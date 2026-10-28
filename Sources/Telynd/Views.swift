import SwiftUI
import AppKit
import TelyndCore

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(Color(red: 18 / 255, green: 92 / 255, blue: 1).opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}
struct ConnectButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Color(red: 18 / 255, green: 92 / 255, blue: 1).opacity(!enabled ? 0.4 : (configuration.isPressed ? 0.8 : 1)), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}
struct Wordmark: View {
    @Environment(\.colorScheme) var scheme
    var compact = false
    var body: some View {
        if let url = Bundle.main.url(forResource: scheme == .dark ? "telynd-logo-dark" : "telynd-logo-v2", withExtension: "png"), let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: compact ? 120 : 230, height: compact ? 38 : 72, alignment: .leading).accessibilityLabel("Telynd")
        } else { Text("Telynd").font(.largeTitle.bold()) }
    }
}
struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @State private var editing: Desktop?
    @State private var search = ""
    @State private var showingRemoved = false
    var filtered: [Desktop] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.desktops.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || ($0.chromeProfile?.email.localizedCaseInsensitiveContains(query) ?? false) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Wordmark(compact: true)
                Spacer(minLength: 16)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search computers", text: $search).textFieldStyle(.plain)
                        .accessibilityLabel("Search computers")
                }.padding(.horizontal, 10).padding(.vertical, 7).frame(width: 210)
                    .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                Button { editing = store.newDesktop() } label: { Label("Add computer", systemImage: "plus") }
                    .controlSize(.regular).disabled(store.writeLocked)
                Menu {
                    Button("Setup guide") { store.refreshProfiles(); store.showGuide = true }
                    Button("Recently removed computers…") { showingRemoved = true }.disabled(store.preferences.removedDesktops.isEmpty)
                } label: { Image(systemName: "questionmark.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Help")
            }.padding(.horizontal, 24).padding(.vertical, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Your computers").font(.system(size: 22, weight: .semibold))
                        Spacer()
                        Text("\(store.desktops.count) saved").font(.callout).foregroundStyle(.secondary)
                    }
                    if store.fixtureMode { Text("Preview · synthetic accounts; network actions disabled").font(.caption).foregroundStyle(.secondary) }
                    if let id = store.lastRemovedID, let removed = store.preferences.removedDesktops.first(where: { $0.id == id }) {
                        HStack { Text("Removed \(removed.name) from Telynd."); Spacer(); Button("Undo") { _ = store.restore(id) } }
                            .font(.callout).padding(12).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if store.writeLocked {
                        Label("Settings need attention. Your saved files have been preserved; correct them and reopen Telynd before saving.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                    if !store.preferences.guideCompleted && !store.showGuide {
                        HStack { Text("Your setup progress is saved."); Spacer(); Button("Continue setup") { store.showGuide = true } }
                            .padding(14).background(.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if store.desktops.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "desktopcomputer").font(.system(size: 36)).foregroundStyle(.secondary)
                            Text("A home for your remote computers").font(.title3.weight(.semibold))
                            Text("Add a computer and Telynd remembers how you connect.").foregroundStyle(.secondary)
                            Button("Add your first computer") { editing = store.newDesktop() }.buttonStyle(.borderedProminent).disabled(store.writeLocked)
                        }.frame(maxWidth: .infinity).padding(.vertical, 54)
                    } else if filtered.isEmpty {
                        Text("No computers match your search.").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(filtered) { item in DesktopRow(desktop: item) { editing = item } }
                        }
                    }
                    Text("Desktop connections open in Chrome. SSH terminals open inside Telynd.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth: 960, alignment: .leading).frame(maxWidth: .infinity)
            }
        }.frame(minWidth: 720, minHeight: 420)
            .background(Color(nsColor: .windowBackgroundColor))
            .tint(Color(red: 18 / 255, green: 92 / 255, blue: 1))
            .sheet(item: $editing) { DesktopEditor(desktop: $0) }
            .sheet(isPresented: $showingRemoved) { RemovedComputersSheet() }
            .sheet(isPresented: $store.showGuide) { OnboardingGuide() }
            .sheet(item: $store.recoveryDesktop) { RecoverySheet(desktop: $0) }
            .sheet(item: $store.sshSettingsDesktop) { SSHSettingsSheet(desktop: $0) }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.refreshProfiles(); store.refreshOperationNotes() }
            .alert("Telynd", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
}
struct RemovedComputersSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var pendingDeletion: Desktop?
    @State private var confirmingDeletion = false
    @State private var deletionError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Recently removed computers").font(.title2.bold())
            Text("These entries were removed from Telynd. Their Google registration, SSH access and host recovery were left in place.").font(.callout).foregroundStyle(.secondary)
            Text("Kept until you restore or permanently delete them. There is no automatic expiry.").font(.caption).foregroundStyle(.secondary)
            if let deletionError { Text(deletionError).font(.callout).foregroundStyle(.red) }
            ScrollView {
                VStack(spacing: 14) {
                    if store.preferences.removedDesktops.isEmpty { Text("No removed computers.").foregroundStyle(.secondary) }
                    ForEach(Array(store.preferences.removedDesktops.reversed())) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name).font(.headline)
                                if let email = item.chromeProfile?.email { Text(email).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Button("Delete permanently…", role: .destructive) { deletionError = nil; pendingDeletion = item; confirmingDeletion = true }
                                .disabled(store.writeLocked).accessibilityLabel("Permanently delete \(item.name)")
                            Button("Restore") { _ = store.restore(item.id) }.buttonStyle(ConnectButton()).disabled(store.writeLocked).accessibilityLabel("Restore \(item.name)")
                        }.padding(12).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 580, height: 420)
            .alert("Permanently delete \(pendingDeletion?.name ?? "this computer")?", isPresented: $confirmingDeletion) {
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
                Button("Delete permanently", role: .destructive) {
                    if let item = pendingDeletion, !store.permanentlyDelete(item.id) {
                        deletionError = store.error ?? "This entry could not be deleted. Reopen Recently removed computers and try again."
                        store.error = nil
                    }
                    pendingDeletion = nil
                }
            } message: {
                Text("This deletes the saved computer entry from Telynd. You cannot restore it afterwards. Its Google registration, SSH keys and remote recovery stay in place.")
            }
    }
}
struct DesktopRow: View {
    @EnvironmentObject var store: AppStore
    let desktop: Desktop
    let edit: () -> Void
    @State private var now = Date()
    @State private var detailsExpanded = false
    @State private var confirmingRemoval = false
    var observed: HostObservation { store.observations[desktop.id] ?? HostObservation() }
    var title: String {
        if observed.busy { return "Checking recovery…" }
        if let report = observed.report { return report.isStale(at: now) ? "Recovery status needs a refresh" : report.configurationLabel(at: now) }
        if desktop.target == nil || !desktop.hostPlatform.usesSSHRecovery { return "Connection only" }
        return observed.ssh == nil ? "Recovery not checked" : "Recovery needs attention"
    }
    var action: String {
        if !store.profileReady(for: desktop) { return "Choose account" }
        return desktop.hasDirectConnection ? "Connect" : "Set connection"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: desktop.symbol).font(.system(size: 21, weight: .regular)).foregroundStyle(.secondary)
                    .frame(width: 44, height: 44).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 5) {
                    Text(desktop.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text([desktop.hostPlatform == .unknown ? nil : desktop.hostPlatform.label, desktop.chromeProfile?.email ?? "Choose a browser account"].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 12)
                Button { store.startSSH(desktop) } label: { Label("Start SSH", systemImage: "terminal") }
                    .disabled(store.writeLocked).accessibilityLabel("Start SSH for \(desktop.name)")
                    .help("Open an SSH terminal inside Telynd.")
                Button { if desktop.hasDirectConnection && store.profileReady(for: desktop) { store.connect(desktop) } else { edit() } } label: {
                    Text(action).frame(minWidth: 64)
                }.buttonStyle(ConnectButton()).disabled(store.writeLocked)
                    .accessibilityLabel("\(action) \(desktop.name)")
                    .help("Open a separate Chrome session window using this computer’s saved account.")
                Menu {
                    Button("Edit computer…", action: edit).disabled(store.writeLocked)
                    Button("SSH settings…") { store.sshSettingsDesktop = desktop }.disabled(store.writeLocked)
                    Button("Open in Chrome tab") { store.connect(desktop, presentation: .tab) }
                        .disabled(store.writeLocked || !desktop.hasDirectConnection || !store.profileReady(for: desktop))
                    Button(detailsExpanded ? "Hide details" : "Details & recovery") { detailsExpanded.toggle() }
                    Divider()
                    Button("Recovery settings…") { store.recoveryDesktop = desktop }.disabled(store.writeLocked)
                    Divider()
                    Button("Remove from Telynd…", role: .destructive) { confirmingRemoval = true }.disabled(store.writeLocked)
                } label: { Image(systemName: "ellipsis").frame(width: 18, height: 24) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Options for \(desktop.name)")
            }
            if detailsExpanded {
                Divider()
                HStack { Text(title).font(.callout.weight(.medium)); Spacer(); Button("Hide details") { detailsExpanded = false }.buttonStyle(.link) }
                StatusDetails(observation: observed, now: now, platform: desktop.hostPlatform)
                if let launched = desktop.lastLaunch { Text("Last opened: \(launched.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                if let note = store.operationNotes[desktop.id] { Text("Last action: " + note).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                HStack {
                    Button("Recovery settings…") { store.recoveryDesktop = desktop }
                    Spacer()
                    if !desktop.hostPlatform.usesSSHRecovery { Button("Import report") { store.importHostReport(desktop) } }
                    else if desktop.target != nil { Button("Recheck") { store.check(desktop) }.disabled(observed.busy) }
                }.buttonStyle(.link)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.07)))
            .alert("Remove \(desktop.name) from Telynd?", isPresented: $confirmingRemoval) {
                Button("Cancel", role: .cancel) {}
                Button("Remove computer", role: .destructive) { _ = store.remove(desktop.id) }
            } message: {
                Text("You can restore it from Recently removed computers in Help. This leaves its Google registration, SSH keys and recovery timer in place. Any setup already open in Terminal continues. To stop host recovery, use Recovery settings before removing this entry.")
            }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
    }
}
struct StatusDetails: View {
    let observation: HostObservation
    var now = Date()
    var platform: HostPlatform = .unknown
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if observation.busy { ProgressView("Checking readiness…").controlSize(.small) }
            else {
                if observation.report?.imported == true {
                    Text("Evidence: imported host snapshot · identity not verified")
                    Text("Host: \(observation.report?.values["os"] ?? "unknown") \(observation.report?.values["os_version"] ?? "")")
                    Text("Recovery scope: \(observation.report?.values["recovery_scope"] ?? "unknown")")
                    if platform == .macos { Text("Privacy permissions: unknown — review on the host") }
                } else if platform.usesSSHRecovery { Text("SSH: \(observation.ssh == .ready ? "access verified" : "not verified")") }
                else { Text("Evidence: no imported host snapshot") }
                Text("Chrome service: \(observation.report?.serviceLabel ?? "unknown")")
                if platform.usesSSHRecovery && observation.report?.imported != true { Text("Recovery timer: \(observation.report?.values["timer"] ?? "unknown")") }
                Text("Google connection: not verified by Telynd")
                if let date = observation.checkedAt { Text("Checked \(date.formatted(date: .omitted, time: .shortened))\(now.timeIntervalSince(date) > 300 ? " · stale — recheck" : "")") }
                if let report = observation.report {
                    if let enabled = report.values["chrome_enabled"], !["enabled", "enabled-runtime"].contains(enabled) { Text("Recovery leaves a host that is not enabled alone. Ask the administrator to review its intended state.") }
                    if report.values["service_loaded"] == "not-found" { Text("Set up the Linux Chrome host for this account using Google’s guide, then recheck.") }
                    if let missing = report.values["missing_tools"], !missing.isEmpty { Text("Ask the host administrator to provide: \(missing). Recheck afterwards.") }
                    if !report.supported { Text("Keep connection-only access. Review the selected operating system and its recovery instructions.") }
                }
                Text(observation.note).fixedSize(horizontal: false, vertical: true)
            }
        }.font(.caption).foregroundStyle(.secondary).textSelection(.enabled).accessibilityElement(children: .contain)
    }
}
struct ComputerAccountPicker: View {
    @EnvironmentObject var store: AppStore
    @Binding var desktop: Desktop
    var selection: String {
        guard let reference = desktop.chromeProfile else { return "" }
        return store.profileReady(for: desktop) ? (reference.directory ?? "") : "/unavailable"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Browser account", selection: Binding(get: { selection }, set: { value in
                desktop.chromeProfile = store.profiles.first(where: { $0.directory == value && $0.signedIn })?.reference
            })) {
                Text("Choose an account").tag("")
                if selection == "/unavailable" { Text("\(desktop.chromeProfile?.email ?? "Saved account") — unavailable").tag("/unavailable") }
                ForEach(store.profiles) { profile in Text(profile.label).tag(profile.directory).disabled(!profile.signedIn) }
            }
            Text("Uses a Chrome profile saved for this computer. Google sign-in stays in Chrome.").font(.caption).foregroundStyle(.secondary)
            if let problem = store.profileProblem { Text(problem).font(.caption).foregroundStyle(.secondary) }
            if selection == "/unavailable" { Text("This computer’s saved Chrome profile is unavailable. Choose its account again; Telynd will not switch accounts automatically.").font(.caption).foregroundStyle(.orange) }
            HStack { Button("Refresh accounts") { store.refreshProfiles() }; Button("Open Chrome to sign in…") { store.openChromeForSignIn() } }.font(.caption).buttonStyle(.link)
        }.onAppear { store.refreshProfiles() }
    }
}
struct DesktopEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State var desktop: Desktop
    private enum Step { case connection, recovery }
    @State private var step = Step.connection
    @State private var savedForRecovery: Desktop?
    var isNew: Bool { !store.desktops.contains(where: { $0.id == desktop.id }) }
    var canSave: Bool { desktop.valid && desktop.hasDirectConnection && store.profileReady(for: desktop) && !store.writeLocked }
    func save(openRecovery: Bool) {
        guard canSave, store.save(desktop) else { return }
        if openRecovery {
            // Replace this editor's contents after saving. A second sheet cannot
            // race the dismissal of the first, and recovery gets the saved record.
            savedForRecovery = store.desktops.first(where: { $0.id == desktop.id })
        } else { dismiss() }
    }
    var body: some View {
        if let savedForRecovery { RecoverySheet(desktop: savedForRecovery) }
        else {
        VStack(alignment: .leading, spacing: 20) {
            Text(isNew ? "Add computer" : "Computer details").font(.title2.bold())
            HStack(spacing: 12) {
                Button("1. Connection") { step = .connection }
                    .foregroundStyle(step == .connection ? Color.accentColor : Color.secondary)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                Button("2. Recovery (optional)") { step = .recovery }
                    .foregroundStyle(step == .recovery ? Color.accentColor : Color.secondary)
            }.buttonStyle(.plain).font(.callout.weight(.medium))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if step == .connection { ComputerFields(desktop: $desktop) }
                    else { RecoveryIntroduction(platform: $desktop.hostPlatform) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            if step == .connection {
                Text("Next: optional recovery, including guided SSH setup for Linux.").font(.caption).foregroundStyle(.secondary)
            } else if !canSave {
                Text("Complete the Connection step before saving or starting recovery setup.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if step == .recovery { Button("Back") { step = .connection } }
                Spacer()
                if step == .connection {
                    if !isNew { Button("Save") { save(openRecovery: false) }.disabled(!canSave) }
                    Button("Continue to recovery") { step = .recovery }.buttonStyle(ConnectButton())
                        .keyboardShortcut(.defaultAction).disabled(!canSave)
                } else {
                    Button(isNew ? "Save connection only" : "Save") { save(openRecovery: false) }.disabled(!canSave)
                    Button("Save & set up recovery…") { save(openRecovery: true) }
                        .buttonStyle(ConnectButton()).keyboardShortcut(.defaultAction)
                        .disabled(!canSave || desktop.hostPlatform == .unknown)
                }
            }
        }.padding(28).frame(width: 640, height: 600)
        }
    }
}
struct RecoveryIntroduction: View {
    @Binding var platform: HostPlatform
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add a recovery route").font(.title3.weight(.semibold))
            Text("If the Chrome Remote Desktop service fails, recovery can help restore access. You can set it up now or add it later from the computer’s options.").font(.callout).foregroundStyle(.secondary)
            Picker("Remote operating system", selection: $platform) {
                ForEach(HostPlatform.allCases) { item in Text(item.label).tag(item) }
            }
            if platform == .unknown {
                Text("Choose the remote computer’s operating system to see its recovery steps. Linux uses SSH; Mac and Windows use setup on the remote computer.").font(.callout).foregroundStyle(.secondary)
            } else if platform.usesSSHRecovery {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Linux recovery uses SSH", systemImage: "terminal").font(.headline)
                    Text("The setup helper supplies the details and Telynd finds a matching connection. SSH provides the recovery route behind the scenes.").font(.callout).foregroundStyle(.secondary)
                    Label("Download and open Telynd Setup inside your Linux remote desktop.", systemImage: "1.circle")
                    Label("Paste its setup card; Telynd checks the connection.", systemImage: "2.circle")
                    Label("Approve access, then enable recovery.", systemImage: "3.circle")
                    Text("The desktop helper supports Ubuntu/Debian. Both computers need a shared network or existing VPN. One-time passwords and administrator approvals stay in system prompts; manual setup remains available under Advanced.").font(.caption).foregroundStyle(.secondary)
                }.font(.callout).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            } else {
                Label(platform == .macos ? "Mac recovery runs in a signed-in desktop session." : "Windows recovery can restart a crashed service.", systemImage: "arrow.clockwise").font(.headline)
                Text("No SSH setup is needed. Telynd helps you export a recovery kit to run on that computer. These kits are development previews awaiting real-host validation and distribution signing.").font(.callout).foregroundStyle(.secondary)
            }
            Text("Recovery cannot wake a sleeping computer, repair its network or renew Google sign-in. Connecting works without recovery.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
struct ComputerFields: View {
    @Binding var desktop: Desktop
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Name").font(.subheadline.weight(.medium))
            TextField("Computer name, for example Home PC", text: $desktop.name)
            ComputerAccountPicker(desktop: $desktop)
            ConnectionLinkFields(desktop: $desktop)
        }
    }
}
struct ConnectionLinkFields: View {
    @EnvironmentObject var store: AppStore
    @Binding var desktop: Desktop
    @State private var pasteError: String?
    @State private var feedbackIsError = false
    @State private var manualEntryExpanded = false
    @State private var captureRequests = ChromeCaptureRequests()
    @State private var setup: ChromeSetupCapture?
    private let setupTicks = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private func stopDetection() { setup = nil; captureRequests.invalidate() }
    private func startSetup() {
        stopDetection(); pasteError = nil
        let session = ChromeSetupCapture(desktop: desktop, markerPage: store.resources.appendingPathComponent("chrome-setup.html"))
        store.openChromeSetup(desktop, session: session) { setup = session }
    }
    private func showCaptureError(_ error: Error) {
        pasteError = error.localizedDescription
        feedbackIsError = !((error as? ChromeCaptureError)?.isGuidance ?? false)
    }
    private func pollSetup() {
        guard let session = setup else { return }
        guard session.isCurrent(desktop) else {
            stopDetection(); pasteError = "Detection stopped. Choose computer in Chrome to try again, or enter its link manually."; feedbackIsError = false; return
        }
        guard session.candidate == nil, !store.readingChromeConnection else { return }
        let request = session.request
        store.inspectChromeSetup(request) { result in
            guard var active = setup, active.id == session.id, active.isCurrent(desktop) else { return }
            switch result {
            case .success(let snapshot):
                let accepted = active.receive(snapshot, for: request, current: desktop)
                setup = active
                if accepted && active.candidate != nil { NSApp.requestUserAttention(.informationalRequest) }
            case .failure(let error): stopDetection(); showCaptureError(error)
            }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connection link").font(.subheadline.weight(.medium))
            if setup?.candidate == nil { HStack {
                Button("Choose computer in Chrome", action: startSetup)
                    .disabled(!store.profileReady(for: desktop) || setup != nil || store.readingChromeConnection)
                if setup != nil { Button("Cancel detection") { stopDetection() } }
            } }
            if let session = setup {
                if session.candidate != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Computer link detected", systemImage: "checkmark.circle").font(.callout.weight(.medium))
                        Text("Check that you selected the intended computer in Chrome. Use this link with the browser account shown above, then Save.").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Use this computer") {
                                guard let link = setup?.confirmedLink(current: desktop) else { pollSetup(); return }
                                stopDetection(); desktop.chromeURL = link; pasteError = nil
                            }
                            Button("Discard") { stopDetection() }
                        }
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    ProgressView("Choose your computer in the Chrome window Telynd opened…").controlSize(.small)
                    Text("Telynd detects the link automatically in that tab, even while Chrome is in the background. Return here to confirm. Detection stops after five minutes or when you cancel or close setup.").font(.caption).foregroundStyle(.secondary)
                }
            } else if let pasteError { Text(pasteError).font(.caption).foregroundStyle(feedbackIsError ? Color.red : Color.secondary) }
            else if desktop.hasDirectConnection && store.profileReady(for: desktop) {
                Text("Connect opens this computer using \(desktop.chromeProfile?.email ?? "its saved browser account").").font(.caption).foregroundStyle(.secondary)
            } else if desktop.hasDirectConnection {
                Text("Choose this computer’s browser account to enable Connect.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Choose computer in Chrome, then select it in Google’s list. Telynd detects its link for you to confirm. macOS may ask permission to interact with Chrome.").font(.callout).foregroundStyle(.secondary)
                Link("Chrome Remote Desktop setup", destination: URL(string: "https://support.google.com/chrome/answer/1649523")!).font(.caption)
            }
            DisclosureGroup("Other ways to add a link", isExpanded: $manualEntryExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Button("Use open computer") {
                        stopDetection(); pasteError = nil
                        let request = captureRequests.begin(for: desktop)
                        store.captureChromeConnection { result in
                            guard captureRequests.consume(request, current: desktop) else { return }
                            switch result {
                            case .success(let link): desktop.chromeURL = link
                            case .failure(let error): showCaptureError(error)
                            }
                        }
                    }.disabled(store.readingChromeConnection || !store.profileReady(for: desktop))
                    Text("Use open computer reads Chrome’s front tab once. You can also paste an individual computer link below.").font(.caption).foregroundStyle(.secondary)
                    TextField("https://remotedesktop.google.com/access/session/…", text: Binding(
                        get: { desktop.chromeURL == InputValidation.devicePicker || desktop.chromeURL == InputValidation.devicePicker + "/" ? "" : desktop.chromeURL },
                        set: { stopDetection(); desktop.chromeURL = $0.isEmpty ? InputValidation.devicePicker : $0; pasteError = nil }
                    )).accessibilityLabel("Individual computer connection link")
                    Button("Paste link") {
                        stopDetection()
                        guard let value = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), InputValidation.directChromeURL(value) else {
                            pasteError = "Copy the address after opening your computer in Chrome Remote Desktop."; feedbackIsError = false; return
                        }
                        desktop.chromeURL = value; pasteError = nil
                    }
                    if !InputValidation.chromeURL(desktop.chromeURL) { Text("This is not an individual Google Remote Desktop link.").font(.caption).foregroundStyle(.red) }
                }.padding(.top, 10)
            }.font(.callout)
        }.onChange(of: desktop) { _ in stopDetection(); pasteError = nil }
            .onReceive(setupTicks) { _ in pollSetup() }
            .onDisappear { stopDetection() }
    }
}
struct OnboardingGuide: View {
    @EnvironmentObject var store: AppStore
    @State private var draft = Desktop(name: "")
    var step: GuideStep { store.preferences.guideStep }
    var chosen: Desktop? { store.desktops.first(where: { $0.id == store.preferences.guideDesktopID }) }
    func advance(_ next: GuideStep) { _ = store.updatePreferences { $0.guideStep = next } }
    func saveDraft() -> Bool {
        var value = draft
        if let saved = chosen, saved.id == draft.id { value.lastLaunch = saved.lastLaunch; value.userConfirmedConnection = saved.userConfirmedConnection }
        return store.saveGuideDraft(value)
    }
    func finish(recovery: Bool = false) {
        if store.updatePreferences({ $0.guideStep = .finished; $0.guideCompleted = true; $0.guideDraft = nil }) {
            store.showGuide = false
            if recovery, let desktop = chosen { DispatchQueue.main.async { store.recoveryDesktop = desktop } }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack { Wordmark(); Spacer(); Text("Setup").font(.callout).foregroundStyle(.secondary) }
            Text(step.title).font(.title2.bold())
            if store.fixtureMode { Text("Preview · synthetic profiles; Chrome launch is simulated").font(.caption).foregroundStyle(.secondary) }
            ScrollView { Group {
                switch step {
                case .welcome:
                    Text("Telynd keeps your remote computers in one place. Google Chrome Remote Desktop provides the screen connection and handles its sign-in and PIN.")
                    Text("First, save a computer and its browser account. Optional recovery can be configured afterwards for your remote computer’s operating system. You do not need SSH or administrator access to make your first connection.").foregroundStyle(.secondary)
                case .profile, .computer: ComputerFields(desktop: $draft)
                case .connect:
                    if let desktop = chosen {
                        if desktop.hasDirectConnection && store.profileReady(for: desktop) {
                            Text("Connect to \(desktop.name) using \(desktop.chromeProfile?.email ?? "its saved browser account").")
                            Button("Connect") { store.connect(desktop) }.buttonStyle(PrimaryButton())
                            Text("Opening Chrome does not confirm a remote session. You can continue after launching, or record that you connected successfully yourself.").font(.callout).foregroundStyle(.secondary)
                            if desktop.lastLaunch != nil { Text("Chrome launch recorded.").font(.callout) }
                            Button("I connected successfully") { var value = desktop; value.userConfirmedConnection = Date(); if store.save(value) { advance(.recovery) } }
                        } else {
                            ComputerAccountPicker(desktop: $draft)
                            ConnectionLinkFields(desktop: $draft)
                            Button("Save connection link") { _ = saveDraft() }.disabled(!draft.valid || !draft.hasDirectConnection || !store.profileReady(for: draft))
                        }
                    } else { Text("No computer is saved for this guide. Go back to add one.") }
                case .recovery:
                    RecoveryIntroduction(platform: $draft.hostPlatform)
                    Button("Save & set up recovery…") {
                        if saveDraft() { finish(recovery: true) }
                    }.buttonStyle(ConnectButton()).disabled(chosen == nil || draft.hostPlatform == .unknown)
                case .finished:
                    Text("Your computers and their browser accounts are saved. Choose Connect, or open a computer’s options for recovery settings.")
                }
            }.frame(maxWidth: .infinity, alignment: .leading) }
            Spacer(minLength: 12)
            Divider()
            HStack {
                Button("Save progress and close") { store.showGuide = false }.keyboardShortcut(.cancelAction)
                Spacer()
                if step != .welcome && step != .finished { Button("Back") { advance(step == .computer || step == .profile ? .welcome : (GuideStep(rawValue: step.rawValue - 1) ?? .welcome)) } }
                switch step {
                case .welcome: Button("Get started") { advance(.computer) }.buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction)
                case .profile, .computer: Button("Save and continue") { if saveDraft() { advance(.connect) } }.buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction).disabled(!draft.valid || !draft.hasDirectConnection || !store.profileReady(for: draft))
                case .connect: Button("Continue after opening Chrome") { advance(.recovery) }.keyboardShortcut(.defaultAction).disabled(chosen?.lastLaunch == nil || chosen?.hasDirectConnection != true || chosen.map { !store.profileReady(for: $0) } != false)
                case .recovery: Button("Finish with connection-only access") {
                    if chosen == nil || saveDraft() { finish() }
                }.buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction)
                case .finished: Button("Done") { store.showGuide = false }.buttonStyle(PrimaryButton())
                }
            }
        }.padding(30).frame(width: 730, height: 560)
            .onAppear { draft = step == .connect ? (chosen ?? store.newDesktop()) : (store.preferences.guideDraft ?? chosen ?? store.newDesktop()) }
            .onChange(of: draft) { value in if step == .computer || step == .profile { _ = store.updatePreferences { $0.guideDraft = value } } }
    }
}
struct RecoverySheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State var desktop: Desktop
    @State private var platform: HostPlatform = .unknown
    @State private var address = SSHAddress()
    @State private var addressError: String?
    @State private var identity = ""
    @State private var now = Date()
    @State private var waitingAction: String?
    @State private var manualConnection = false
    @State private var pairedName: String?
    @State private var pairingKeys: [PairingKey] = []
    var observed: HostObservation { store.observations[desktop.id] ?? HostObservation() }
    var current: Desktop { store.desktops.first(where: { $0.id == desktop.id }) ?? desktop }
    var key: String { (identity as NSString).expandingTildeInPath }
    var keyPairPresent: Bool { FileManager.default.fileExists(atPath: key) && FileManager.default.fileExists(atPath: key + ".pub") }
    var valid: Bool { address.target != nil && InputValidation.identityPath(key) }
    var detailsSaved: Bool { platform == current.hostPlatform && address.target == current.target && key == (current.identityPath ?? store.defaultIdentity) }
    var accessReady: Bool { detailsSaved && keyPairPresent && observed.ssh == .ready && observed.report?.isStale(at: now) == false }
    var canInstall: Bool {
        valid && accessReady && observed.report?.supported == true && observed.report?.values["service_loaded"] == "loaded" && observed.report?.values["missing_tools"] == "" && !observed.busy && waitingAction == nil
    }
    var recoveryOn: Bool { accessReady && observed.report?.recoveryEnabled == true && waitingAction == nil && !observed.busy }
    var setupStep: Int { address.target == nil ? 1 : (accessReady || waitingAction == "install" ? 3 : 2) }
    var accessMessage: String? {
        guard detailsSaved, let result = observed.ssh else { return nil }
        return result.setupGuidance(previousResult: store.terminalResult(current, action: "setup-access"))
    }
    func progressItem(_ number: Int, _ title: String, _ status: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(number). \(title)").font(.caption.weight(.semibold))
            Text(status).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            .background(setupStep == number && !recoveryOn ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
    }
    var recoveryProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recoveryOn ? "Automatic recovery is enabled" : (waitingAction != nil ? "Step \(setupStep) of 3: Finish the approval in Terminal" : (observed.busy ? "Checking this computer…" : "Step \(setupStep) of 3: " + (setupStep == 1 ? "Find the Linux PC" : (setupStep == 2 ? "Approve or check this Mac’s access" : "Turn on automatic recovery")))))
                .font(.headline)
            HStack(spacing: 8) {
                progressItem(1, "Computer details", address.target == nil ? "Current step" : "Details added")
                progressItem(2, "Approve access", accessReady ? "Verified" : (setupStep == 2 ? "Current step" : "After step 1"))
                progressItem(3, "Automatic recovery", recoveryOn ? "Enabled" : (setupStep == 3 ? "Current step" : "Not verified yet"))
            }
        }
    }
    var linuxRecoveryControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("3. Automatic recovery").font(.headline)
                Spacer()
                if recoveryOn {
                    Label("Enabled", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout.weight(.medium))
                } else {
                    Button("Enable automatic recovery…") { launch("install") }
                        .buttonStyle(ConnectButton()).disabled(!canInstall)
                }
            }
            if recoveryOn {
                Text("The monitor runs on the Linux PC, even when this Mac is closed.").font(.callout).foregroundStyle(.secondary)
            } else if waitingAction == "install" {
                Text("Complete the Linux administrator approval in Terminal. Telynd will check the installation when it finishes.").font(.callout).foregroundStyle(.secondary)
            } else if waitingAction == "disable" || waitingAction == "uninstall" {
                Text("Complete the requested change in Terminal. Telynd will check the recovery state when it finishes.").font(.callout).foregroundStyle(.secondary)
            } else if observed.busy {
                Text("Checking current access and recovery status. Wait for the result before continuing.").font(.callout).foregroundStyle(.secondary)
            } else if !accessReady {
                Text("Unlocks after access is verified in step 2. Installing the Linux helper alone does not turn recovery on.").font(.callout).foregroundStyle(.secondary)
            } else if !canInstall {
                Text(observed.report?.configurationLabel(at: now) ?? "Check access for current installation requirements.").font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Choose Enable automatic recovery and approve installation on Linux in Terminal.").font(.callout).foregroundStyle(.secondary)
            }
        }.padding(12).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }
    var discoveryCommands: String { SSHDiscovery.command }
    func saveDetails() -> Bool {
        var value = current; value.hostPlatform = platform
        if platform.usesSSHRecovery {
            guard let target = address.target, InputValidation.identityPath(key) else { return false }
            value.target = target; value.identityPath = key
        }
        return store.save(value)
    }
    func launch(_ action: String) {
        if saveDetails(), store.terminal(current, action: action) { waitingAction = action }
    }
    func pollCompletion() {
        now = Date()
        guard let action = waitingAction else { return }
        store.refreshOperationNotes()
        guard let result = store.terminalResult(current, action: action), !["awaiting_terminal", "in_progress"].contains(result) else { return }
        waitingAction = nil
        if detailsSaved && valid { store.check(current) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recovery for \(desktop.name)").font(.title2.bold())
            Picker("Remote operating system", selection: $platform) {
                ForEach(HostPlatform.allCases) { item in Text(item.label).tag(item) }
            }.disabled(waitingAction != nil)
            if platform.usesSSHRecovery { recoveryProgress }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if platform == .unknown {
                        Text("Choose this computer’s operating system to see its setup steps. Screen connections work without recovery.").foregroundStyle(.secondary)
                    } else if platform.usesSSHRecovery {
                        linuxSetup
                    } else {
                        Text("Recovery is set up on the remote computer itself. No SSH connection is required for Mac or Windows.").foregroundStyle(.secondary)
                        Text(platform == .macos ? "Mac recovery runs in a signed-in desktop session. Google’s screen and control permissions must be approved on that Mac." : "Windows recovery restarts a crashed service. It leaves an orderly stop alone and needs administrator approval to change the recovery policy.")
                        Text("These host kits are development previews awaiting real-host validation and distribution signing.").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Save operating system") { _ = saveDetails() }
                            Button("Export recovery kit…") { store.exportRecoveryKit(current) }.disabled(platform != current.hostPlatform)
                            Button("Import host report…") { store.importHostReport(current) }.disabled(platform != current.hostPlatform)
                        }
                        Text("Transfer the kit to that computer and follow its README, then import a fresh report after changes.").font(.callout).foregroundStyle(.secondary)
                        StatusDetails(observation: observed, now: now, platform: current.hostPlatform)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if platform.usesSSHRecovery { linuxRecoveryControl }
            Divider()
            HStack {
                Text("Recovery is optional. Connect works independently.").font(.caption).foregroundStyle(.secondary)
                Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 740, height: 660)
            .onAppear {
                platform = current.hostPlatform; address = SSHAddress(target: current.target); identity = store.suggestedIdentity(for: current)
                if !store.fixtureMode && platform.usesSSHRecovery && valid && detailsSaved { store.check(current) }
            }
            .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in pollCompletion() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in pollCompletion() }
            .onChange(of: address) { _ in addressError = nil; if manualConnection { pairedName = nil; pairingKeys = [] } }
    }
    var manualAddressFields: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Connection details").font(.headline)
                    Spacer()
                    Button("Paste SSH address") {
                        if let value = SSHAddress.pasted(NSPasteboard.general.string(forType: .string)) { address = value; addressError = nil }
                        else { addressError = "Copy user@computer or a simple ssh user@computer login command first. SSH options and custom ports are not supported here." }
                    }.font(.caption)
                }
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Linux username").font(.caption.weight(.medium))
                        TextField("For example: alex", text: $address.username).accessibilityLabel("Linux username")
                        Text("Login name only. Leave out @ and the computer name.").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Computer address").font(.caption.weight(.medium))
                        TextField("One IP address or network name", text: $address.host).accessibilityLabel("Computer address")
                        Text("An address this Mac can reach, using your shared network or existing VPN.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if address.username.contains("@") {
                    Text("The first field contains a full SSH address. Enter only the part before @ as the username. You can also copy the full address and choose Paste SSH address to fill both fields.").font(.callout).foregroundStyle(.secondary)
                }
                Text("Or copy one ssh user@address line and choose Paste SSH address. Telynd fills both fields for you.").font(.caption).foregroundStyle(.secondary)
                if let addressError { Text(addressError).font(.caption).foregroundStyle(.red) }
                DisclosureGroup("Where do I find these? What if SSH is not enabled?") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("1. Open a Terminal on the Linux computer, through your working Google remote session or in person. These commands run on Linux, not on this Mac.")
                        Text("2. Copy the Linux details command below, paste it into that Terminal and press Enter. It only reads connection details; it does not enable SSH or change that computer.")
                        Button("Copy Linux details command") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(discoveryCommands, forType: .string) }
                        Text("3. If both devices already use the same Tailscale network, copy the ssh line under SSH via Tailscale. Otherwise choose an address for a network shared with this Mac. Other addresses can include virtual interfaces; ask the computer’s administrator if you are unsure which network is reachable.")
                        Link("Find a Tailscale device’s address", destination: URL(string: "https://tailscale.com/docs/concepts/ip-and-dns-addresses")!)
                        Text("4. Return here and choose Paste SSH address. Copy just one ssh user@address line, without the Terminal prompt or the rest of the output.")
                        DisclosureGroup("View the Linux details command") {
                            Text(discoveryCommands).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding(.top, 8)
                        }
                        Text("SSH must be enabled on Linux. On Ubuntu, look for Secure Shell in System settings. Its displayed SSH login command also works with Paste SSH address. If the setting is missing, use Ubuntu’s OpenSSH Server guide. If password login is disabled and no existing key works, an administrator must authorise this Mac on that computer.")
                        Link("Ubuntu’s OpenSSH setup guide", destination: URL(string: "https://ubuntu.com/server/docs/how-to/security/openssh-server/")!)
                        Text("The SHA256 lines are the computer’s SSH identity fingerprints. Do not paste them into either field. When SSH asks you to trust the computer, compare its fingerprint with the matching key type in the Linux output, or with a trusted record from its administrator.")
                    }.font(.callout).foregroundStyle(.secondary).padding(.top, 10)
                }.font(.callout)
            }
    }
    var linuxSetup: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Once enabled, a monitor on the Linux PC checks Google’s remote desktop service every two minutes. It starts an enabled service if it has stopped, even while this Mac is closed.").font(.callout).foregroundStyle(.secondary)
            if address.target == nil && !manualConnection {
                PairingSetupView(desktop: current) { card, selected in
                    store.resetRecoveryCheck(current.id)
                    address = SSHAddress(target: card.username + "@" + selected)
                    pairedName = card.hostname; pairingKeys = card.hostKeys
                }
            }
            if address.target != nil {
                DisclosureGroup("Computer details · " + (pairedName ?? current.name)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("These details identify the recovery connection. Access is verified separately in step 2.").font(.callout).foregroundStyle(.secondary)
                        if !pairingKeys.isEmpty {
                            Text("Compare the matching identity if Terminal asks you to trust this PC.").font(.caption).foregroundStyle(.secondary)
                            ForEach(pairingKeys, id: \.type) { key in Text(key.type + " · " + key.fingerprint).font(.caption).textSelection(.enabled) }
                        }
                        Button("Set up the recovery connection again") { address = SSHAddress(); pairedName = nil; pairingKeys = []; manualConnection = false }
                    }.padding(.top, 10)
                }.font(.callout)
            }
            DisclosureGroup("Advanced: enter connection details", isExpanded: $manualConnection) { manualAddressFields.padding(.top, 10) }.font(.callout)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("2. Approve access from this Mac").font(.headline)
                if address.target == nil {
                    Text("Add this PC’s connection details in step 1. Then approve access here.").font(.callout).foregroundStyle(.secondary)
                } else if waitingAction != nil {
                    ProgressView("Continue in Terminal. Telynd checks access when approval finishes.").controlSize(.small)
                } else if observed.busy {
                    ProgressView("Checking this Mac’s access…").controlSize(.small)
                } else if accessReady {
                    Label("Access verified", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(recoveryOn ? "This Mac can manage recovery. The monitor’s status is shown below." : "This Mac can manage recovery. Turn on automatic recovery below.").font(.callout).foregroundStyle(.secondary)
                } else if detailsSaved && keyPairPresent && observed.ssh == .ready {
                    Text("The previous check has expired. Check access again to continue.").font(.callout).foregroundStyle(.secondary)
                    Button("Check access again") { store.check(current) }.buttonStyle(ConnectButton())
                } else {
                    Text("Give this Mac permission to manage recovery on the Linux PC. This one-time approval opens Terminal; enter the Linux account password when asked.").font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("Approve this Mac…") { launch("setup-access") }.buttonStyle(ConnectButton())
                            .disabled(!valid || observed.busy || waitingAction != nil || (detailsSaved && observed.ssh == .identityChanged))
                        Button("Check access") { if saveDetails() { store.check(current) } }.disabled(!valid || observed.busy || waitingAction != nil)
                    }
                    if let accessMessage { Text(accessMessage).font(.callout).foregroundStyle(.secondary) }
                    if detailsSaved && observed.ssh == .ready && !keyPairPresent { Text("Access works with your current SSH configuration. Telynd needs a complete key pair for setup; approve this Mac or choose an existing pair in Advanced.").font(.caption).foregroundStyle(.secondary) }
                    DisclosureGroup("What happens in Terminal?") {
                        Text("Telynd creates a key if needed and adds its public key to your Linux account. Existing files are never overwritten. Terminal may ask you to choose a key passphrase and confirm the PC’s identity; its fingerprints are in Computer details after pairing. Login passwords and passphrases stay in system prompts. This approval does not install the recovery monitor.").font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                    }.font(.callout)
                }
            }
            DisclosureGroup("Advanced settings & diagnostics") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        TextField("SSH private key path", text: $identity)
                        Button("Choose key…") { let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.showsHiddenFiles = true; if panel.runModal() == .OK, let url = panel.url { identity = url.path } }
                    }
                    Button("Start SSH") { if saveDetails() { store.startSSH(current) } }.disabled(!valid || waitingAction != nil)
                    if detailsSaved {
                        StatusDetails(observation: observed, now: now, platform: current.hostPlatform)
                        if let note = store.operationNotes[desktop.id] { Text("Last setup result: " + note).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    } else { Text("Check access to verify the edited settings.").font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        Button("Recheck") { if saveDetails() { store.check(current) } }.disabled(!valid || observed.busy || waitingAction != nil)
                        Button("Recover if stopped") { store.check(current, recover: true) }.disabled(!accessReady || observed.report?.recoveryEnabled != true || observed.busy || waitingAction != nil)
                    }
                    HStack {
                        Button("Disable timer…") { launch("disable") }
                        Button("Uninstall recovery…") { launch("uninstall") }
                    }.disabled(!valid || !detailsSaved || observed.busy || waitingAction != nil)
                }.padding(.top, 12)
            }.font(.callout)
        }
    }
}

@main struct TelyndApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(store).preferredColorScheme(store.fixtureAppearance) }.windowStyle(.hiddenTitleBar).defaultSize(width: 860, height: 520)
            .commands { CommandGroup(after: .appInfo) { Button("Setup guide") { store.showGuide = true } } }
    }
}
