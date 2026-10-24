import XCTest
import Darwin
@testable import TelyndCore

final class PlatformTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func fixture(_ desktop: Desktop, _ updates: [String: Any] = [:]) throws -> Data {
        var data: [String: Any] = ["schemaVersion": 1, "desktopID": desktop.id.uuidString, "platform": desktop.hostPlatform.rawValue,
                                  "osVersion": "26.4", "architecture": "arm64", "checkedAt": now.timeIntervalSince1970,
                                  "service": "running", "enablement": "enabled", "installation": "verified", "recovery": "stopped-service", "permissions": "unknown", "outcome": "checked"]
        data.merge(updates) { _, value in value }
        return try JSONSerialization.data(withJSONObject: data)
    }
    func testOldSSHAndConnectionOnlyDesktopsStayUnknownWithoutLosingDetails() throws {
        for target in ["", "reader@fixture.example"] {
            let id = UUID()
            let json = "{\"id\":\"\(id)\",\"name\":\"Fixture\",\"target\":\"\(target)\",\"identityPath\":\"/tmp/fixture key\",\"lastLaunch\":123.0}"
            let item = try JSONDecoder().decode(Desktop.self, from: Data(json.utf8))
            XCTAssertEqual(item.id, id); XCTAssertEqual(item.hostPlatform, .unknown)
            XCTAssertEqual(item.target, target.isEmpty ? nil : target); XCTAssertEqual(item.identityPath, "/tmp/fixture key")
            XCTAssertNotNil(item.lastLaunch)
            XCTAssertEqual(item, try JSONDecoder().decode(Desktop.self, from: JSONEncoder().encode(item)))
        }
    }
    func testAllPlatformSelectionsAllowConnectionOnlyAndSurviveDraftResume() throws {
        for platform in HostPlatform.allCases {
            let item = Desktop(name: "Fixture", hostPlatform: platform)
            XCTAssertTrue(item.valid); XCTAssertNil(item.target)
            var prefs = Preferences(); prefs.guideDraft = item
            let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(prefs))
            XCTAssertEqual(decoded.guideDraft?.hostPlatform, platform)
            XCTAssertEqual(platform.usesSSHRecovery, platform == .unknown || platform == .linux)
        }
    }
    func testImportedEvidenceIsBoundToComputerAndPlatform() throws {
        let mac = Desktop(name: "Mac fixture", hostPlatform: .macos)
        let data = try fixture(mac)
        XCTAssertNoThrow(try LocalHostReport.parse(data, desktop: mac, now: now))
        XCTAssertThrowsError(try LocalHostReport.parse(data, desktop: Desktop(name: "Other", hostPlatform: .macos), now: now))
        var changed = mac; changed.hostPlatform = .windows
        XCTAssertThrowsError(try LocalHostReport.parse(data, desktop: changed, now: now))
    }
    func testUnknownOrMalformedStatusNeverEstablishesImportedReadiness() throws {
        let item = Desktop(name: "Fixture", hostPlatform: .windows)
        for update: [String: Any] in [["schemaVersion": 2], ["platform": "linux"], ["service": "<script>"], ["installation": "yes"], ["permissions": "granted"], ["outcome": "success"], ["osVersion": "bad\nvalue"], ["architecture": String(repeating: "x", count: 129)], ["checkedAt": 0]] {
            XCTAssertThrowsError(try LocalHostReport.parse(fixture(item, update), desktop: item, now: now), "\(update)")
        }
        XCTAssertThrowsError(try LocalHostReport.parse(Data(repeating: 32, count: 16385), desktop: item))
        XCTAssertThrowsError(try LocalHostReport.parse(Data("{}".utf8), desktop: item))
    }
    func testFutureReportsAreRejectedAndOldReportsRemainStale() throws {
        let item = Desktop(name: "Fixture", hostPlatform: .macos)
        XCTAssertThrowsError(try LocalHostReport.parse(fixture(item, ["checkedAt": now.timeIntervalSince1970+61]), desktop: item, now: now))
        let report = try LocalHostReport.parse(fixture(item, ["checkedAt": now.timeIntervalSince1970-301]), desktop: item, now: now).readiness
        XCTAssertTrue(report.isStale(at: now)); XCTAssertEqual(report.configurationLabel(at: now), "Verification is stale")
    }
    func testWindowsCrashScopeAndDisabledDriftStatesRemainDistinct() throws {
        let item = Desktop(name: "Fixture", hostPlatform: .windows)
        let report = try LocalHostReport.parse(fixture(item, ["recovery": "crash-only"]), desktop: item, now: now).readiness
        XCTAssertTrue(report.recoveryEnabled); XCTAssertTrue(report.imported)
        XCTAssertNil(report.values["ssh"]); XCTAssertNil(report.values["timer"])
        XCTAssertEqual(report.configurationLabel(at: now), "Crash recovery configured · imported")
        for (update, label) in [(["enablement": "disabled"], "Chrome host intentionally disabled"), (["installation": "drift"], "Recovery setup needs attention"), (["installation": "partial"], "Recovery setup needs attention"), (["installation": "disabled"], "Recovery disabled · imported"), (["installation": "missing"], "Recovery not configured · imported"), (["service": "missing"], "Chrome host service not found"), (["permissions": "needs-attention"], "Host permissions need attention")] {
            let other = try LocalHostReport.parse(fixture(item, update), desktop: item, now: now).readiness
            XCTAssertEqual(other.configurationLabel(at: now), label)
            if update["installation"] == "partial" || update["enablement"] == "disabled" { XCTAssertFalse(other.recoveryEnabled) }
        }
    }
    func testKitsArePlatformSpecificAndNeverRequestSecurityBypasses() {
        XCTAssertTrue(RecoveryKit.files(for: .unknown).isEmpty)
        XCTAssertTrue(RecoveryKit.files(for: .linux).isEmpty)
        XCTAssertEqual(RecoveryKit.files(for: .macos), ["macos-recovery.sh"])
        XCTAssertEqual(RecoveryKit.files(for: .windows), ["windows-recovery.ps1", "WindowsServicePolicy.cs"])
        for platform in [HostPlatform.macos, .windows] {
            let desktop = Desktop(name: "Not included in public kit", hostPlatform: platform)
            let instructions = RecoveryKit.instructions(for: desktop)
            XCTAssertTrue(instructions.contains(desktop.id.uuidString))
            XCTAssertFalse(instructions.contains(desktop.name)); XCTAssertFalse(instructions.contains("ExecutionPolicy Bypass"))
            XCTAssertTrue(instructions.contains("not authenticated"))
        }
    }
    func testPowerShellUTF16AndUTF8BOMReportsAreAcceptedWithinBounds() throws {
        let desktop = Desktop(name: "Fixture", hostPlatform: .windows)
        let json = try fixture(desktop)
        let text = try XCTUnwrap(String(data: json, encoding: .utf8))
        let expected = try LocalHostReport.parse(json, desktop: desktop, now: now)
        for (bom, encoding) in [(Data([0xff, 0xfe]), String.Encoding.utf16LittleEndian), (Data([0xfe, 0xff]), .utf16BigEndian), (Data([0xef, 0xbb, 0xbf]), .utf8)] {
            let encoded = try XCTUnwrap(text.data(using: encoding))
            XCTAssertEqual(try LocalHostReport.parse(bom + encoded, desktop: desktop, now: now), expected)
        }
        XCTAssertThrowsError(try LocalHostReport.parse(Data(repeating: 0, count: 32769), desktop: desktop, now: now))
        XCTAssertThrowsError(try LocalHostReport.parse(Data([0xff, 0xfe, 0x7b]), desktop: desktop, now: now))
    }
    func testReportFileReaderRejectsSpecialFilesAndLinksWithoutBlocking() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("report.json")
        try Data("{}".utf8).write(to: file)
        XCTAssertEqual(try LocalHostReport.read(from: file), Data("{}".utf8))
        let link = dir.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertThrowsError(try LocalHostReport.read(from: link))
        let pipe = dir.appendingPathComponent("pipe.json")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        let start = Date()
        XCTAssertThrowsError(try LocalHostReport.read(from: pipe))
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
        XCTAssertThrowsError(try LocalHostReport.read(from: dir))
    }
    func testReportFileReaderEnforcesBoundBeforeLoading() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(repeating: 0, count: 32769).write(to: file)
        XCTAssertThrowsError(try LocalHostReport.read(from: file))
    }
}
