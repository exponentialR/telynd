import AppKit
import TelyndCore

enum ChromeTabReader {
    static func read() throws -> String {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").isEmpty else { throw ChromeCaptureError.chromeClosed }
        // Fixed, user-requested Apple event. Read one URL, never enumerate tabs,
        // access page content, or interpolate browser/user data into a script.
        let source = """
        with timeout of 30 seconds
            tell application id "com.google.Chrome"
                if (count of windows) is 0 then return ""
                return URL of active tab of front window
            end tell
        end timeout
        """
        guard let script = NSAppleScript(source: source) else { throw ChromeCaptureError.unavailable }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            if (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue == -1743 { throw ChromeCaptureError.permissionDenied }
            throw ChromeCaptureError.unavailable
        }
        return try ChromeConnectionCapture.validatedLink(result.stringValue)
    }
}
