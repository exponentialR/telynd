import XCTest
@testable import TelyndCore

final class LinuxSetupDownloadTests: XCTestCase {
    func testPinnedPublicDownloadMatchesBundledHelper() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("assets/" + LinuxSetupDownload.filename))
        let url = try XCTUnwrap(LinuxSetupDownload.verifiedURL(for: data))
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "raw.githubusercontent.com")
        XCTAssertEqual(url.path, "/exponentialR/telynd/\(LinuxSetupDownload.revision)/assets/\(LinuxSetupDownload.filename)")
        XCTAssertNotNil(LinuxSetupDownload.revision.range(of: "^[0-9a-f]{40}$", options: .regularExpression))
    }
    func testMismatchedOrAbsentHelperCannotSupplyDownloadLink() {
        XCTAssertNil(LinuxSetupDownload.verifiedURL(for: Data()))
        XCTAssertNil(LinuxSetupDownload.verifiedURL(for: Data("unreviewed replacement".utf8)))
        XCTAssertNil(LinuxSetupDownload.verifiedInstallCommand(for: Data()))
        XCTAssertNil(LinuxSetupDownload.verifiedInstallCommand(for: Data("unreviewed replacement".utf8)))
    }
    func testTerminalInstallDownloadsAndVerifiesBeforeAnyAdministratorAction() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let helper = root.appendingPathComponent("assets/" + LinuxSetupDownload.filename)
        let command = try XCTUnwrap(LinuxSetupDownload.verifiedInstallCommand(for: Data(contentsOf: helper)))
        for outcome in ["valid", "corrupt", "download_failed"] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let bin = directory.appendingPathComponent("bin")
            let work = directory.appendingPathComponent("work")
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let scripts = [
                "mktemp": "printf '%s\\n' \"$TEST_WORK\"",
                "wget": """
                test "$1" = --https-only && test "$2" = -O || exit 9
                test "$4" = '\(LinuxSetupDownload.url.absoluteString)' || exit 9
                case "$TEST_OUTCOME" in
                  valid) cp "$TEST_HELPER" "$3";;
                  corrupt) printf 'corrupt download' > "$3";;
                  *) exit 8;;
                esac
                """,
                // macOS has shasum; Ubuntu's copied command uses sha256sum.
                "sha256sum": "exec /usr/bin/shasum -a 256 \"$@\"",
                "sudo": "printf '%s\\n' \"$*\" > \"$TEST_ADMIN_MARKER\"",
                "telynd-setup": "printf launched > \"$TEST_LAUNCH_MARKER\""
            ]
            for (name, script) in scripts {
                let path = bin.appendingPathComponent(name)
                try ("#!/bin/sh\nset -e\n" + script + "\n").write(to: path, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
            }
            let administrator = directory.appendingPathComponent("administrator")
            let launched = directory.appendingPathComponent("launched")
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
            process.environment = ["PATH": bin.path + ":/usr/bin:/bin", "TEST_WORK": work.path,
                                   "TEST_HELPER": helper.path, "TEST_OUTCOME": outcome,
                                   "TEST_ADMIN_MARKER": administrator.path, "TEST_LAUNCH_MARKER": launched.path]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus == 0, outcome == "valid", outcome)
            XCTAssertEqual(FileManager.default.fileExists(atPath: administrator.path), outcome == "valid", outcome)
            XCTAssertEqual(FileManager.default.fileExists(atPath: launched.path), outcome == "valid", outcome)
            if outcome == "valid" { XCTAssertEqual(try String(contentsOf: administrator), "apt install ./\(LinuxSetupDownload.filename)\n") }
        }
    }
}
