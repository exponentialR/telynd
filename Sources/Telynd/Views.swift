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
                    Text("Connections open in Chrome using each computer’s saved account.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth: 960, alignment: .leading).frame(maxWidth: .infinity)
            }
        }.frame(minWidth: 720, minHeight: 420)
            .background(Color(nsColor: .windowBackgroundColor))
            .tint(Color(red: 18 / 255, green: 92 / 255, blue: 1))
            .sheet(item: $editing) { DesktopEditor(desktop: $0) }
            .sheet(isPresented: $store.showGuide) { OnboardingGuide() }
            .sheet(item: $store.recoveryDesktop) { RecoverySheet(desktop: $0) }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.refreshProfiles(); store.refreshOperationNotes() }
            .alert("Telynd", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
}
struct DesktopRow: View {
    @EnvironmentObject var store: AppStore
    let desktop: Desktop
    let edit: () -> Void
    @State private var now = Date()
    @State private var detailsExpanded = false
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
                Button { if desktop.hasDirectConnection && store.profileReady(for: desktop) { store.connect(desktop) } else { edit() } } label: {
                    Text(action).frame(minWidth: 64)
                }.buttonStyle(ConnectButton()).disabled(store.writeLocked)
                    .accessibilityLabel("\(action) \(desktop.name)")
                Menu {
                    Button("Edit computer…", action: edit).disabled(store.writeLocked)
                    Button(detailsExpanded ? "Hide details" : "Details & recovery") { detailsExpanded.toggle() }
                    Divider()
                    Button("Recovery settings…") { store.recoveryDesktop = desktop }.disabled(store.writeLocked)
                } label: { Image(systemName: "ellipsis").frame(width: 18, height: 24) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Options for \(desktop.name)")
            }
            if detailsExpanded {
                Divider()
                HStack { Text(title).font(.callout.weight(.medium)); Spacer(); Button("Hide details") { detailsExpanded = false }.buttonStyle(.link) }
                StatusDetails(observation: observed, now: now, platform: desktop.hostPlatform)
                if let launched = desktop.lastLaunch { Text("Last opened: \(launched.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                if let note = store.operationNotes[desktop.id] { Text(note).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
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
    @State private var sshVisible: Bool
    @State private var recoveryExpanded = false
    init(desktop: Desktop) { _desktop = State(initialValue: desktop); _sshVisible = State(initialValue: desktop.target != nil) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Computer details").font(.title2.bold())
            ScrollView { VStack(alignment: .leading, spacing: 20) {
            ComputerFields(desktop: $desktop)
            Divider()
            DisclosureGroup("Optional recovery", isExpanded: $recoveryExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Operating system", selection: $desktop.hostPlatform) {
                        ForEach(HostPlatform.allCases) { platform in Text(platform.label).tag(platform) }
                    }
                    Toggle("Configure SSH address", isOn: $sshVisible)
                    if sshVisible {
                        TextField("SSH address: user@hostname", text: Binding(get: { desktop.target ?? "" }, set: { desktop.target = $0.isEmpty ? nil : $0 }))
                    }
                    Text("Linux recovery uses SSH. Mac and Windows use host-local setup. Connection does not require recovery.").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 12)
            }
            }.frame(maxWidth: .infinity, alignment: .leading) }
            Divider()
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Save") { if !sshVisible { desktop.target = nil }; if store.save(desktop) { dismiss() } }.keyboardShortcut(.defaultAction).disabled(!desktop.valid || !desktop.hasDirectConnection || !store.profileReady(for: desktop) || store.writeLocked) }
        }.padding(28).frame(width: 640, height: 560)
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
    @State private var manualEntryExpanded = false
    @State private var captureRequests = ChromeCaptureRequests()
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connection link").font(.subheadline.weight(.medium))
            HStack {
                Button("Choose computer in Chrome") { captureRequests.invalidate(); store.openChrome(desktop, picker: true) }.disabled(!store.profileReady(for: desktop))
                Button("Use open computer") {
                    pasteError = nil
                    let request = captureRequests.begin(for: desktop)
                    store.captureChromeConnection { result in
                        guard captureRequests.consume(request, current: desktop) else { return }
                        switch result {
                        case .success(let link): desktop.chromeURL = link
                        case .failure(let error): pasteError = error.localizedDescription
                        }
                    }
                }.disabled(store.readingChromeConnection || !store.profileReady(for: desktop))
            }
            if store.readingChromeConnection { ProgressView("Reading Chrome’s open computer…").controlSize(.small) }
            if let pasteError { Text(pasteError).font(.caption).foregroundStyle(.red) }
            else if desktop.hasDirectConnection && store.profileReady(for: desktop) {
                Text("Connect opens this computer using \(desktop.chromeProfile?.email ?? "its saved browser account").").font(.caption).foregroundStyle(.secondary)
            } else if desktop.hasDirectConnection {
                Text("Choose this computer’s browser account to enable Connect.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Open your computer in Chrome, then choose Use open computer. macOS will ask permission for Telynd to read Chrome’s current tab address.").font(.callout).foregroundStyle(.secondary)
                Link("Chrome Remote Desktop setup", destination: URL(string: "https://support.google.com/chrome/answer/1649523")!).font(.caption)
            }
            DisclosureGroup("Enter link manually", isExpanded: $manualEntryExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("https://remotedesktop.google.com/access/session/…", text: Binding(
                        get: { desktop.chromeURL == InputValidation.devicePicker || desktop.chromeURL == InputValidation.devicePicker + "/" ? "" : desktop.chromeURL },
                        set: { captureRequests.invalidate(); desktop.chromeURL = $0.isEmpty ? InputValidation.devicePicker : $0; pasteError = nil }
                    )).accessibilityLabel("Individual computer connection link")
                    Button("Paste link") {
                        captureRequests.invalidate()
                        guard let value = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), InputValidation.directChromeURL(value) else {
                            pasteError = "Copy the address after opening your computer in Chrome Remote Desktop."; return
                        }
                        desktop.chromeURL = value; pasteError = nil
                    }
                    if !InputValidation.chromeURL(desktop.chromeURL) { Text("This is not an individual Google Remote Desktop link.").font(.caption).foregroundStyle(.red) }
                }.padding(.top, 10)
            }.font(.callout)
        }.onChange(of: desktop) { _ in captureRequests.invalidate() }
            .onDisappear { captureRequests.invalidate() }
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
                    Text("Recovery setup depends on the remote computer. Linux uses SSH and a host timer. Mac uses a host-local desktop agent. Windows uses native crash recovery. Each setup explains its permissions and limits.")
                    Text("Recovery cannot fix a sleeping PC, network failure or expired Google authorisation. You can finish now and add recovery from the computer’s card later.").foregroundStyle(.secondary)
                    Button("Set up optional recovery") { finish(recovery: true) }.disabled(chosen == nil)
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
                case .recovery: Button("Finish with connection-only access") { finish() }.buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction)
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
    @State private var target = ""
    @State private var identity = ""
    @State private var now = Date()
    var observed: HostObservation { store.observations[desktop.id] ?? HostObservation() }
    var current: Desktop { store.desktops.first(where: { $0.id == desktop.id }) ?? desktop }
    func saveDetails() -> Bool {
        var value = current; value.hostPlatform = platform
        if !platform.usesSSHRecovery { return store.save(value) }
        value.target = target.isEmpty ? nil : target
        value.identityPath = (identity as NSString).expandingTildeInPath
        return store.save(value)
    }
    var detailsSaved: Bool { platform == current.hostPlatform && target == current.target && (identity as NSString).expandingTildeInPath == (current.identityPath ?? store.defaultIdentity) }
    var valid: Bool { InputValidation.target(target) && InputValidation.identityPath((identity as NSString).expandingTildeInPath) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Recovery for \(desktop.name)").font(.title2.bold())
            Picker("Remote operating system", selection: $platform) {
                ForEach(HostPlatform.allCases) { item in Text(item.label).tag(item) }
            }
            if !platform.usesSSHRecovery {
                Text("Recovery is set up locally on the remote computer. Export its kit, transfer it to that computer and follow the README. No inbound SSH is required. These host kits are development previews awaiting real-host validation and distribution signing.").font(.callout).foregroundStyle(.secondary)
                Text(platform == .macos ? "Mac: recovery runs only in a signed-in desktop session, with bounded start attempts. Grant Google’s screen/control permissions on that Mac when required." : "Windows: native crash recovery with bounded restart attempts. An orderly stop is not automatically recovered. Administrator approval is needed to change or restore the service’s recovery policy.").font(.callout)
                HStack {
                    Button("Save operating system") { _ = saveDetails() }
                    Button("Export recovery kit…") { store.exportRecoveryKit(current) }.disabled(platform != current.hostPlatform)
                    Button("Import host report…") { store.importHostReport(current) }.disabled(platform != current.hostPlatform)
                }
                Text("Follow the kit’s README to check, enable or remove recovery on the remote computer. Import a fresh report after changes.").font(.caption).foregroundStyle(.secondary)
                StatusDetails(observation: observed, now: now, platform: current.hostPlatform)
                if let note = store.operationNotes[desktop.id] { Text(note).font(.callout).foregroundStyle(.secondary) }
            } else {
            Text("Optional recovery supports Linux with systemd and an existing per-account Chrome host service. Other computers can remain connection-only. An existing reachable SSH route is needed; Tailscale is optional.").font(.callout).foregroundStyle(.secondary)
            TextField("SSH account and host, for example researcher@workstation.example", text: $target)
            HStack { TextField("Private key path", text: $identity); Button("Choose key…") { let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.showsHiddenFiles = true; if panel.runModal() == .OK, let url = panel.url { identity = url.path } } }
            HStack {
                Button("Save and check readiness") { if saveDetails() { store.check(current) } }.disabled(!valid || observed.busy)
                Button("SSH Terminal") { if saveDetails() { store.terminal(current, action: "connect") } }.disabled(!valid)
            }
            StatusDetails(observation: observed, now: now, platform: current.hostPlatform)
            if let note = store.operationNotes[desktop.id] { Text(note).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            Divider()
            Text("Each action explains its scope before opening Terminal. Enter login and administrator passwords directly there. No password is saved by Telynd.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Create a new SSH key…") { if saveDetails() { store.terminal(current, action: "generate-key") } }.disabled(!valid || FileManager.default.fileExists(atPath: (identity as NSString).expandingTildeInPath))
                Button("Authorise SSH access…") { if saveDetails() { store.terminal(current, action: "authorise") } }.disabled(!valid)
                Button("Install recovery…") { if saveDetails() { store.terminal(current, action: "install") } }.disabled(!valid || !detailsSaved || observed.report?.supported != true || observed.report?.values["service_loaded"] != "loaded" || observed.report?.values["missing_tools"] != "" || observed.report?.isStale(at: now) == true || observed.busy)
            }
            HStack {
                Button("Recover if stopped") { store.check(current, recover: true) }.disabled(!detailsSaved || observed.report?.recoveryEnabled != true || observed.report?.isStale(at: now) == true || observed.busy)
                Spacer()
                Button("Disable timer…") { store.terminal(current, action: "disable") }.disabled(!valid || !detailsSaved || current.target == nil || observed.busy)
                Button("Uninstall recovery…") { store.terminal(current, action: "uninstall") }.disabled(!valid || !detailsSaved || current.target == nil || observed.busy)
            }
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 800)
            .onAppear { platform = current.hostPlatform; target = current.target ?? ""; identity = current.identityPath ?? store.defaultIdentity }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
    }
}

@main struct TelyndApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(store).preferredColorScheme(store.fixtureAppearance) }.windowStyle(.hiddenTitleBar).defaultSize(width: 860, height: 520)
            .commands { CommandGroup(after: .appInfo) { Button("Setup guide") { store.showGuide = true } } }
    }
}
