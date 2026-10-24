import AppKit
import SwiftUI
import TelyndCore

@MainActor final class AppStore: ObservableObject {
    @Published var desktops: [Desktop] = []
    @Published var preferences = Preferences()
    @Published var profiles: [ChromeProfile] = []
    @Published var profileProblem: String?
    @Published var error: String?
    @Published var showGuide = false
    @Published private var hostChecks = HostChecks()
    var observations: [UUID: HostObservation] { hostChecks.observations }
    @Published var operationNotes: [UUID: String] = [:]
    @Published var recoveryDesktop: Desktop?
    @Published var writeLocked = false
    let configuration: ConfigurationStore
    let fixtureMode: Bool
    var fixtureAppearance: ColorScheme? {
        guard fixtureMode else { return nil }
        switch Bundle.main.object(forInfoDictionaryKey: "TelyndPreviewAppearance") as? String { case "dark": return .dark; case "light": return .light; default: return nil }
    }
    var resources: URL { Bundle.main.resourceURL! }
    var defaultIdentity: String {
        if fixtureMode { return "/tmp/telynd-preview/id_ed25519" }
        let ssh = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        let existing = ssh.appendingPathComponent("id_ed25519").path
        return FileManager.default.fileExists(atPath: existing) ? existing : ssh.appendingPathComponent("telynd_ed25519").path
    }
    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var directory = home.appendingPathComponent("Library/Application Support/Telynd")
        var fixture = false
        #if DEBUG
        if let path = Bundle.main.object(forInfoDictionaryKey: "TelyndFixtureDirectory") as? String {
            directory = URL(fileURLWithPath: path); fixture = true
        }
        #endif
        fixtureMode = fixture
        configuration = ConfigurationStore(directory: directory)
        do {
            if !fixture { try configuration.migrateLegacy(from: home.appendingPathComponent("Library/Application Support/Remote Desktops")) }
            desktops = try configuration.loadDesktops()
            preferences = try configuration.loadPreferences(existingDesktops: !desktops.isEmpty)
        } catch { self.error = error.localizedDescription; writeLocked = true }
        refreshProfiles()
        refreshOperationNotes()
        showGuide = !preferences.guideCompleted && !writeLocked
    }
    @discardableResult func save(_ desktop: Desktop) -> Bool {
        guard !writeLocked else { error = ConfigurationError.writeLocked.localizedDescription; return false }
        var updated = desktops
        if let i = updated.firstIndex(where: { $0.id == desktop.id }) { updated[i] = desktop } else { updated.append(desktop) }
        do {
            try configuration.saveDesktops(updated)
            if let old = desktops.first(where: { $0.id == desktop.id }), old.target != desktop.target || old.identityPath != desktop.identityPath { hostChecks.invalidate(desktop.id); operationNotes[desktop.id] = nil }
            desktops = updated; return true
        }
        catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func updatePreferences(_ update: (inout Preferences) -> Void) -> Bool {
        guard !writeLocked else { error = ConfigurationError.writeLocked.localizedDescription; return false }
        var next = preferences; update(&next)
        do { try configuration.savePreferences(next); preferences = next; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func refreshProfiles() {
        let url = fixtureMode ? configuration.directory.appendingPathComponent("chrome-state.json") : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/Chrome/Local State")
        do {
            profiles = try ChromeProfiles.parse(Data(contentsOf: url))
            if !fixtureMode {
                let root = url.deletingLastPathComponent()
                profiles = profiles.filter { var directory: ObjCBool = false; return FileManager.default.fileExists(atPath: root.appendingPathComponent($0.directory).path, isDirectory: &directory) && directory.boolValue }
            }
            profileProblem = profiles.contains(where: \.signedIn) ? nil : ConfigurationError.noProfiles.localizedDescription
            if preferences.chromeProfileDirectory == nil, !preferences.chromeProfileEmail.isEmpty,
               let match = try? ChromeProfiles.selected(in: profiles, preferences: preferences), !writeLocked {
                _ = updatePreferences { $0.chromeProfileDirectory = match.directory }
            }
        } catch { profiles = []; profileProblem = ConfigurationError.unreadableProfiles.localizedDescription }
    }
    func chooseProfile(_ directory: String) {
        guard let profile = profiles.first(where: { $0.directory == directory && $0.signedIn }) else { return }
        _ = updatePreferences { $0.chromeProfileDirectory = profile.directory; $0.chromeProfileEmail = profile.email }
    }
    var profileReady: Bool { (try? ChromeProfiles.selected(in: profiles, preferences: preferences)) != nil }
    func connect(_ desktop: Desktop) {
        guard InputValidation.chromeURL(desktop.chromeURL) else { error = "Use a supported Chrome Remote Desktop link."; return }
        openChrome(desktop.chromeURL) { [weak self] in
            guard let self else { return }
            var item = desktop; item.lastLaunch = Date()
            if self.save(item) { self.operationNotes[item.id] = "Opened in Chrome. A browser launch does not confirm a connected remote session." }
        }
    }
    func openChrome(_ value: String = InputValidation.devicePicker, completed: (() -> Void)? = nil) {
        refreshProfiles()
        let chrome = fixtureMode ? nil : NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome")
        let arguments: [String]
        do { arguments = try ChromeLaunch.arguments(url: value, profiles: profiles, preferences: preferences, applicationAvailable: fixtureMode || chrome != nil) }
        catch { self.error = error.localizedDescription; return }
        if fixtureMode { completed?(); return }
        guard let chrome else { return }
        let process = Process()
        process.executableURL = chrome.appendingPathComponent("Contents/MacOS/Google Chrome")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run(); completed?() } catch { self.error = error.localizedDescription }
    }
    func openChromeForSignIn() {
        guard !fixtureMode else { return }
        guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
            NSWorkspace.shared.open(URL(string: "https://www.google.com/chrome/")!); return
        }
        NSWorkspace.shared.openApplication(at: chrome, configuration: NSWorkspace.OpenConfiguration())
    }
    func check(_ desktop: Desktop, recover: Bool = false) {
        guard !fixtureMode else { error = "Preview data cannot contact SSH hosts."; return }
        guard let target = desktop.target, InputValidation.target(target) else { recoveryDesktop = desktop; return }
        guard observations[desktop.id]?.busy != true else { return }
        if recover && !confirm("Recover \(desktop.name)?", "This asks the installed helper to start this account’s Chrome service only if stopped or failed. Active, disabled and transitioning services are left alone.") { return }
        let identity = desktop.identityPath ?? defaultIdentity
        guard InputValidation.identityPath(identity) else { error = "Choose an absolute SSH private-key path."; return }
        guard let request = hostChecks.begin(desktop.id, recovering: recover) else { return }
        let script = resources.appendingPathComponent("remote-check.sh")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.execute("/usr/bin/ssh", args: SSHPolicy.readinessArguments(identity: identity, target: target, command: "bash -s -- \(recover ? "recover" : "check")"), input: script)
            DispatchQueue.main.async {
                guard let current = self.desktops.first(where: { $0.id == desktop.id }), current.target == target, (current.identityPath ?? self.defaultIdentity) == identity else {
                    self.hostChecks.complete(desktop.id, request: request, observation: nil)
                    return
                }
                let ssh = SSHResult(code: result.code, output: result.output)
                let report = ReadinessReport(output: result.output)
                let authenticated = report.accepts(exitCode: result.code, recoveryRequested: recover)
                self.hostChecks.complete(desktop.id, request: request, observation: HostObservation(checkedAt: Date(), ssh: authenticated ? .ready : ssh, report: authenticated ? report : nil, note: authenticated ? (recover && result.code != 0 ? "Recovery did not complete. Recheck readiness; no rollback is assumed." : "Readiness checked. Google session availability remains unknown.") : ssh.guidance))
            }
        }
    }
    nonisolated static func execute(_ command: String, args: [String], input: URL? = nil) -> (code: Int32, output: String) {
        ProcessRunner.run(command, arguments: args, input: input)
    }

    private func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    func confirm(_ title: String, _ message: String) -> Bool {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.addButton(withTitle: "Continue"); alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
    func terminal(_ desktop: Desktop, action: String) {
        guard !fixtureMode else { error = "Preview data cannot authorise SSH or change hosts."; return }
        let identity = desktop.identityPath ?? defaultIdentity
        guard InputValidation.identityPath(identity), action == "generate-key" || InputValidation.target(desktop.target) else { error = "Save a valid SSH address and key path first."; return }
        let messages = [
            "authorise": "Authorise \(desktop.target ?? "") using \(identity). This adds the public key to that account. Enter Linux passwords directly in Terminal and verify any new host fingerprint against a trusted record. Recovery is not installed by this action.",
            "install": "Install recovery for \(desktop.target ?? ""). Administrator approval installs fixed recovery and read-only status helpers, a two-minute timer and narrow password-free permissions for those helpers. Chrome registration and Google credentials are unchanged.",
            "disable": "Disable Telynd’s timer for this account. Chrome and its registration remain installed. SSH authorisation stays in place.",
            "uninstall": "Remove only the verified Telynd recovery components for this account. Chrome registration, unrelated files and SSH authorisations are preserved. Modified or unrecognised components will require review.",
            "generate-key": "Create a new key at \(identity). Existing files will not be overwritten. Choose a passphrase in the standard SSH prompt; Telynd does not choose or save it."
        ]
        if let message = messages[action], !confirm(action == "generate-key" ? "Create an SSH key?" : "\(action.capitalized) access for \(desktop.name)?", message) { return }
        do {
            let folder = configuration.directory.appendingPathComponent("Launchers")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let receipt = folder.appendingPathComponent("\(desktop.id.uuidString)-\(action).receipt")
            let pending = "TELYND:result=awaiting_terminal\nTELYND:target=\(desktop.target ?? "")\nTELYND:identity=\(identity)\n"
            try pending.write(to: receipt, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: receipt.path)
            let file = folder.appendingPathComponent("\(desktop.id.uuidString)-\(action).command")
            let helper = resources.appendingPathComponent("launch-host.command").path
            let script = "#!/bin/bash\nexec /bin/bash \(quote(helper)) \(quote(desktop.target ?? "")) \(quote(action)) \(quote(identity)) \(quote(receipt.path))\n"
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
            operationNotes[desktop.id] = "Continue in Terminal, then return here and recheck readiness. Interrupted operations may have made partial changes."
            if !NSWorkspace.shared.open(file) { error = "Terminal could not be opened. No completion was verified; try the action again." }
        } catch { self.error = error.localizedDescription }
    }
    func refreshOperationNotes() {
        let folder = configuration.directory.appendingPathComponent("Launchers")
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for item in desktops {
            let receipts = files.filter { $0.lastPathComponent.hasPrefix(item.id.uuidString) && $0.pathExtension == "receipt" }.sorted {
                ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            }
            if let latest = receipts.first, let output = try? String(contentsOf: latest, encoding: .utf8) {
                let fields = ReadinessReport(output: output).values
                guard fields["target"] == (item.target ?? ""), fields["identity"] == (item.identityPath ?? defaultIdentity) else { continue }
                let value = fields["result"] ?? "unknown"
                let labels = ["awaiting_terminal": "The action was prepared for Terminal; no changes or completion have been verified.", "ssh_ready": "SSH authorisation finished and was checked in Terminal.", "installed": "Recovery installation passed its root-side read-back.", "disabled": "The recovery timer was disabled.", "uninstalled": "Verified Telynd recovery components were removed.", "key_created": "The new SSH key was created; authorise it on the host next.", "authentication_failed": "SSH authorisation failed in Terminal. Check the account, host identity and login details before retrying.", "verification_unavailable": "Authorisation was attempted but a new non-interactive SSH connection could not be verified.", "failed": "Setup did not complete. Some steps may have changed the host.", "cancelled": "Setup was interrupted. Some steps may have changed the host.", "in_progress": "Setup was started in Terminal; its final outcome is not yet known."]
                operationNotes[item.id] = (labels[value] ?? "The setup result is unknown.") + " Recheck readiness for current evidence."
            }
        }
    }
}
