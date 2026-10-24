import XCTest
@testable import TelyndCore

final class ChromeSetupCaptureTests: XCTestCase {
    let markerPage = URL(fileURLWithPath: "/synthetic/chrome-setup.html")
    let now = Date(timeIntervalSince1970: 100)
    let tab = ChromeSetupTab(windowID: "12", tabID: "34")
    let link = "https://remotedesktop.google.com/access/session/11111111-1111-4111-8111-111111111111"

    func testOnlyOpenedMarkerBindsAndOnlyBoundTabCanProvideCandidate() {
        let desktop = Desktop(name: "Home")
        var flow = ChromeSetupCapture(desktop: desktop, markerPage: markerPage, now: now)
        let bind = flow.request
        // An already-open remote session must never be mistaken for this setup.
        XCTAssertFalse(flow.receive(.init(tab: tab, address: link), for: bind, current: desktop, now: now))
        XCTAssertNil(flow.candidate)
        XCTAssertTrue(flow.receive(.init(tab: tab, address: flow.bootstrapURL), for: bind, current: desktop, now: now))
        XCTAssertEqual(flow.request, .tab(tab))
        XCTAssertFalse(flow.receive(.init(tab: .init(windowID: "12", tabID: "99"), address: link), for: flow.request, current: desktop, now: now))
        XCTAssertFalse(flow.receive(.init(tab: tab, address: link), for: bind, current: desktop, now: now))
        XCTAssertTrue(flow.receive(.init(tab: tab, address: link), for: flow.request, current: desktop, now: now))
        XCTAssertEqual(flow.confirmedLink(current: desktop, now: now), link)
        XCTAssertEqual(desktop.chromeURL, InputValidation.devicePicker) // No automatic draft mutation.
    }

    func testPickerSignInAndUntrustedAddressesRemainWaiting() {
        let desktop = Desktop(name: "Home")
        var flow = bound(desktop)
        for address in [InputValidation.devicePicker, "https://accounts.google.com/", "https://example.test/access/session/11111111-1111-4111-8111-111111111111", link + "?token=secret", link + "#fragment", "javascript:alert(1)"] {
            XCTAssertFalse(flow.receive(.init(tab: tab, address: address), for: flow.request, current: desktop, now: now))
            XCTAssertNil(flow.confirmedLink(current: desktop, now: now))
        }
        XCTAssertTrue(flow.receive(.init(tab: tab, address: link), for: flow.request, current: desktop, now: now))
    }

    func testDraftChangesRejectBothDetectionAndConfirmation() {
        let desktop = Desktop(name: "Home")
        var renamed = desktop; renamed.name = "Work"
        var accountChanged = desktop; accountChanged.chromeProfile = .init(directory: "Profile 2", email: "other@example.test")
        var manual = desktop; manual.chromeURL = link
        for changed in [renamed, accountChanged, manual, Desktop(name: "Other")] {
            var flow = bound(desktop)
            XCTAssertFalse(flow.receive(.init(tab: tab, address: link), for: flow.request, current: changed, now: now))
            XCTAssertTrue(flow.receive(.init(tab: tab, address: link), for: flow.request, current: desktop, now: now))
            XCTAssertNil(flow.confirmedLink(current: changed, now: now))
        }
    }

    func testExpiredAndReplacedAttemptsRejectLateResults() {
        let desktop = Desktop(name: "Home")
        var flow = bound(desktop)
        let expired = now.addingTimeInterval(300)
        XCTAssertFalse(flow.isCurrent(desktop, now: expired))
        XCTAssertFalse(flow.receive(.init(tab: tab, address: link), for: flow.request, current: desktop, now: expired))
        XCTAssertTrue(flow.receive(.init(tab: tab, address: link), for: flow.request, current: desktop, now: now))
        XCTAssertEqual(flow.confirmedLink(current: desktop, now: expired), link) // Reviewing a detected link needs no polling deadline.
        var replacement = ChromeSetupCapture(desktop: desktop, markerPage: markerPage, now: now)
        let old = ChromeSetupCapture(desktop: desktop, markerPage: markerPage, now: now)
        XCTAssertNotEqual(old.id, replacement.id)
        XCTAssertFalse(replacement.receive(.init(tab: tab, address: old.bootstrapURL), for: old.request, current: desktop, now: now))
    }

    func testInvalidTabIdentifiersCannotBindAndGuidanceIsNotFailure() {
        let desktop = Desktop(name: "Home")
        for identifier in ["", "-1", "1 or 2", "\"; do shell script", String(repeating: "1", count: 21)] {
            var flow = ChromeSetupCapture(desktop: desktop, markerPage: markerPage, now: now)
            XCTAssertFalse(flow.receive(.init(tab: .init(windowID: identifier, tabID: "1"), address: flow.bootstrapURL), for: flow.request, current: desktop, now: now))
        }
        XCTAssertTrue(ChromeCaptureError.notConnection.isGuidance)
        XCTAssertTrue(ChromeCaptureError.setupTabClosed.isGuidance)
        XCTAssertFalse(ChromeCaptureError.permissionDenied.isGuidance)
        XCTAssertFalse(ChromeCaptureError.unavailable.isGuidance)
    }

    private func bound(_ desktop: Desktop) -> ChromeSetupCapture {
        var flow = ChromeSetupCapture(desktop: desktop, markerPage: markerPage, now: now)
        XCTAssertTrue(flow.receive(.init(tab: tab, address: flow.bootstrapURL), for: flow.request, current: desktop, now: now))
        return flow
    }
}
