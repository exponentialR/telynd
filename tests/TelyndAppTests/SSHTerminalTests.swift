import AppKit
import XCTest
import SwiftTerm
import TelyndCore
@testable import Telynd

final class SSHTerminalTests: XCTestCase {
    func testStartSSHRejectsStaleRemovedLockedAndPreviewHostsWithoutChrome() async {
        await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = AppStore(configuration: ConfigurationStore(directory: directory))
            var desktop = Desktop(name: "Test computer", target: "reader@host.example", identityPath: "/tmp/test_key")
            XCTAssertTrue(store.save(desktop))
            // A missing Chrome profile and unknown OS must not gate SSH.
            store.startSSH(desktop)
            XCTAssertEqual(store.error, "Preview data cannot contact SSH hosts.")
            store.error = nil
            let old = desktop
            desktop.target = "reader@other.example"
            XCTAssertTrue(store.save(desktop))
            store.startSSH(old)
            XCTAssertTrue(store.error?.contains("settings changed") == true)
            store.writeLocked = true
            store.startSSH(desktop)
            XCTAssertEqual(store.error, ConfigurationError.writeLocked.localizedDescription)
            store.writeLocked = false
            XCTAssertTrue(store.remove(desktop.id))
            store.startSSH(desktop)
            XCTAssertEqual(store.error, "Restore this computer before starting SSH.")
            let unconfigured = Desktop(name: "No SSH yet")
            XCTAssertTrue(store.save(unconfigured))
            store.startSSH(unconfigured)
            XCTAssertEqual(store.sshSettingsDesktop, unconfigured)
        }
    }

    func testPTYAcceptsInputRendersANSIResizesAndReportsExitStatus() async throws {
        let ended = expectation(description: "Local PTY exits")
        let session = await MainActor.run {
            _ = NSApplication.shared
            let session = SSHSession(desktop: Desktop(name: "PTY fixture", target: "reader@fixture.example"), identity: "/tmp/fixture key") { view, arguments in
                XCTAssertEqual(Array(arguments.suffix(3)), ["-i", "/tmp/fixture key", "reader@fixture.example"])
                // No SSH host is contacted. Exercise a real PTY using a local shell.
                view.startProcess(executable: "/bin/sh", args: ["-c", "stty -echo; IFS= read -r line; printf '\\033[31mPTY:%s\\033[0m\\r\\n' \"$line\"; stty size; exit 7"])
            }
            session.onEnded = { ended.fulfill() }
            session.start()
            XCTAssertTrue(session.isRunning)
            session.terminalView.terminal.resize(cols: 100, rows: 30)
            session.sizeChanged(source: session.terminalView as TerminalView, newCols: 100, newRows: 30)
            session.send(source: session.terminalView, data: Array("hello terminal\n".utf8)[...])
            return session
        }
        await fulfillment(of: [ended], timeout: 10)
        // Final PTY reads can be delivered after the process exit notification.
        for _ in 0..<50 {
            if await MainActor.run(body: { String(decoding: session.terminalView.terminal.getBufferAsData(), as: UTF8.self).contains("30 100") }) { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        await MainActor.run {
            XCTAssertFalse(session.isRunning)
            XCTAssertTrue(session.status.contains("exit 7"), session.status)
            let output = String(decoding: session.terminalView.terminal.getBufferAsData(), as: UTF8.self)
            XCTAssertTrue(output.contains("PTY:hello terminal"), output)
            XCTAssertTrue(output.contains("30 100"), output)
            XCTAssertNil(session.clipboardRead(source: session.terminalView))
        }
    }

    func testDisconnectReapsChildAndAllowsReconnect() async throws {
        let ended = expectation(description: "Both local PTYs exit")
        ended.expectedFulfillmentCount = 2
        let session = await MainActor.run {
            _ = NSApplication.shared
            let session = SSHSession(desktop: Desktop(name: "Disconnect fixture", target: "reader@fixture.example"), identity: "/tmp/fixture") { view, _ in
                view.startProcess(executable: "/bin/cat")
            }
            session.onEnded = { ended.fulfill() }
            session.start()
            XCTAssertTrue(session.isRunning)
            session.disconnect()
            return session
        }
        for _ in 0..<100 {
            if await MainActor.run(body: { !session.isRunning }) { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        await MainActor.run {
            XCTAssertFalse(session.isRunning)
            XCTAssertEqual(session.status, "Disconnected")
            var result: Int32 = 0
            XCTAssertEqual(waitpid(session.terminalView.process.shellPid, &result, WNOHANG), -1)
            XCTAssertEqual(errno, ECHILD)
            session.start()
            XCTAssertTrue(session.isRunning)
            session.disconnect()
        }
        await fulfillment(of: [ended], timeout: 10)
        await MainActor.run { XCTAssertEqual(session.status, "Disconnected") }
    }

    func testClosingTerminalWindowDisconnectsAndReapsItsChild() async throws {
        let controller = await MainActor.run {
            _ = NSApplication.shared
            let session = SSHSession(desktop: Desktop(name: "Window fixture", target: "reader@fixture.example"), identity: "/tmp/fixture") { view, _ in
                view.startProcess(executable: "/bin/cat")
            }
            let controller = SSHTerminalWindow(session: session)
            session.start()
            XCTAssertTrue(session.isRunning)
            var closed = false
            controller.onClosed = { closed = true }
            controller.close()
            XCTAssertTrue(closed)
            return controller
        }
        for _ in 0..<150 {
            if await MainActor.run(body: { !controller.session.isRunning }) { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        await MainActor.run {
            XCTAssertEqual(controller.session.status, "Disconnected")
            var result: Int32 = 0
            XCTAssertEqual(waitpid(controller.session.terminalView.process.shellPid, &result, WNOHANG), -1)
            XCTAssertEqual(errno, ECHILD)
        }
    }
}
