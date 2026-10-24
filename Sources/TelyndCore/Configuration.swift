import Foundation

public final class ConfigurationStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func migrateLegacy(from legacy: URL) throws {
        for name in ["desktops.json", "preferences.json"] {
            let source = legacy.appendingPathComponent(name), destination = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: destination.path), FileManager.default.fileExists(atPath: source.path) {
                try prepareDirectory()
                try FileManager.default.copyItem(at: source, to: destination)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            }
        }
    }
    public func loadDesktops() throws -> [Desktop] {
        let url = directory.appendingPathComponent("desktops.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let items = try JSONDecoder().decode([Desktop].self, from: Data(contentsOf: url))
        guard items.allSatisfy(\.valid) else { throw ConfigurationError.invalidDesktop }
        guard Set(items.map(\.id)).count == items.count else { throw ConfigurationError.duplicateIDs }
        return items
    }
    public func loadPreferences(existingDesktops: Bool) throws -> Preferences {
        let url = directory.appendingPathComponent("preferences.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            var p = Preferences(); p.guideCompleted = existingDesktops; return p
        }
        return try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url))
    }
    public func saveDesktops(_ value: [Desktop]) throws {
        guard value.allSatisfy(\.valid) else { throw ConfigurationError.invalidDesktop }
        guard Set(value.map(\.id)).count == value.count else { throw ConfigurationError.duplicateIDs }
        try write(value, name: "desktops.json")
    }
    public func savePreferences(_ value: Preferences) throws { try write(value, name: "preferences.json") }
    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
    private func write<T: Encodable>(_ value: T, name: String) throws {
        try prepareDirectory()
        let data = try JSONEncoder().encode(value)
        // Write the private temporary file first, then atomically replace the destination.
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600])
        try data.write(to: temporary)
        let destination = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else { try FileManager.default.moveItem(at: temporary, to: destination) }
        // Replacement may retain an older destination's metadata.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}

public struct ChromeProfile: Identifiable, Equatable {
    public var id: String { directory }
    public let directory: String
    public let name: String
    public let email: String
    public var signedIn: Bool { !email.isEmpty }
    public var label: String { email.isEmpty ? "\(name) — sign in within Chrome" : "\(name) — \(email)" }
}

public enum ChromeProfiles {
    public static func parse(_ data: Data) throws -> [ChromeProfile] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: [String: Any]] else { throw ConfigurationError.unreadableProfiles }
        return cache.compactMap { directory, value in
            guard !directory.isEmpty, directory != ".", directory != "..", !directory.contains("/"), !directory.contains("\\"), !directory.contains("\0") else { return nil }
            return ChromeProfile(directory: directory, name: value["name"] as? String ?? directory, email: value["user_name"] as? String ?? "")
        }.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }
    public static func selected(in profiles: [ChromeProfile], preferences: Preferences) throws -> ChromeProfile {
        if let id = preferences.chromeProfileDirectory {
            guard let item = profiles.first(where: { $0.directory == id && $0.signedIn && $0.email.lowercased() == preferences.chromeProfileEmail.lowercased() }) else { throw ConfigurationError.invalidProfile }
            return item
        }
        let matches = profiles.filter { $0.signedIn && $0.email.lowercased() == preferences.chromeProfileEmail.lowercased() }
        guard matches.count == 1 else { throw ConfigurationError.invalidProfile }
        return matches[0]
    }
}
