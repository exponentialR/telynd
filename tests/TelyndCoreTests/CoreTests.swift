import XCTest
@testable import TelyndCore

final class CoreTests: XCTestCase {
    func testOnlySupportedGoogleURLsAreAccepted() {
        XCTAssertTrue(InputValidation.chromeURL(InputValidation.devicePicker))
        XCTAssertFalse(InputValidation.target("reader@host.example\n"))
        XCTAssertTrue(InputValidation.chromeURL("https://remotedesktop.google.com/access/session/484e7079-80ab-45f8-8a4f-96d517f8cfea"))
        for value in ["http://remotedesktop.google.com/access", "https://remotedesktop.google.com.evil.test/access", "https://user@remotedesktop.google.com/access", "https://remotedesktop.google.com:443/access", "https://remotedesktop.google.com/support", "https://remotedesktop.google.com/access?token=secret", "https://remotedesktop.google.com/access/session/not-an-id", "https://remotedesktop.google.com/access/%2e%2e/support"] {
            XCTAssertFalse(InputValidation.chromeURL(value), value)
        }
    }
    func testOldDesktopRetainsIdentityAndConnectionOnlyRoundTrips() throws {
        let id = UUID()
        let legacy = Data("[{\"id\":\"\(id)\",\"name\":\"Lab\",\"target\":\"researcher@workstation.example\",\"chromeURL\":\"https://remotedesktop.google.com/access\",\"symbol\":\"desktopcomputer\"}]".utf8)
        let old = try JSONDecoder().decode([Desktop].self, from: legacy)[0]
        XCTAssertEqual(old.id, id); XCTAssertEqual(old.target, "researcher@workstation.example")
        let new = Desktop(name: "Home")
        XCTAssertNil(new.target); XCTAssertTrue(new.valid)
        XCTAssertEqual(try JSONDecoder().decode(Desktop.self, from: JSONEncoder().encode(new)), new)
    }
    func withStore(_ action: (ConfigurationStore, URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try action(ConfigurationStore(directory: dir), dir)
    }
    func testCorruptSettingsAreNotReplacedByLoading() throws {
        try withStore { store, dir in
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = Data("not json".utf8), url = dir.appendingPathComponent("desktops.json")
            try data.write(to: url)
            XCTAssertThrowsError(try store.loadDesktops())
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }
    func testPersistenceAndPrivatePermissions() throws {
        try withStore { store, dir in
            let first = Desktop(name: "Home"), second = Desktop(name: "Lab")
            try store.saveDesktops([first])
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dir.appendingPathComponent("desktops.json").path)
            try store.saveDesktops([first, second])
            XCTAssertEqual(try store.loadDesktops(), [first, second])
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("desktops.json").path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
    }
    func testMigrationNeverOverwritesCurrentSettings() throws {
        try withStore { store, dir in
            let legacy = dir.appendingPathComponent("legacy")
            try ConfigurationStore(directory: legacy).saveDesktops([Desktop(name: "Old")])
            try store.saveDesktops([Desktop(name: "Current")])
            try store.migrateLegacy(from: legacy)
            XCTAssertEqual(try store.loadDesktops().first?.name, "Current")
        }
    }
    func testFutureSchemaAndDuplicateIDsAreRejected() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(Preferences.self, from: Data("{\"schemaVersion\":2}".utf8)))
        try withStore { store, _ in
            let item = Desktop(name: "Home")
            XCTAssertThrowsError(try store.saveDesktops([item, item]))
        }
    }
    func testGuideResumesAndExistingUsersAreNotForcedThroughIt() throws {
        let legacy = try JSONDecoder().decode(Preferences.self, from: Data("{\"chromeProfileEmail\":\"reader@example.test\"}".utf8))
        XCTAssertTrue(legacy.guideCompleted)
        try withStore { store, _ in
            var prefs = Preferences(); prefs.guideStep = .connect; prefs.guideDesktopID = UUID(); prefs.guideDraft = Desktop(name: "Unfinished", chromeURL: "still typing")
            try store.savePreferences(prefs)
            XCTAssertEqual(try store.loadPreferences(existingDesktops: false), prefs)
        }
    }
    let metadata = Data("{\"profile\":{\"info_cache\":{\"Default\":{\"name\":\"Local\"},\"Profile 1\":{\"name\":\"Research\",\"user_name\":\"reader@example.test\"},\"../escape\":{\"user_name\":\"bad@example.test\"}}}}".utf8)
    func testProfileDiscoveryAndEmailMigration() throws {
        let profiles = try ChromeProfiles.parse(metadata)
        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(profiles.filter(\.signedIn).count, 1)
        var p = Preferences(); p.chromeProfileEmail = "reader@example.test"
        XCTAssertEqual(try ChromeProfiles.selected(in: profiles, preferences: p).directory, "Profile 1")
        p.chromeProfileDirectory = "Profile 2"
        XCTAssertThrowsError(try ChromeProfiles.selected(in: profiles, preferences: p))
        XCTAssertThrowsError(try ChromeProfiles.parse(Data("{}".utf8)))
    }
    func testAmbiguousProfileMigrationRequiresExplicitSelection() throws {
        let profiles = try ChromeProfiles.parse(Data("{\"profile\":{\"info_cache\":{\"Profile 1\":{\"user_name\":\"reader@example.test\"},\"Profile 2\":{\"user_name\":\"reader@example.test\"}}}}".utf8))
        var p = Preferences(); p.chromeProfileEmail = "reader@example.test"
        XCTAssertThrowsError(try ChromeProfiles.selected(in: profiles, preferences: p))
    }
    func testRecoveryEvidenceDoesNotClaimAGoogleSession() {
        let now = Date()
        let report = ReadinessReport(output: "TELYND:ssh=ready\nTELYND:os=linux\nTELYND:systemd=available\nTELYND:service=active\nTELYND:installation=missing", checkedAt: now)
        XCTAssertFalse(report.recoveryEnabled)
        XCTAssertEqual(report.configurationLabel(at: now), "Recovery not configured")
        XCTAssertEqual(report.configurationLabel(at: now.addingTimeInterval(301)), "Verification is stale")
        let installed = ReadinessReport(output: "TELYND:ssh=ready\nTELYND:os=linux\nTELYND:systemd=available\nTELYND:installation=verified\nTELYND:timer=active\nTELYND:timer_enabled=enabled\nTELYND:service=failed")
        XCTAssertTrue(installed.recoveryEnabled)
        XCTAssertEqual(installed.serviceLabel, "failed")
        let disabled = ReadinessReport(output: "TELYND:service=inactive\nTELYND:chrome_enabled=disabled")
        XCTAssertEqual(disabled.serviceLabel, "inactive (disabled)")
    }
    func testSSHFailuresHaveDifferentNextActions() {
        XCTAssertEqual(SSHResult(code: 255, output: "Permission denied"), .authenticationRequired)
        XCTAssertEqual(SSHResult(code: 255, output: "REMOTE HOST IDENTIFICATION HAS CHANGED"), .identityChanged)
        XCTAssertEqual(SSHResult(code: 255, output: "Host key verification failed"), .identityNeedsVerification)
        XCTAssertEqual(SSHResult(code: 255, output: "Connection refused"), .unreachable)
    }
    func testProcessTimeoutAndOutputLimitDiscardPartialSuccess() {
        let start = Date()
        let timeout = ProcessRunner.run("/bin/sh", arguments: ["-c", "printf 'TELYND:ssh=ready\\n'; exec sleep 10"], timeout: 0.15)
        XCTAssertEqual(timeout.code, -2)
        XCTAssertFalse(timeout.output.contains("TELYND:"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        let overflow = ProcessRunner.run("/bin/sh", arguments: ["-c", "yes TELYND:ssh=ready"], outputLimit: 1000)
        XCTAssertEqual(overflow.code, -3)
        XCTAssertFalse(overflow.output.contains("TELYND:"))
        let normal = ProcessRunner.run("/bin/echo", arguments: ["ok"])
        XCTAssertEqual(normal.code, 0); XCTAssertEqual(normal.output, "ok\n")
    }

    func testIncompleteAndFailedTransportCannotEstablishReadiness() {
        let incomplete = ReadinessReport(output: "TELYND:ssh=ready\nTELYND:installation=verified")
        XCTAssertFalse(incomplete.accepts(exitCode: 0, recoveryRequested: false))
        let full = ReadinessReport(output: "TELYND:ssh=ready\nTELYND:check=complete")
        XCTAssertTrue(full.accepts(exitCode: 0, recoveryRequested: false))
        for code: Int32 in [-3, -2, -1, 255] { XCTAssertFalse(full.accepts(exitCode: code, recoveryRequested: true)) }
        XCTAssertFalse(full.accepts(exitCode: 3, recoveryRequested: false))
        XCTAssertTrue(full.accepts(exitCode: 3, recoveryRequested: true))
    }

    func testMissingChromeAndChangedProfileDoNotProduceLaunchArguments() throws {
        let profiles = try ChromeProfiles.parse(metadata)
        var prefs = Preferences(); prefs.chromeProfileEmail = "reader@example.test"; prefs.chromeProfileDirectory = "Profile 1"
        XCTAssertThrowsError(try ChromeLaunch.arguments(url: InputValidation.devicePicker, profiles: profiles, preferences: prefs, applicationAvailable: false)) { error in
            XCTAssertEqual(error as? ConfigurationError, .chromeMissing)
        }
        XCTAssertEqual(try ChromeLaunch.arguments(url: InputValidation.devicePicker, profiles: profiles, preferences: prefs, applicationAvailable: true), ["--profile-directory=Profile 1", InputValidation.devicePicker])
        prefs.chromeProfileEmail = "someone-else@example.test"
        XCTAssertThrowsError(try ChromeLaunch.arguments(url: InputValidation.devicePicker, profiles: profiles, preferences: prefs, applicationAvailable: true))
        XCTAssertThrowsError(try ChromeLaunch.arguments(url: InputValidation.devicePicker, profiles: [], preferences: prefs, applicationAvailable: true))
    }

    func testReadinessSSHPolicyOverridesUnsafeUserDefaults() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("config")
        try "Host *\n StrictHostKeyChecking no\n ForwardAgent yes\n ForwardX11 yes\n ControlMaster auto\n ControlPath /tmp/unsafe-mux\n ControlPersist yes\n PermitLocalCommand yes\n".write(to: config, atomically: true, encoding: .utf8)
        let result = ProcessRunner.run("/usr/bin/ssh", arguments: ["-G", "-F", config.path] + SSHPolicy.readinessArguments(identity: "/tmp/synthetic_key", target: "reader@fixture.example", command: "true"))
        XCTAssertEqual(result.code, 0)
        let fields = Dictionary(result.output.split(separator: "\n").compactMap { line -> (String, String)? in
            let pair = line.split(separator: " ", maxSplits: 1)
            return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
        }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(fields["stricthostkeychecking"], "true")
        XCTAssertEqual(fields["forwardagent"], "no")
        XCTAssertEqual(fields["forwardx11"], "no")
        XCTAssertEqual(fields["controlmaster"], "false")
        XCTAssertTrue(fields["controlpath"] == nil || fields["controlpath"] == "none")
        XCTAssertEqual(fields["clearallforwardings"], "yes")
        XCTAssertEqual(fields["permitlocalcommand"], "no")
    }

}
