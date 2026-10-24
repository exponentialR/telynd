import Foundation

public enum ChromeLaunch {
    public static func arguments(url: String, profiles: [ChromeProfile], preferences: Preferences, applicationAvailable: Bool) throws -> [String] {
        guard InputValidation.chromeURL(url) else { throw ConfigurationError.invalidDesktop }
        let profile = try ChromeProfiles.selected(in: profiles, preferences: preferences)
        guard applicationAvailable else { throw ConfigurationError.chromeMissing }
        return ["--profile-directory=\(profile.directory)", url]
    }
}
