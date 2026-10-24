import XCTest
@testable import TelyndCore

final class HostChecksTests: XCTestCase {
    func testOldCompletionDoesNotClearNewerBusyStateAfterEdit() throws {
        var checks = HostChecks()
        let desktop = UUID()
        let old = try XCTUnwrap(checks.begin(desktop, recovering: false))
        checks.invalidate(desktop) // Saved target/key edit.
        let current = try XCTUnwrap(checks.begin(desktop, recovering: true))
        checks.complete(desktop, request: old, observation: nil)
        XCTAssertEqual(checks.observations[desktop]?.busy, true)
        XCTAssertNil(checks.begin(desktop, recovering: false))
        checks.complete(desktop, request: current, observation: HostObservation(ssh: .ready, note: "current"))
        XCTAssertEqual(checks.observations[desktop]?.busy, false)
        XCTAssertEqual(checks.observations[desktop]?.note, "current")
    }

    func testOldCompletionDoesNotEraseAlreadyCompletedNewerResult() throws {
        var checks = HostChecks()
        let desktop = UUID()
        let old = try XCTUnwrap(checks.begin(desktop, recovering: false))
        checks.invalidate(desktop)
        let current = try XCTUnwrap(checks.begin(desktop, recovering: false))
        checks.complete(desktop, request: current, observation: HostObservation(ssh: .ready, note: "new result"))
        checks.complete(desktop, request: old, observation: nil)
        XCTAssertEqual(checks.observations[desktop]?.ssh, .ready)
        XCTAssertEqual(checks.observations[desktop]?.note, "new result")
    }

    func testReturningToOriginalTargetDoesNotAcceptItsSupersededResult() throws {
        var checks = HostChecks()
        let desktop = UUID()
        let originalA = try XCTUnwrap(checks.begin(desktop, recovering: false))
        checks.invalidate(desktop) // A -> B.
        let intermediateB = try XCTUnwrap(checks.begin(desktop, recovering: false))
        checks.invalidate(desktop) // B -> A: same target/key, different request.
        let latestA = try XCTUnwrap(checks.begin(desktop, recovering: false))
        checks.complete(desktop, request: originalA, observation: HostObservation(ssh: .ready, note: "old A"))
        checks.complete(desktop, request: intermediateB, observation: nil)
        XCTAssertEqual(checks.observations[desktop]?.busy, true)
        XCTAssertNil(checks.observations[desktop]?.ssh)
        checks.complete(desktop, request: latestA, observation: HostObservation(ssh: .failed, note: "latest A"))
        XCTAssertEqual(checks.observations[desktop]?.ssh, .failed)
        XCTAssertEqual(checks.observations[desktop]?.note, "latest A")
    }

    func testDiscardingCurrentRequestAllowsRetryWithoutAffectingAnotherDesktop() throws {
        var checks = HostChecks()
        let first = UUID(), second = UUID()
        let firstRequest = try XCTUnwrap(checks.begin(first, recovering: false))
        let secondRequest = try XCTUnwrap(checks.begin(second, recovering: false))
        checks.complete(first, request: firstRequest, observation: nil)
        XCTAssertNil(checks.observations[first])
        XCTAssertNotNil(checks.begin(first, recovering: false))
        XCTAssertEqual(checks.observations[second]?.busy, true)
        checks.complete(second, request: secondRequest, observation: HostObservation(ssh: .ready))
        XCTAssertEqual(checks.observations[second]?.ssh, .ready)
    }
}
