import XCTest
@testable import TelyndCore

final class CaptureRequestsTests: XCTestCase {
    func testManualFallbackWinsOverALateCaptureEvenAfterReturningToOriginalLink() {
        let original = Desktop(name: "Computer")
        var draft = original
        var requests = ChromeCaptureRequests()
        let pending = requests.begin(for: draft)
        // Manual edits invalidate immediately, even if SwiftUI coalesces changes.
        requests.invalidate()
        draft.chromeURL = "https://remotedesktop.google.com/access/session/22222222-2222-4222-8222-222222222222"
        XCTAssertFalse(requests.consume(pending, current: draft))
        draft = original
        XCTAssertFalse(requests.consume(pending, current: draft))
    }

    func testChangedComputerOrNameRejectsAResultBeforeTheChangeObserverRuns() {
        let original = Desktop(name: "First computer")
        for changed in [Desktop(name: "Other computer"), renamed(original)] {
            var requests = ChromeCaptureRequests()
            let pending = requests.begin(for: original)
            XCTAssertFalse(requests.consume(pending, current: changed))
        }
    }

    func testCancelledEditorAndSupersededRequestCannotConsumeNewResult() {
        let draft = Desktop(name: "Computer")
        var requests = ChromeCaptureRequests()
        let cancelled = requests.begin(for: draft)
        requests.invalidate() // Editor disappeared.
        let current = requests.begin(for: draft)
        XCTAssertFalse(requests.consume(cancelled, current: draft))
        XCTAssertTrue(requests.consume(current, current: draft))
        XCTAssertFalse(requests.consume(current, current: draft))
    }

    func testUnchangedDraftAcceptsItsOwnSuccessfulOrFailedCompletionOnce() {
        let draft = Desktop(name: "Computer")
        var requests = ChromeCaptureRequests()
        for _ in 0..<2 {
            let current = requests.begin(for: draft)
            XCTAssertTrue(requests.consume(current, current: draft))
            XCTAssertFalse(requests.consume(current, current: draft))
        }
    }

    private func renamed(_ desktop: Desktop) -> Desktop {
        var result = desktop; result.name = "Renamed computer"; return result
    }
}
