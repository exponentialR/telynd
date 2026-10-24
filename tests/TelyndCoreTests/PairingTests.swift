import XCTest
@testable import TelyndCore

final class PairingTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1000)
    var key: PairingKey {
        var data = Data([0, 0, 0, 11]); data.append(Data("ssh-ed25519".utf8)); data.append(Data([0, 0, 0, 32])); data.append(Data(repeating: 7, count: 32))
        return PairingKey(type: "ssh-ed25519", key: data.base64EncodedString())
    }
    func card(addresses: [String] = ["100.75.0.12", "192.0.2.4"]) -> PairingCard {
        PairingCard(createdAt: now.timeIntervalSince1970, username: "demo", hostname: "Work-PC", addresses: addresses, hostKeys: [key])
    }
    func encoded(_ value: PairingCard) throws -> String { "TELYND1:" + (try JSONEncoder().encode(value)).base64EncodedString() }

    func testFreshPublicCardRoundTripsAndHostKeyFingerprintIsDeterministic() throws {
        let value = card()
        XCTAssertTrue(key.valid)
        XCTAssertEqual(try PairingCard.parse(encoded(value), now: now), value)
        XCTAssertTrue(key.fingerprint.hasPrefix("SHA256:"))
        XCTAssertEqual(key.fingerprint.count, 50)
        XCTAssertThrowsError(try PairingCard.parse(encoded(value), now: now.addingTimeInterval(900)))
        XCTAssertThrowsError(try PairingCard.parse(encoded(value), now: now.addingTimeInterval(-61)))
    }

    func testMalformedSecretBearingAndUnsupportedCardsFailBeforeNetworkUse() throws {
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(card())) as? [String: Any])
        value["password"] = "never-import-secrets"
        let secret = "TELYND1:" + (try JSONSerialization.data(withJSONObject: value)).base64EncodedString()
        XCTAssertThrowsError(try PairingCard.parse(secret, now: now))
        for input in ["bad", "TELYND1:!!!", String(repeating: "a", count: 16385)] { XCTAssertThrowsError(try PairingCard.parse(input, now: now)) }
        for username in ["root", "demo@other", "demo;id", "demo\n"] {
            let invalid = PairingCard(createdAt: 1000, username: username, hostname: "PC", addresses: ["192.0.2.4"], hostKeys: [key])
            XCTAssertThrowsError(try invalid.validate(now: now))
        }
        let wrongOS = PairingCard(platform: "windows", createdAt: 1000, username: "demo", hostname: "PC", addresses: ["192.0.2.4"], hostKeys: [key])
        XCTAssertThrowsError(try wrongOS.validate(now: now))
    }

    func testAddressScopeAndProbeCountAreBounded() {
        for value in ["localhost", "127.0.0.1", "169.254.1.2", "224.0.0.1", "255.255.255.255", "0.0.0.0", "10.0.0.255", "01.2.3.4", "192.0.2.4;id", "::1"] {
            XCTAssertFalse(PairingCard.addressAllowed(value), value)
        }
        XCTAssertThrowsError(try card(addresses: ["192.0.2.4", "192.0.2.4"]).validate(now: now))
        XCTAssertThrowsError(try card(addresses: (1...7).map { "192.0.2.\($0)" }).validate(now: now))
        XCTAssertTrue(PairingCard.addressAllowed("100.75.0.12"))
    }

    func testReachabilityAloneNeverChoosesAnIdentityMismatchAndStopsAtFirstMatch() throws {
        var contacted: [String] = []
        let value = card()
        let found = try PairingProbe.find(value, control: PairingProbeControl(), now: { self.now }) { address in
            contacted.append(address)
            return address == value.addresses[0] ? "\(address) ssh-ed25519 wrong-key" : "\(address) \(self.key.type) \(self.key.key)"
        }
        XCTAssertEqual(found, value.addresses[1])
        XCTAssertEqual(contacted, value.addresses)
        contacted = []
        _ = try PairingProbe.find(value, control: PairingProbeControl(), now: { self.now }) { address in
            contacted.append(address); return "\(address) \(self.key.type) \(self.key.key)"
        }
        XCTAssertEqual(contacted.count, 1)
        XCTAssertThrowsError(try PairingProbe.find(value, control: PairingProbeControl(), now: { self.now }, scan: { _ in "different-host \(self.key.type) \(self.key.key)" }))
    }

    func testCancellationAndExpiryPreventFurtherProbesOrLateSuccess() {
        let control = PairingProbeControl()
        var count = 0
        XCTAssertThrowsError(try PairingProbe.find(card(), control: control, now: { self.now }) { address in
            count += 1; control.cancel(); return "\(address) \(self.key.type) \(self.key.key)"
        })
        XCTAssertEqual(count, 1)
        count = 0
        XCTAssertThrowsError(try PairingProbe.find(card(), control: control, now: { self.now }, scan: { _ in count += 1; return "" }))
        XCTAssertEqual(count, 0)
        var clock = now
        XCTAssertThrowsError(try PairingProbe.find(card(), control: PairingProbeControl(), now: { clock }) { address in
            clock = self.now.addingTimeInterval(900); return "\(address) \(self.key.type) \(self.key.key)"
        })
    }
    func testUntrustedScannerDiagnosticsCannotBecomeKeyProtocolOutput() {
        let result = ProcessRunner.run("/bin/sh", arguments: ["-c", "printf 'forged-key-line\\n' >&2; printf 'public-output\\n'"], mergeError: false)
        XCTAssertEqual(result.code, 0)
        XCTAssertEqual(result.output, "public-output\n")
    }
}
