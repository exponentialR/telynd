import Foundation

public enum InputValidation {
    public static let devicePicker = "https://remotedesktop.google.com/access"
    public static func target(_ value: String?) -> Bool {
        guard let value, !value.isEmpty, !value.contains("\n"), !value.contains("\r"), !value.contains("\0") else { return false }
        return value.range(of: "^[A-Za-z_][A-Za-z0-9_-]*@[A-Za-z0-9][A-Za-z0-9.-]*$", options: .regularExpression) != nil
    }
    public static func chromeURL(_ value: String) -> Bool {
        guard let url = URLComponents(string: value), url.scheme == "https",
              url.host == "remotedesktop.google.com", url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil,
              !value.contains("%") else { return false }
        if url.path == "/access" || url.path == "/access/" { return true }
        let pieces = url.path.split(separator: "/", omittingEmptySubsequences: false)
        return pieces.count == 4 && pieces[1] == "access" && pieces[2] == "session" && UUID(uuidString: String(pieces[3])) != nil
    }
    public static func directChromeURL(_ value: String) -> Bool {
        chromeURL(value) && URLComponents(string: value)?.path.hasPrefix("/access/session/") == true
    }
    public static func identityPath(_ value: String) -> Bool {
        value.hasPrefix("/") && !value.contains("\n") && !value.contains("\r") && !value.contains("\0")
    }
    public static func profileDirectory(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\\") && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}

public struct ChromeProfileReference: Codable, Equatable, Sendable {
    public var directory: String?
    public var email: String
    public init(directory: String?, email: String) { self.directory = directory; self.email = email }
    public var valid: Bool { !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (directory == nil || InputValidation.profileDirectory(directory!)) }
}

public struct Desktop: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var target: String?
    public var chromeURL: String
    public var symbol: String
    public var identityPath: String?
    public var hostPlatform: HostPlatform
    public var chromeProfile: ChromeProfileReference?
    public var lastLaunch: Date?
    public var userConfirmedConnection: Date?
    public init(id: UUID = UUID(), name: String, target: String? = nil, chromeURL: String = InputValidation.devicePicker, symbol: String = "desktopcomputer", identityPath: String? = nil, hostPlatform: HostPlatform = .unknown) {
        self.id = id; self.name = name; self.target = target?.isEmpty == true ? nil : target
        self.chromeURL = chromeURL; self.symbol = symbol; self.identityPath = identityPath
        self.hostPlatform = hostPlatform
    }
    enum CodingKeys: String, CodingKey { case id, name, target, chromeURL, symbol, identityPath, hostPlatform, chromeProfile, lastLaunch, userConfirmedConnection }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        target = try c.decodeIfPresent(String.self, forKey: .target)
        if target?.isEmpty == true { target = nil }
        chromeURL = try c.decodeIfPresent(String.self, forKey: .chromeURL) ?? InputValidation.devicePicker
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "desktopcomputer"
        identityPath = try c.decodeIfPresent(String.self, forKey: .identityPath)
        hostPlatform = try c.decodeIfPresent(HostPlatform.self, forKey: .hostPlatform) ?? .unknown
        chromeProfile = try c.decodeIfPresent(ChromeProfileReference.self, forKey: .chromeProfile)
        lastLaunch = try c.decodeIfPresent(Date.self, forKey: .lastLaunch)
        userConfirmedConnection = try c.decodeIfPresent(Date.self, forKey: .userConfirmedConnection)
    }
    public var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && InputValidation.chromeURL(chromeURL)
            && (target == nil || InputValidation.target(target)) && (identityPath == nil || InputValidation.identityPath(identityPath!))
            && (chromeProfile == nil || chromeProfile!.valid)
    }
    public var hasDirectConnection: Bool { InputValidation.directChromeURL(chromeURL) }
}

public enum GuideStep: Int, Codable, CaseIterable {
    case welcome, profile, computer, connect, recovery, finished
    public var title: String {
        switch self {
        case .welcome: return "Welcome to Telynd"
        case .profile: return "Add your first computer"
        case .computer: return "Add your first computer"
        case .connect: return "Open your remote desktop"
        case .recovery: return "Would you like automatic recovery?"
        case .finished: return "Your workspace is ready"
        }
    }
}

public struct Preferences: Codable, Equatable {
    public var schemaVersion: Int = 2
    public var chromeProfileEmail: String = ""
    public var chromeProfileDirectory: String?
    public var guideStep: GuideStep = .welcome
    public var guideDraft: Desktop?
    public var guideDesktopID: UUID?
    public var guideCompleted: Bool = false
    public var connectionProfilesMigrated: Bool = false
    public init() {}
    public var legacyChromeProfile: ChromeProfileReference? {
        chromeProfileEmail.isEmpty ? nil : ChromeProfileReference(directory: chromeProfileDirectory, email: chromeProfileEmail)
    }
    enum CodingKeys: String, CodingKey { case schemaVersion, chromeProfileEmail, chromeProfileDirectory, guideStep, guideDraft, guideDesktopID, guideCompleted, connectionProfilesMigrated }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard schemaVersion == 1 || schemaVersion == 2 else { throw ConfigurationError.unsupportedVersion }
        chromeProfileEmail = try c.decodeIfPresent(String.self, forKey: .chromeProfileEmail) ?? ""
        chromeProfileDirectory = try c.decodeIfPresent(String.self, forKey: .chromeProfileDirectory)
        guideStep = try c.decodeIfPresent(GuideStep.self, forKey: .guideStep) ?? .welcome
        guideDraft = try c.decodeIfPresent(Desktop.self, forKey: .guideDraft)
        guideDesktopID = try c.decodeIfPresent(UUID.self, forKey: .guideDesktopID)
        // An existing email-only installation is an existing user, not a first launch.
        guideCompleted = try c.decodeIfPresent(Bool.self, forKey: .guideCompleted) ?? !chromeProfileEmail.isEmpty
        connectionProfilesMigrated = try c.decodeIfPresent(Bool.self, forKey: .connectionProfilesMigrated) ?? false
    }
}

public enum ConfigurationError: LocalizedError, Equatable {
    case unsupportedVersion, invalidDesktop, duplicateIDs, invalidProfile, unreadableProfiles, noProfiles, chromeMissing, writeLocked
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "These settings were created by a newer Telynd version. They have been preserved."
        case .invalidDesktop: return "A saved desktop contains unsupported details. Your settings have been preserved; correct the file or restore a backup before saving."
        case .duplicateIDs: return "Saved desktop identities are duplicated. Your settings have been preserved."
        case .invalidProfile: return "The selected Chrome profile is unavailable. Refresh the profile list and select it again."
        case .unreadableProfiles: return "Chrome profile metadata could not be read. Open Chrome, then refresh."
        case .chromeMissing: return "Google Chrome was not found. Install Chrome, sign into your chosen profile and refresh."
        case .noProfiles: return "No signed-in Chrome profiles were found. Sign in within Chrome, then refresh."
        case .writeLocked: return "Settings could not be loaded safely. Reopen Telynd after correcting the saved file; it has not been overwritten."
        }
    }
}
