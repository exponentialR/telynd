import AppKit
import WebKit

// A disposable feasibility probe, never included in the Telynd app.
final class Probe: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {
    var window: NSWindow!
    var web: WKWebView!
    let status = NSTextField(labelWithString: "Loading Google Remote Desktop with an empty, temporary browser session…")
    var events: [String] = []
    var profiles: [String] { Bundle.main.object(forInfoDictionaryKey: "ProbeProfileDirectories") as? [String] ?? [] }
    @objc func openChromeWindow(_ sender: NSButton) {
        guard profiles.indices.contains(sender.tag), let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else { return }
        let profile = profiles[sender.tag]
        guard profile == "Default" || profile.range(of: "^Profile [0-9]+$", options: .regularExpression) != nil else { return }
        let process = Process()
        process.executableURL = chrome.appendingPathComponent("Contents/MacOS/Google Chrome")
        // Public picker only: do not connect to or interrupt a real host.
        process.arguments = ["--profile-directory=\(profile)", "--app=https://remotedesktop.google.com/access"]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run(); record("separate_chrome_window_requested") }
        catch { record("separate_chrome_window_launch_failed") }
    }
    func record(_ event: String) {
        events.append(event)
        let file = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("probe-events.json")
        if let data = try? JSONEncoder().encode(events) {
            try? data.write(to: file, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self; web.uiDelegate = self
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Telynd Viewer Lab — feasibility test"
        let buttons = profiles.prefix(2).enumerated().map { index, profile in
            let button = NSButton(title: "Test Chrome window (\(profile))", target: self, action: #selector(openChromeWindow(_:)))
            button.tag = index; return button
        }
        let stack = NSStackView(views: [status] + buttons + [web]); stack.orientation = .vertical
        stack.alignment = .leading; stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        window.contentView = stack
        web.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        status.lineBreakMode = .byWordWrapping; status.maximumNumberOfLines = 3
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        record("temporary_store_created_no_chrome_cookies")
        web.load(URLRequest(url: URL(string: "https://remotedesktop.google.com/access")!))
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if url.host == "accounts.google.com" {
            status.stringValue = "Google sign-in is required. This probe stops here: Google OAuth must use an external browser. No credentials or Chrome cookies have been imported."
            record("external_google_authentication_required_stopped_before_sign_in")
            decisionHandler(.cancel)
        } else if url.scheme == "https" && url.host == "remotedesktop.google.com" {
            record("remote_desktop_navigation"); decisionHandler(.allow)
        } else {
            record("other_navigation_blocked"); decisionHandler(.cancel)
        }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        record("new_window_request_not_authenticated"); return nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { record("public_page_loaded_not_a_connected_session") }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { record("navigation_failed_\((error as NSError).code)") }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = Probe()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
