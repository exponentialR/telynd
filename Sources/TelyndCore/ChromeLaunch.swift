import Foundation

public enum ChromeLaunch {
    public static func arguments(desktop: Desktop, profiles: [ChromeProfile], applicationAvailable: Bool) throws -> [String] {
        guard desktop.hasDirectConnection else { throw ConfigurationError.invalidDesktop }
        let profile = try ChromeProfiles.selected(in: profiles, reference: desktop.chromeProfile)
        guard applicationAvailable else { throw ConfigurationError.chromeMissing }
        return ["--profile-directory=\(profile.directory)", desktop.chromeURL]
    }
}
