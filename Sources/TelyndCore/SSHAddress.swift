import Foundation

public struct SSHAddress: Equatable {
    public var username: String
    public var host: String
    public init(target: String? = nil) {
        let parts = (target ?? "").split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        username = parts.count == 2 ? String(parts[0]) : ""
        host = parts.count == 2 ? String(parts[1]) : ""
    }
    public var target: String? {
        let value = username.trimmingCharacters(in: .whitespacesAndNewlines) + "@" + host.trimmingCharacters(in: .whitespacesAndNewlines)
        return InputValidation.target(value) ? value : nil
    }
    public static func pasted(_ value: String?) -> SSHAddress? {
        guard let value, value.utf8.count <= 1024 else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.split(whereSeparator: \.isWhitespace)
        let candidate = parts.count == 2 && parts[0] == "ssh" ? String(parts[1]) : text
        let address = SSHAddress(target: candidate)
        return address.target != nil ? address : nil
    }
}
