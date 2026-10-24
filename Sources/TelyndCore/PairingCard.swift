import Foundation
import CryptoKit

public enum PairingError: LocalizedError {
    case invalid, expired, cancelled, unreachable
    public var errorDescription: String? {
        switch self {
        case .invalid: return "This is not a supported Telynd setup card. Copy a fresh card from Telynd Setup on the remote PC."
        case .expired: return "This setup card has expired. Choose Copy setup card again on the remote PC."
        case .cancelled: return "Connection checking was cancelled."
        case .unreachable: return "No matching connection was found. Keep the remote PC awake and connect both devices to the same network or existing private VPN, then try again. Your network administrator may need to allow SSH access."
        }
    }
}

public struct PairingKey: Codable, Equatable, Sendable {
    public let type: String
    public let key: String
    public init(type: String, key: String) { self.type = type; self.key = key }
    public var valid: Bool {
        guard ["ssh-ed25519", "ecdsa-sha2-nistp256", "ssh-rsa"].contains(type), key.count <= 2048,
              let data = Data(base64Encoded: key), data.count >= 19, data.count <= 1536 else { return false }
        let count = data.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard count == type.utf8.count, data.count >= count + 4,
              String(data: data.subdata(in: 4..<(count + 4)), encoding: .utf8) == type else { return false }
        if type == "ssh-ed25519" { return data.count == 51 && data[15..<19].elementsEqual([0, 0, 0, 32]) }
        return true
    }
    public var fingerprint: String {
        guard let data = Data(base64Encoded: key) else { return "" }
        return "SHA256:" + Data(SHA256.hash(data: data)).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }
}

public struct PairingCard: Codable, Equatable, Sendable {
    public let version: Int
    public let platform: String
    public let createdAt: TimeInterval
    public let username: String
    public let hostname: String
    public let addresses: [String]
    public let hostKeys: [PairingKey]
    public init(version: Int = 1, platform: String = "linux", createdAt: TimeInterval, username: String, hostname: String, addresses: [String], hostKeys: [PairingKey]) {
        self.version = version; self.platform = platform; self.createdAt = createdAt; self.username = username; self.hostname = hostname; self.addresses = addresses; self.hostKeys = hostKeys
    }
    public static func addressAllowed(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.count <= 3, part.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = Int(part), number <= 255, String(number) == part else { return nil }
            return number
        }
        return numbers.count == 4 && numbers[0] > 0 && numbers[0] < 224 && numbers[0] != 127 && !(numbers[0] == 169 && numbers[1] == 254) && numbers[3] != 255
    }
    public func validate(now: Date = Date()) throws {
        guard version == 1, platform == "linux", username != "root", InputValidation.target(username + "@host"),
              !hostname.isEmpty, hostname.utf8.count <= 128, !hostname.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !addresses.isEmpty, addresses.count <= 6, Set(addresses).count == addresses.count, addresses.allSatisfy(Self.addressAllowed),
              !hostKeys.isEmpty, hostKeys.count <= 3, Set(hostKeys.map(\.type)).count == hostKeys.count, hostKeys.allSatisfy(\.valid) else { throw PairingError.invalid }
        guard createdAt.isFinite, createdAt <= now.timeIntervalSince1970 + 60, now.timeIntervalSince1970 - createdAt < 900 else { throw PairingError.expired }
    }
    public static func parse(_ text: String, now: Date = Date()) throws -> PairingCard {
        guard text.utf8.count <= 16_384 else { throw PairingError.invalid }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("TELYND1:"), let data = Data(base64Encoded: String(value.dropFirst(8))), data.count <= 8192,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["version", "platform", "createdAt", "username", "hostname", "addresses", "hostKeys"]),
              let keys = object["hostKeys"] as? [[String: Any]], keys.allSatisfy({ Set($0.keys) == Set(["type", "key"]) }),
              let card = try? JSONDecoder().decode(PairingCard.self, from: data) else { throw PairingError.invalid }
        try card.validate(now: now)
        return card
    }
}

public final class PairingProbeControl: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    public init() {}
    public func cancel() { lock.lock(); stopped = true; lock.unlock() }
    public var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

public enum PairingProbe {
    /// Contacts only the addresses in an explicitly approved card. No login,
    /// user SSH configuration, host-trust writes or remote commands are involved.
    public static func find(_ card: PairingCard, control: PairingProbeControl, now: () -> Date = { Date() }, scan: ((String) -> String)? = nil) throws -> String {
        try card.validate(now: now())
        let expected = Set(card.hostKeys.map { $0.type + " " + $0.key })
        for address in card.addresses {
            guard !control.cancelled else { throw PairingError.cancelled }
            let output = scan?(address) ?? self.scan(address)
            guard !control.cancelled else { throw PairingError.cancelled }
            try card.validate(now: now())
            for line in output.split(whereSeparator: \.isNewline) {
                let parts = line.split(whereSeparator: \.isWhitespace)
                if parts.count == 3, parts[0] == Substring(address), expected.contains(String(parts[1]) + " " + String(parts[2])) { return address }
            }
        }
        throw PairingError.unreachable
    }
    private static func scan(_ address: String) -> String {
        let result = ProcessRunner.run("/usr/bin/ssh-keyscan", arguments: ["-T", "3", "-t", "ed25519,ecdsa,rsa", address], timeout: 4, outputLimit: 16_384, mergeError: false)
        return result.code == 0 ? result.output : ""
    }
}
