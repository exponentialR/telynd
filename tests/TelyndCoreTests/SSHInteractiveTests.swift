import XCTest
import TelyndCore

final class SSHInteractiveTests: XCTestCase {
    func testInteractiveLoginKeepsPromptsAndTrustChecksWhileDisablingForwardingAndReuse() {
        let identity = "/tmp/key with spaces/\"$(touch never)"
        let arguments = SSHPolicy.interactiveArguments(identity: identity, target: "reader@host.example")
        XCTAssertEqual(arguments.first, "-tt")
        XCTAssertEqual(Array(arguments.suffix(3)), ["-i", identity, "reader@host.example"])
        for option in ["BatchMode=no", "StrictHostKeyChecking=ask", "ForwardAgent=no", "ForwardX11=no", "ForwardX11Trusted=no", "ClearAllForwardings=yes", "PermitLocalCommand=no", "ControlMaster=no", "ControlPath=none", "ControlPersist=no", "ForkAfterAuthentication=no", "IdentitiesOnly=yes", "ConnectTimeout=10"] {
            XCTAssertTrue(arguments.contains(option), option)
        }
        XCTAssertFalse(arguments.contains("StrictHostKeyChecking=no"))
        XCTAssertFalse(arguments.contains("-T"))
    }
}
