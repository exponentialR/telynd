import XCTest
@testable import TelyndCore

final class SSHAddressTests: XCTestCase {
    func testFriendlyAddressFieldsPreserveExistingTargetsAndTrimInput() {
        var address = SSHAddress(target: "reader@100.64.0.1")
        XCTAssertEqual(address.username, "reader"); XCTAssertEqual(address.host, "100.64.0.1")
        XCTAssertEqual(address.target, "reader@100.64.0.1")
        address.username = " reader "; address.host = " workstation.example "
        XCTAssertEqual(address.target, "reader@workstation.example")
        XCTAssertNil(SSHAddress().target)
    }
    func testUnsupportedAndShellInputCannotBecomeATarget() {
        for value in ["reader@host:2222", "reader@::1", "reader@host/path", "reader@host;touch", "reader@host\ncommand", "reader@@host", "reader@$(hostname)", "@host", "reader@", "reader host"] {
            XCTAssertNil(SSHAddress(target: value).target, value)
        }
    }
    func testPastedLoginCommandsAreParsedAsDataWithoutOptionsOrShellSyntax() {
        for value in ["reader@host.example", "ssh reader@host.example", "  ssh reader@host.example\n"] {
            XCTAssertEqual(SSHAddress.pasted(value)?.target, "reader@host.example")
        }
        for value in ["ssh -p 2222 reader@host", "ssh reader@host; command", "ssh $(whoami)@host", "ssh reader@host\ncommand", "https://host", "", String(repeating: "x", count: 1025)] {
            XCTAssertNil(SSHAddress.pasted(value), value)
        }
        XCTAssertNil(SSHAddress.pasted(nil))
    }
}
