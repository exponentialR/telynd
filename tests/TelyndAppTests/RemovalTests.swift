import XCTest
import TelyndCore
@testable import Telynd

final class RemovalTests: XCTestCase {
    private func setup(_ action: @MainActor (ConfigurationStore, URL) throws -> Void) async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try action(ConfigurationStore(directory: directory), directory)
        }
    }
    func testRemovalAndRestorationSurviveRelaunchAndPreserveAllConnectionDetails() async throws {
        try await setup { configuration, directory in
            var computer = Desktop(name: "Lab", target: "reader@host.example", chromeURL: "https://remotedesktop.google.com/access/session/11111111-1111-4111-8111-111111111111", identityPath: "/tmp/private_key", hostPlatform: .linux)
            computer.chromeProfile = ChromeProfileReference(directory: "Profile 1", email: "reader@example.test")
            computer.lastLaunch = Date(timeIntervalSince1970: 1); computer.userConfirmedConnection = Date(timeIntervalSince1970: 2)
            let other = Desktop(name: "Other")
            try configuration.saveDesktops([computer, other])
            let store = AppStore(configuration: configuration)
            XCTAssertTrue(store.updatePreferences { $0.guideDesktopID = computer.id; $0.guideDraft = computer; $0.guideStep = .connect })
            XCTAssertTrue(store.remove(computer.id))
            XCTAssertEqual(store.desktops, [other])
            XCTAssertEqual(store.preferences.removedDesktops, [computer])
            XCTAssertNil(store.preferences.guideDesktopID); XCTAssertNil(store.preferences.guideDraft)
            XCTAssertEqual(store.preferences.guideStep, .computer)
            XCTAssertFalse(store.save(computer)) // A stale editor cannot resurrect a removed record.
            let reopened = AppStore(configuration: configuration)
            XCTAssertEqual(reopened.desktops, [other])
            XCTAssertTrue(reopened.restore(computer.id))
            XCTAssertEqual(reopened.desktops, [other, computer])
            XCTAssertTrue(reopened.preferences.removedDesktops.isEmpty)
            XCTAssertEqual(AppStore(configuration: configuration).desktops, [other, computer])
            let mode = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("preferences.json").path)[.posixPermissions] as? NSNumber
            XCTAssertEqual(mode?.intValue, 0o600)
        }
    }
    func testCommittedRemovalHidesAnUncleanedActiveListAndMultipleRemovalsCanBeRestored() async throws {
        try await setup { configuration, _ in
            let first = Desktop(name: "First"), second = Desktop(name: "Second")
            try configuration.saveDesktops([first, second])
            let store = AppStore(configuration: configuration)
            XCTAssertTrue(store.remove(first.id)); XCTAssertTrue(store.remove(second.id))
            // Simulate interruption before the best-effort active-list cleanup.
            try configuration.saveDesktops([first, second])
            let reopened = AppStore(configuration: configuration)
            XCTAssertTrue(reopened.desktops.isEmpty)
            XCTAssertTrue(reopened.restore(first.id))
            XCTAssertFalse(reopened.restore(first.id))
            XCTAssertEqual(AppStore(configuration: configuration).desktops, [first])
            XCTAssertTrue(reopened.restore(second.id))
            XCTAssertEqual(AppStore(configuration: configuration).desktops, [first, second])
        }
    }
    func testFailedRemovalCommitKeepsTheOriginalAndDoesNotClearSetupProgress() async throws {
        try await setup { configuration, directory in
            let computer = Desktop(name: "Kept")
            try configuration.saveDesktops([computer])
            let store = AppStore(configuration: configuration)
            XCTAssertTrue(store.updatePreferences { $0.guideDesktopID = computer.id; $0.guideDraft = computer })
            let preferencesURL = directory.appendingPathComponent("preferences.json")
            try FileManager.default.removeItem(at: preferencesURL)
            try FileManager.default.createDirectory(at: preferencesURL, withIntermediateDirectories: false)
            try Data("block replacement".utf8).write(to: preferencesURL.appendingPathComponent("block"))
            XCTAssertFalse(store.remove(computer.id))
            XCTAssertEqual(store.desktops, [computer])
            XCTAssertTrue(store.preferences.removedDesktops.isEmpty)
            XCTAssertEqual(store.preferences.guideDesktopID, computer.id)
            XCTAssertNotNil(store.error)
        }
    }
    func testFailedRestoreCommitRemainsArchivedAfterReopening() async throws {
        try await setup { configuration, directory in
            let computer = Desktop(name: "Archived")
            try configuration.saveDesktops([computer])
            let store = AppStore(configuration: configuration)
            XCTAssertTrue(store.remove(computer.id))
            let preferencesURL = directory.appendingPathComponent("preferences.json")
            let archived = try Data(contentsOf: preferencesURL)
            try FileManager.default.removeItem(at: preferencesURL)
            try FileManager.default.createDirectory(at: preferencesURL, withIntermediateDirectories: false)
            XCTAssertFalse(store.restore(computer.id))
            XCTAssertTrue(store.desktops.isEmpty)
            XCTAssertEqual(store.preferences.removedDesktops, [computer])
            // Restore storage after the failed final commit. The active file may
            // already contain the computer, but the archive must still hide it.
            try FileManager.default.removeItem(at: preferencesURL)
            try archived.write(to: preferencesURL)
            let reopened = AppStore(configuration: configuration)
            XCTAssertTrue(reopened.desktops.isEmpty)
            XCTAssertTrue(reopened.restore(computer.id))
            XCTAssertEqual(reopened.desktops, [computer])
        }
    }
    func testRemovalRejectsStaleHostActionsAndDoesNotDeleteKeysOrTerminalReceipts() async throws {
        try await setup { configuration, directory in
            let key = directory.appendingPathComponent("private-key"); try Data("preserved".utf8).write(to: key)
            let computer = Desktop(name: "Lab", target: "reader@host.example", identityPath: key.path, hostPlatform: .linux)
            try configuration.saveDesktops([computer])
            let store = AppStore(configuration: configuration)
            let launchers = directory.appendingPathComponent("Launchers"); try FileManager.default.createDirectory(at: launchers, withIntermediateDirectories: false)
            let receipt = launchers.appendingPathComponent("\(computer.id.uuidString)-setup-access.receipt")
            try Data("preserved receipt".utf8).write(to: receipt)
            XCTAssertTrue(store.remove(computer.id))
            XCTAssertFalse(store.terminal(computer, action: "setup-access"))
            store.check(computer); XCTAssertNil(store.observations[computer.id])
            store.connect(computer); XCTAssertTrue(store.desktops.isEmpty)
            XCTAssertEqual(try String(contentsOf: key), "preserved")
            XCTAssertEqual(try String(contentsOf: receipt), "preserved receipt")
        }
    }
    func testTerminalCompletionRequiresTheSameActionTargetAndKey() async throws {
        try await setup { configuration, directory in
            let computer = Desktop(name: "Lab", target: "reader@host.example", identityPath: "/tmp/key", hostPlatform: .linux)
            let store = AppStore(configuration: configuration)
            let launchers = directory.appendingPathComponent("Launchers"); try FileManager.default.createDirectory(at: launchers, withIntermediateDirectories: false)
            let receipt = launchers.appendingPathComponent("\(computer.id.uuidString)-setup-access.receipt")
            let correct = "TELYND:action=setup-access\nTELYND:target=reader@host.example\nTELYND:identity=/tmp/key\nTELYND:result=ssh_ready\n"
            for wrong in [correct.replacingOccurrences(of: "action=setup-access", with: "action=install"), correct.replacingOccurrences(of: "reader@host.example", with: "other@host.example"), correct.replacingOccurrences(of: "/tmp/key", with: "/tmp/other_key")] {
                try wrong.write(to: receipt, atomically: true, encoding: .utf8)
                XCTAssertNil(store.terminalResult(computer, action: "setup-access"))
            }
            try correct.write(to: receipt, atomically: true, encoding: .utf8)
            XCTAssertEqual(store.terminalResult(computer, action: "setup-access"), "ssh_ready")
        }
    }
}
