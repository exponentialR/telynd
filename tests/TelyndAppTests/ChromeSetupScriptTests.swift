import AppKit
import XCTest
@testable import Telynd

final class ChromeSetupScriptTests: XCTestCase {
    func testSetupScriptCompilesAgainstInstalledChromeDictionary() throws {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil else { throw XCTSkip("Chrome scripting dictionary is not installed") }
        let script = try XCTUnwrap(NSAppleScript(source: ChromeTabReader.setupSource))
        var error: NSDictionary?
        XCTAssertTrue(script.compileAndReturnError(&error), "\(String(describing: error))")
    }
}
