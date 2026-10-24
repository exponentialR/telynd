import XCTest
import TelyndCore
@testable import Telynd

final class AppConnectionProfilesTests: XCTestCase {
    private func metadata(_ entries: [String: String], in configuration: ConfigurationStore) throws {
        try FileManager.default.createDirectory(at: configuration.directory, withIntermediateDirectories: true)
        let profiles = entries.mapValues { ["name": $0, "user_name": $0] }
        try JSONSerialization.data(withJSONObject: ["profile": ["info_cache": profiles]]).write(to: configuration.directory.appendingPathComponent("chrome-state.json"))
    }
    func testExistingGlobalChoiceMigratesOnceWithoutChangingSSHOrEvidence() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let configuration = ConfigurationStore(directory: directory)
            try metadata(["Profile 1": "personal@example.test", "Profile 2": "work@example.test"], in: configuration)
            var desktop = Desktop(name: "Existing", target: "reader@host.example", identityPath: "/tmp/private_key", hostPlatform: .linux)
            desktop.lastLaunch = Date(timeIntervalSince1970: 1)
            desktop.userConfirmedConnection = Date(timeIntervalSince1970: 2)
            try configuration.saveDesktops([desktop])
            var preferences = Preferences(); preferences.schemaVersion = 1; preferences.chromeProfileDirectory = "Profile 1"; preferences.chromeProfileEmail = "personal@example.test"; preferences.guideDraft = desktop
            try configuration.savePreferences(preferences)
            let store = AppStore(configuration: configuration)
            var expected = desktop; expected.chromeProfile = ChromeProfileReference(directory: "Profile 1", email: "personal@example.test")
            XCTAssertEqual(store.desktops, [expected])
            XCTAssertEqual(store.preferences.guideDraft, expected)
            XCTAssertTrue(store.preferences.connectionProfilesMigrated)
            XCTAssertEqual(store.preferences.schemaVersion, 3)
            XCTAssertEqual(try configuration.loadDesktops(), [expected])
            // A later unfinished draft must not inherit the obsolete global preference.
            var unfinished = Desktop(name: "New draft")
            unfinished.chromeURL = "still typing"
            XCTAssertTrue(store.updatePreferences { $0.guideDraft = unfinished; $0.chromeProfileDirectory = "Profile 2"; $0.chromeProfileEmail = "work@example.test" })
            let reopened = AppStore(configuration: configuration)
            XCTAssertEqual(reopened.desktops, [expected])
            XCTAssertNil(reopened.preferences.guideDraft?.chromeProfile)
            XCTAssertNil(reopened.newDesktop().chromeProfile) // Multiple accounts require a choice.
        }
    }
    func testUnsafeLegacyProfileStopsMigrationWithoutReplacingTheSavedComputer() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let configuration = ConfigurationStore(directory: directory)
            let original = Desktop(name: "Preserved", target: "reader@host.example")
            try configuration.saveDesktops([original])
            let before = try Data(contentsOf: directory.appendingPathComponent("desktops.json"))
            var preferences = Preferences(); preferences.schemaVersion = 1
            preferences.chromeProfileDirectory = "../unsafe"; preferences.chromeProfileEmail = "personal@example.test"
            try configuration.savePreferences(preferences)
            let store = AppStore(configuration: configuration)
            XCTAssertTrue(store.writeLocked)
            XCTAssertNotNil(store.error)
            XCTAssertFalse(store.preferences.connectionProfilesMigrated)
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("desktops.json")), before)
            XCTAssertFalse(store.save(original))
        }
    }
    func testSingleAccountDefaultAndChangedComputerAccountClearsOnlyItsConnectionEvidence() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let configuration = ConfigurationStore(directory: directory)
            try metadata(["Profile 1": "personal@example.test"], in: configuration)
            let store = AppStore(configuration: configuration)
            var first = store.newDesktop(); first.name = "First"
            first.chromeURL = "https://remotedesktop.google.com/access/session/11111111-1111-4111-8111-111111111111"
            first.lastLaunch = Date(timeIntervalSince1970: 1); first.userConfirmedConnection = Date(timeIntervalSince1970: 2)
            XCTAssertEqual(first.chromeProfile?.directory, "Profile 1")
            var second = first; second.id = UUID(); second.name = "Second"
            XCTAssertTrue(store.save(first)); XCTAssertTrue(store.save(second))
            try metadata(["Profile 2": "work@example.test"], in: configuration); store.refreshProfiles()
            XCTAssertFalse(store.profileReady(for: first))
            XCTAssertEqual(store.desktops[0].chromeProfile, first.chromeProfile)
            first.chromeProfile = store.profiles[0].reference
            XCTAssertTrue(store.saveGuideDraft(first))
            XCTAssertNil(store.desktops[0].lastLaunch)
            XCTAssertNil(store.desktops[0].userConfirmedConnection)
            XCTAssertEqual(store.preferences.guideDraft, store.desktops[0])
            XCTAssertEqual(store.desktops[1], second)
        }
    }
    func testConnectUsesSavedComputerAccountAndMissingProfileDoesNotRecordALaunch() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let configuration = ConfigurationStore(directory: directory)
            try metadata(["Profile 1": "personal@example.test", "Profile 2": "work@example.test"], in: configuration)
            let store = AppStore(configuration: configuration)
            for profile in store.profiles {
                var desktop = Desktop(name: profile.email, chromeURL: "https://remotedesktop.google.com/access/session/11111111-1111-4111-8111-111111111111")
                desktop.chromeProfile = profile.reference
                XCTAssertTrue(store.save(desktop)); store.connect(desktop)
                XCTAssertNotNil(store.desktops.first(where: { $0.id == desktop.id })?.lastLaunch)
                XCTAssertNil(store.error)
            }
            var missing = Desktop(name: "Missing", chromeURL: "https://remotedesktop.google.com/access/session/11111111-1111-4111-8111-111111111111")
            missing.chromeProfile = ChromeProfileReference(directory: "Profile 3", email: "missing@example.test")
            XCTAssertTrue(store.save(missing)); store.connect(missing)
            XCTAssertNil(store.desktops.last?.lastLaunch)
            XCTAssertNotNil(store.error)
        }
    }
}
