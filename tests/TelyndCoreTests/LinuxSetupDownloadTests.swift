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
    }
}
