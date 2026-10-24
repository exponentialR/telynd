import XCTest
import TelyndCore
@testable import Telynd

final class GuidePersistenceTests: XCTestCase {
    func testCorrectedLegacyConnectionSurvivesBackCloseAndReopen() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let configuration = ConfigurationStore(directory: directory)
            let legacy = Desktop(name: "Legacy computer")
            try configuration.saveDesktops([legacy])
            var preferences = Preferences()
            preferences.guideStep = .connect
            preferences.guideDesktopID = legacy.id
            preferences.guideDraft = legacy
            try configuration.savePreferences(preferences)

            let store = AppStore(configuration: configuration)
            var corrected = legacy
            corrected.chromeURL = "https://remotedesktop.google.com/access/session/11111111-1111-4111-8111-111111111111"
            XCTAssertTrue(store.saveGuideDraft(corrected))
            XCTAssertTrue(store.updatePreferences { $0.guideStep = .computer }) // Back.
            store.showGuide = false // Save progress and close.

            let reopened = AppStore(configuration: configuration)
            XCTAssertTrue(reopened.showGuide)
            XCTAssertEqual(reopened.preferences.guideStep, .computer)
            XCTAssertEqual(reopened.preferences.guideDesktopID, legacy.id)
            XCTAssertEqual(reopened.preferences.guideDraft, corrected)
            XCTAssertEqual(reopened.desktops, [corrected])
            XCTAssertTrue(try XCTUnwrap(reopened.preferences.guideDraft).hasDirectConnection)
        }
    }

    func testGuideDraftUsesCanonicalSavedConnectionEvidence() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let configuration = ConfigurationStore(directory: directory)
            var old = Desktop(name: "Computer", chromeURL: "https://remotedesktop.google.com/access/session/11111111-1111-4111-8111-111111111111")
            old.lastLaunch = Date(timeIntervalSince1970: 1)
            old.userConfirmedConnection = Date(timeIntervalSince1970: 2)
            try configuration.saveDesktops([old])
            let store = AppStore(configuration: configuration)
            var changed = old
            changed.chromeURL = "https://remotedesktop.google.com/access/session/22222222-2222-4222-8222-222222222222"
            XCTAssertTrue(store.saveGuideDraft(changed))
            let saved = try XCTUnwrap(store.desktops.first)
            let draft = try XCTUnwrap(configuration.loadPreferences(existingDesktops: true).guideDraft)
            XCTAssertEqual(draft, saved)
            XCTAssertNil(draft.lastLaunch)
            XCTAssertNil(draft.userConfirmedConnection)
        }
    }
}
