import AppKit
import SwiftUI
import TelyndCore
import CryptoKit

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
    @Published private(set) var readingChromeConnection = false
    @Published private(set) var lastRemovedID: UUID?
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
    func suggestedIdentity(for desktop: Desktop) -> String {
        if let saved = desktop.identityPath { return saved }
        if desktop.target != nil { return defaultIdentity }
        return fixtureMode ? "/tmp/telynd-preview/telynd_ed25519" : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/telynd_ed25519").path
    }
    convenience init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var directory = home.appendingPathComponent("Library/Application Support/Telynd")
        var fixture = false
        #if DEBUG
        if let path = Bundle.main.object(forInfoDictionaryKey: "TelyndFixtureDirectory") as? String {
            directory = URL(fileURLWithPath: path); fixture = true
        }
        #endif
        self.init(configuration: ConfigurationStore(directory: directory), fixture: fixture)
    }
    #if DEBUG
    // Tests use isolated settings and retain the existing fixture safety gates.
    convenience init(configuration: ConfigurationStore) {
        self.init(configuration: configuration, fixture: true)
    }
    #endif
    private init(configuration: ConfigurationStore, fixture: Bool) {
        fixtureMode = fixture
        self.configuration = configuration
        do {
            if !fixture { try configuration.migrateLegacy(from: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Remote Desktops")) }
            desktops = try configuration.loadDesktops()
            preferences = try configuration.loadPreferences(existingDesktops: !desktops.isEmpty)
            // The archive is authoritative if an interrupted disk cleanup left an old row.
            let removed = Set(preferences.removedDesktops.map(\.id))
            desktops.removeAll { removed.contains($0.id) }
        } catch { self.error = error.localizedDescription; writeLocked = true }
        refreshProfiles()
        migrateConnectionProfiles()
        refreshOperationNotes()
        showGuide = !preferences.guideCompleted && !writeLocked
    }
    @discardableResult func save(_ desktop: Desktop) -> Bool {
        guard !writeLocked else { error = ConfigurationError.writeLocked.localizedDescription; return false }
        guard !preferences.removedDesktops.contains(where: { $0.id == desktop.id }) else { error = "This computer was removed. Restore it from Recently removed computers before editing it."; return false }
        var desktop = desktop
        if let old = desktops.first(where: { $0.id == desktop.id }), old.chromeURL != desktop.chromeURL || old.chromeProfile != desktop.chromeProfile {
            desktop.lastLaunch = nil; desktop.userConfirmedConnection = nil
        }
        var updated = desktops
        if let i = updated.firstIndex(where: { $0.id == desktop.id }) { updated[i] = desktop } else { updated.append(desktop) }
        do {
            try configuration.saveDesktops(updated)
            if let old = desktops.first(where: { $0.id == desktop.id }), old.target != desktop.target || old.identityPath != desktop.identityPath || old.hostPlatform != desktop.hostPlatform { hostChecks.invalidate(desktop.id); operationNotes[desktop.id] = nil }
            desktops = updated; return true
        }
        catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func remove(_ desktopID: UUID) -> Bool {
        guard !writeLocked else { error = ConfigurationError.writeLocked.localizedDescription; return false }
        guard let desktop = desktops.first(where: { $0.id == desktopID }) else { return false }
        // Commit the recoverable removal first. It remains effective across relaunch
        // even if cleaning the active-list file fails afterwards.
        guard updatePreferences({ value in
            value.removedDesktops.append(desktop)
            if value.guideDesktopID == desktopID { value.guideDesktopID = nil; value.guideStep = .computer }
            if value.guideDraft?.id == desktopID { value.guideDraft = nil }
        }) else { return false }
        desktops.removeAll { $0.id == desktopID }
        hostChecks.invalidate(desktopID); operationNotes[desktopID] = nil
        if recoveryDesktop?.id == desktopID { recoveryDesktop = nil }
        lastRemovedID = desktopID
        do { try configuration.saveDesktops(desktops) }
        catch { self.error = "The computer was removed and can be restored. The active-list file could not be cleaned; the saved removal will still hide it after reopening Telynd." }
        return true
    }
    @discardableResult func restore(_ desktopID: UUID) -> Bool {
        guard !writeLocked else { error = ConfigurationError.writeLocked.localizedDescription; return false }
        guard let desktop = preferences.removedDesktops.first(where: { $0.id == desktopID }), !desktops.contains(where: { $0.id == desktopID }) else { return false }
        let updated = desktops + [desktop]
        do { try configuration.saveDesktops(updated) }
        catch { self.error = error.localizedDescription; return false }
        guard updatePreferences({ $0.removedDesktops.removeAll { $0.id == desktopID } }) else { return false }
        desktops = updated
        if lastRemovedID == desktopID { lastRemovedID = nil }
        return true
    }
    @discardableResult func updatePreferences(_ update: (inout Preferences) -> Void) -> Bool {
        guard !writeLocked else { error = ConfigurationError.writeLocked.localizedDescription; return false }
        var next = preferences; update(&next)
        do { try configuration.savePreferences(next); preferences = next; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func saveGuideDraft(_ desktop: Desktop) -> Bool {
        guard save(desktop), let saved = desktops.first(where: { $0.id == desktop.id }) else { return false }
        // Use the saved value: save() can clear evidence belonging to an old link.
        return updatePreferences {
            $0.guideDesktopID = saved.id
            $0.guideDraft = saved
        }
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
        } catch { profiles = []; profileProblem = ConfigurationError.unreadableProfiles.localizedDescription }
    }
    private func migrateConnectionProfiles() {
        guard !writeLocked, !preferences.connectionProfilesMigrated || preferences.schemaVersion < 3 else { return }
        do {
            let legacy = preferences.connectionProfilesMigrated ? nil : preferences.legacyChromeProfile
            let migrated = desktops.map { ChromeProfiles.migrate($0, legacy: legacy, profiles: profiles) }
            if migrated != desktops { try configuration.saveDesktops(migrated); desktops = migrated }
            let migratedDraft = preferences.guideDraft.map { ChromeProfiles.migrate($0, legacy: legacy, profiles: profiles) }
            if !updatePreferences({ $0.guideDraft = migratedDraft; $0.connectionProfilesMigrated = true; $0.schemaVersion = 3 }) { writeLocked = true }
        } catch { self.error = error.localizedDescription; writeLocked = true }
    }
    func newDesktop() -> Desktop {
        refreshProfiles()
        var desktop = Desktop(name: "")
        let available = profiles.filter(\.signedIn)
        if available.count == 1 { desktop.chromeProfile = available[0].reference }
        return desktop
    }
    func profileReady(for desktop: Desktop) -> Bool { (try? ChromeProfiles.selected(in: profiles, reference: desktop.chromeProfile)) != nil }
    func captureChromeConnection(_ completion: @escaping (Result<String, Error>) -> Void) {
        guard !readingChromeConnection else { return }
        guard !fixtureMode else { completion(.failure(ChromeCaptureError.unavailable)); return }
        readingChromeConnection = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try ChromeTabReader.read() }
            DispatchQueue.main.async {
                self.readingChromeConnection = false
                completion(result)
            }
        }
    }
    func connect(_ desktop: Desktop) {
        guard desktops.contains(where: { $0.id == desktop.id }) else { error = "Restore this computer before connecting."; return }
        guard desktop.hasDirectConnection else { error = "Save this computer’s individual connection link before connecting. Choose Edit, open the computer in Chrome and choose Use open computer."; return }
        openChrome(desktop) { [weak self] in
            guard let self else { return }
            var item = desktop; item.lastLaunch = Date()
            if self.save(item) { self.operationNotes[item.id] = "Opened in Chrome. A browser launch does not confirm a connected remote session." }
        }
    }
    func openChrome(_ desktop: Desktop, picker: Bool = false, completed: (() -> Void)? = nil) {
        refreshProfiles()
        let chrome = fixtureMode ? nil : NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome")
        let arguments: [String]
        do {
            if picker {
                let profile = try ChromeProfiles.selected(in: profiles, reference: desktop.chromeProfile)
                guard fixtureMode || chrome != nil else { throw ConfigurationError.chromeMissing }
                arguments = ["--profile-directory=\(profile.directory)", InputValidation.devicePicker]
            } else { arguments = try ChromeLaunch.arguments(desktop: desktop, profiles: profiles, applicationAvailable: fixtureMode || chrome != nil) }
        }
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
        guard desktops.contains(where: { $0.id == desktop.id }) else { return }
        refreshOperationNotes()
        guard desktop.hostPlatform.usesSSHRecovery else { recoveryDesktop = desktop; return }
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
                guard let current = self.desktops.first(where: { $0.id == desktop.id }), current.hostPlatform == desktop.hostPlatform, current.target == target, (current.identityPath ?? self.defaultIdentity) == identity else {
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
    @discardableResult func terminal(_ desktop: Desktop, action: String) -> Bool {
        guard !writeLocked, let saved = desktops.first(where: { $0.id == desktop.id }), saved.target == desktop.target, saved.identityPath == desktop.identityPath, saved.hostPlatform == desktop.hostPlatform else { error = "Save this computer’s current recovery details before continuing."; return false }
        guard !fixtureMode else { error = "Preview data cannot authorise SSH or change hosts."; return false }
        guard desktop.hostPlatform.usesSSHRecovery else { error = "Use the host-local recovery kit for this operating system."; return false }
        let identity = desktop.identityPath ?? defaultIdentity
        guard InputValidation.identityPath(identity), action == "generate-key" || InputValidation.target(desktop.target) else { error = "Save a valid SSH address and key path first."; return false }
        let messages = [
            "setup-access": "Set up SSH access to \(desktop.target ?? "") using \(identity). Telynd creates a key only if both key files are absent, then adds its public key to that Linux account. Choose a passphrase, compare the host fingerprint and enter the Linux login password in Terminal when requested. SSH must already be enabled and reachable. Recovery is installed separately.",
            "authorise": "Authorise \(desktop.target ?? "") using \(identity). This adds the public key to that account. Enter Linux passwords directly in Terminal and verify any new host fingerprint against a trusted record. Recovery is not installed by this action.",
            "install": "Install recovery for \(desktop.target ?? ""). Administrator approval installs fixed recovery and read-only status helpers, a two-minute timer and narrow password-free permissions for those helpers. Chrome registration and Google credentials are unchanged.",
            "disable": "Disable Telynd’s timer for this account. Chrome and its registration remain installed. SSH authorisation stays in place.",
            "uninstall": "Remove only the verified Telynd recovery components for this account. Chrome registration, unrelated files and SSH authorisations are preserved. Modified or unrecognised components will require review.",
            "generate-key": "Create a new key at \(identity). Existing files will not be overwritten. Choose a passphrase in the standard SSH prompt; Telynd does not choose or save it."
        ]
        let title = action == "setup-access" ? "Set up SSH access for \(desktop.name)?" : (action == "generate-key" ? "Create an SSH key?" : "\(action.capitalized) access for \(desktop.name)?")
        if let message = messages[action], !confirm(title, message) { return false }
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
            if !NSWorkspace.shared.open(file) { error = "Terminal could not be opened. No completion was verified; try the action again."; return false }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func exportRecoveryKit(_ desktop: Desktop) {
        guard !fixtureMode else { error = "Recovery kits cannot be exported from synthetic preview data."; return }
        let files = RecoveryKit.files(for: desktop.hostPlatform)
        guard !files.isEmpty else { return }
        let panel = NSSavePanel(); panel.title = "Save recovery kit for the remote computer"
        panel.nameFieldStringValue = "Telynd-\(desktop.hostPlatform.rawValue)-\(desktop.id.uuidString)"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            guard !FileManager.default.fileExists(atPath: destination.path) else { error = "Choose a new folder. Existing files will not be replaced."; return }
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            var checksums: [String] = []
            for name in files {
                let data = try Data(contentsOf: resources.appendingPathComponent(name))
                let output = destination.appendingPathComponent(name)
                try data.write(to: output, options: .withoutOverwriting)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
                checksums.append(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + "  " + name)
            }
            try RecoveryKit.instructions(for: desktop).write(to: destination.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
            try checksums.joined(separator: "\n").appending("\n").write(to: destination.appendingPathComponent("SHA256SUMS"), atomically: true, encoding: .utf8)
            operationNotes[desktop.id] = "Recovery kit saved. Follow its README on the remote computer, then import a fresh report. No host changes have been made by exporting."
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch { self.error = "Kit export did not complete: \(error.localizedDescription). Review the destination before retrying." }
    }
    func importHostReport(_ desktop: Desktop) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.title = "Import a report exported by this computer’s recovery kit"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try LocalHostReport.read(from: url)
            guard let current = desktops.first(where: { $0.id == desktop.id }), current.hostPlatform == desktop.hostPlatform,
                  current.target == desktop.target, current.identityPath == desktop.identityPath else { throw HostReportError.mismatch }
            let report = try LocalHostReport.parse(data, desktop: desktop).readiness
            hostChecks.invalidate(desktop.id)
            if let request = hostChecks.begin(desktop.id, recovering: false) {
                hostChecks.complete(desktop.id, request: request, observation: HostObservation(checkedAt: report.checkedAt, report: report, note: "Imported snapshot supplied by you. Host identity and current state have not been checked live."))
            }
        } catch { self.error = error.localizedDescription }
    }
    func refreshOperationNotes() {
        let folder = configuration.directory.appendingPathComponent("Launchers")
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for item in desktops {
            guard item.hostPlatform.usesSSHRecovery else { continue }
            let receipts = files.filter { $0.lastPathComponent.hasPrefix(item.id.uuidString) && $0.pathExtension == "receipt" }.sorted {
                ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            }
            if let latest = receipts.first, let output = try? String(contentsOf: latest, encoding: .utf8) {
                let fields = ReadinessReport(output: output).values
                guard fields["target"] == (item.target ?? ""), fields["identity"] == (item.identityPath ?? defaultIdentity) else { continue }
                let value = fields["result"] ?? "unknown"
                let labels = ["awaiting_terminal": "The action was prepared for Terminal; no changes or completion have been verified.", "ssh_ready": "Public-key authorisation finished. SSH account access was verified using your SSH configuration; other configured keys may have been used.", "key_validation_failed": "The selected key could not be read or validated. Check its format, permissions and passphrase.", "key_pair_mismatch": "The .pub file does not match the selected private key. Nothing was sent to the host.", "installed": "Recovery installation passed its root-side read-back.", "disabled": "The recovery timer was disabled.", "uninstalled": "Verified Telynd recovery components were removed.", "key_created": "The new SSH key was created; authorise it on the host next.", "authentication_failed": "SSH authorisation failed in Terminal. Check the account, host identity and login details before retrying.", "verification_unavailable": "Authorisation was attempted but a new non-interactive SSH connection could not be verified.", "failed": "Setup did not complete. Some steps may have changed the host.", "cancelled": "Setup was interrupted. Some steps may have changed the host.", "in_progress": "Setup was started in Terminal; its final outcome is not yet known."]
                operationNotes[item.id] = (labels[value] ?? "The setup result is unknown.") + " Recheck readiness for current evidence."
            }
        }
    }
    func terminalResult(_ desktop: Desktop, action: String) -> String? {
        let file = configuration.directory.appendingPathComponent("Launchers/\(desktop.id.uuidString)-\(action).receipt")
        guard let output = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let values = ReadinessReport(output: output).values
        guard values["action"] == action, values["target"] == desktop.target, values["identity"] == (desktop.identityPath ?? defaultIdentity) else { return nil }
        return values["result"]
    }
}
