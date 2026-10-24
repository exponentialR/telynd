import XCTest
@testable import TelyndCore

final class ConnectionProfilesTests: XCTestCase {
    private let link = "https://remotedesktop.google.com/access/session/11111111-1111-4111-8111-111111111111"
    private func profiles(_ values: [String: String]) throws -> [ChromeProfile] {
        let entries = values.mapValues { ["name": $0, "user_name": $0] }
        return try ChromeProfiles.parse(JSONSerialization.data(withJSONObject: ["profile": ["info_cache": entries]]))
    }
    func testEachComputerLaunchesItsOwnProfileAndExactDestination() throws {
        let available = try profiles(["Profile 1": "personal@example.test", "Profile 2": "work@example.test"])
        for profile in available {
            var desktop = Desktop(name: "Computer", chromeURL: link)
            desktop.chromeProfile = profile.reference
            XCTAssertEqual(try ChromeLaunch.arguments(desktop: desktop, profiles: available, applicationAvailable: true), ["--profile-directory=\(profile.directory)", link])
        }
    }
    func testMissingChangedAndUnresolvedProfilesNeverFallBackToAnotherAccount() throws {
        let available = try profiles(["Profile 2": "other@example.test", "Profile 3": "personal@example.test"])
        for reference in [nil, ChromeProfileReference(directory: "Profile 1", email: "personal@example.test"), ChromeProfileReference(directory: "Profile 2", email: "personal@example.test"), ChromeProfileReference(directory: nil, email: "personal@example.test")] {
            var desktop = Desktop(name: "Computer", chromeURL: link); desktop.chromeProfile = reference
            XCTAssertThrowsError(try ChromeLaunch.arguments(desktop: desktop, profiles: available, applicationAvailable: true))
        }
    }
    func testLegacyMigrationPreservesExistingAssociationsAndUnavailableSelections() throws {
        let available = try profiles(["Profile 2": "work@example.test"])
        let legacy = ChromeProfileReference(directory: "Profile 1", email: "personal@example.test")
        var desktop = Desktop(name: "Computer")
        let migrated = ChromeProfiles.migrate(desktop, legacy: legacy, profiles: available)
        XCTAssertEqual(migrated.id, desktop.id)
        XCTAssertEqual(migrated.chromeProfile, legacy)
        desktop.chromeProfile = available[0].reference
        XCTAssertEqual(ChromeProfiles.migrate(desktop, legacy: legacy, profiles: available), desktop)
    }
    func testEmailOnlyMigrationRequiresAnUnambiguousMatchAndFreezesDirectory() throws {
        let legacy = ChromeProfileReference(directory: nil, email: "personal@example.test")
        let original = Desktop(name: "Computer")
        let available = try profiles(["Profile 1": legacy.email])
        XCTAssertEqual(ChromeProfiles.migrate(original, legacy: legacy, profiles: available).chromeProfile, available[0].reference)
        let ambiguous = try profiles(["Profile 1": legacy.email, "Profile 2": legacy.email])
        let unresolved = ChromeProfiles.migrate(original, legacy: legacy, profiles: ambiguous)
        XCTAssertEqual(unresolved.chromeProfile, legacy)
        XCTAssertThrowsError(try ChromeProfiles.selected(in: ambiguous, reference: unresolved.chromeProfile))
        XCTAssertEqual(ChromeProfiles.migrate(original, legacy: nil, profiles: available), original)
    }
    func testSavedProfileRoundTripsAndUnsafeDirectoriesAreRejected() throws {
        var desktop = Desktop(name: "Computer", chromeURL: link)
        desktop.chromeProfile = ChromeProfileReference(directory: "Profile 1", email: "personal@example.test")
        XCTAssertEqual(try JSONDecoder().decode(Desktop.self, from: JSONEncoder().encode(desktop)), desktop)
        for directory in ["", ".", "..", "../Profile 1", "a/b", "a\\b", "a\n", "a\0"] {
            desktop.chromeProfile?.directory = directory
            XCTAssertFalse(desktop.valid, directory)
        }
    }
}
