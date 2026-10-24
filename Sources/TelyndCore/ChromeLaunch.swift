import Foundation

public enum ChromeLaunch {
    public enum Presentation { case window, tab }
    public static func arguments(desktop: Desktop, profiles: [ChromeProfile], applicationAvailable: Bool, presentation: Presentation = .window) throws -> [String] {
        guard desktop.hasDirectConnection else { throw ConfigurationError.invalidDesktop }
        let profile = try ChromeProfiles.selected(in: profiles, reference: desktop.chromeProfile)
        guard applicationAvailable else { throw ConfigurationError.chromeMissing }
        return ["--profile-directory=\(profile.directory)", presentation == .window ? "--app=\(desktop.chromeURL)" : desktop.chromeURL]
    }
}
