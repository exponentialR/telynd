import AppKit
import Carbon
import TelyndCore

enum ChromeTabReader {
    // Arguments travel as Apple event descriptors, never executable script text.
    // The local marker binds the window launched in the selected Chrome profile
    // before navigating that single tab to Google's picker.
    static let setupSource = """
    on inspectsetup(marker, trackedWindowID, trackedTabID)
        with timeout of 30 seconds
            tell application id "com.google.Chrome"
                if marker is not "" then
                    if (count of windows) is 0 then return {}
                    set setupWindow to front window
                    set setupTab to active tab of setupWindow
                    if URL of setupTab is not marker then return {}
                    set boundWindowID to (id of setupWindow) as text
                    set boundTabID to (id of setupTab) as text
                    set URL of setupTab to "https://remotedesktop.google.com/access"
                    return {boundWindowID, boundTabID, marker}
                end if
                if not (exists window id (trackedWindowID as integer)) then return {"closed"}
                set setupWindow to window id (trackedWindowID as integer)
                if not (exists tab id (trackedTabID as integer) of setupWindow) then return {"closed"}
                set setupTab to tab id (trackedTabID as integer) of setupWindow
                return {trackedWindowID, trackedTabID, URL of setupTab}
            end tell
        end timeout
    end inspectsetup
    """

    static func inspectSetup(_ request: ChromeSetupRead) throws -> ChromeSetupSnapshot? {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").isEmpty else { throw ChromeCaptureError.chromeClosed }
        let arguments: [String]
        switch request {
        case .bind(let marker):
            guard var components = URLComponents(string: marker), let fragment = components.fragment,
                  fragment.hasPrefix("telynd-"), UUID(uuidString: String(fragment.dropFirst(7))) != nil,
                  let markerPage = Bundle.main.url(forResource: "chrome-setup", withExtension: "html") else { throw ChromeCaptureError.unavailable }
            components.fragment = nil
            guard components.url == markerPage else { throw ChromeCaptureError.unavailable }
            arguments = [marker, "", ""]
        case .tab(let tab):
            guard tab.valid else { throw ChromeCaptureError.unavailable }
            arguments = ["", tab.windowID, tab.tabID]
        }
        guard let script = NSAppleScript(source: setupSource) else { throw ChromeCaptureError.unavailable }
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite), eventID: AEEventID(kASSubroutineEvent), targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: "inspectsetup"), forKeyword: AEKeyword(keyASSubroutineName))
        let parameters = NSAppleEventDescriptor.list()
        for (index, argument) in arguments.enumerated() { parameters.insert(NSAppleEventDescriptor(string: argument), at: index + 1) }
        event.setParam(parameters, forKeyword: AEKeyword(keyDirectObject))
        var error: NSDictionary?
        let result = script.executeAppleEvent(event, error: &error)
        if let error {
            if (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue == -1743 { throw ChromeCaptureError.permissionDenied }
            throw ChromeCaptureError.unavailable
        }
        if result.numberOfItems == 0 { return nil }
        if result.numberOfItems == 1, result.atIndex(1)?.stringValue == "closed" { throw ChromeCaptureError.setupTabClosed }
        guard result.numberOfItems == 3, let window = result.atIndex(1)?.stringValue,
              let tab = result.atIndex(2)?.stringValue, let address = result.atIndex(3)?.stringValue else { throw ChromeCaptureError.unavailable }
        return ChromeSetupSnapshot(tab: ChromeSetupTab(windowID: window, tabID: tab), address: address)
    }

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
