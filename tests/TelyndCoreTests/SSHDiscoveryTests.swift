import XCTest
@testable import TelyndCore

final class SSHDiscoveryTests: XCTestCase {
    func testLabelledOutputProvidesPasteableTargetsAndSeparatesTailscaleFromOtherAddresses() throws {
        let output = try runDiscovery(tailscale: "printf '%s\\n' '100.75.0.12'")
        XCTAssertTrue(output.contains("Linux username (first field): demo"))
        XCTAssertTrue(output.contains("SSH via Tailscale"))
        let commands = output.components(separatedBy: .newlines).filter { $0.hasPrefix("ssh ") }
        XCTAssertEqual(commands, ["ssh demo@100.75.0.12", "ssh demo@192.0.2.4", "ssh demo@10.2.0.1"])
        for command in commands { XCTAssertNotNil(SSHAddress.pasted(command)) }
        XCTAssertNil(SSHAddress.pasted(output)) // Several addresses never become one destination.
        XCTAssertTrue(output.contains("SSH identity fingerprints"))
        XCTAssertFalse(commands.contains(where: { $0.contains("fd7a:") })) // IPv6 is not supported by this form.
    }

    func testUnavailableTailscaleLeavesOtherNetworkCandidatesWithoutInventingAVPNAddress() throws {
        let output = try runDiscovery(tailscale: "exit 1")
        XCTAssertFalse(output.contains("SSH via Tailscale"))
        let commands = output.components(separatedBy: .newlines).filter { $0.hasPrefix("ssh ") }
        XCTAssertEqual(commands, ["ssh demo@192.0.2.4", "ssh demo@100.75.0.12", "ssh demo@10.2.0.1"])
        XCTAssertTrue(output.contains("choose a network reachable from your Mac"))
    }

    private func runDiscovery(tailscale: String) throws -> String {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let commands = [
            "whoami": "printf '%s\\n' 'demo'",
            "hostname": "printf '%s\\n' '192.0.2.4 100.75.0.12 10.2.0.1 fd7a::1'",
            "tailscale": tailscale,
            "ssh-keygen": "printf '%s\\n' 'synthetic public fingerprint'"
        ]
        for (name, body) in commands {
            let file = folder.appendingPathComponent(name)
            try ("#!/bin/sh\n" + body + "\n").write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.environment = ["PATH": folder.path + ":/usr/bin:/bin"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(Data(SSHDiscovery.command.utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}
