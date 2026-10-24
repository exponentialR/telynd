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
struct Wordmark: View {
    @Environment(\.colorScheme) var scheme
    var compact = false
    var body: some View {
        if let url = Bundle.main.url(forResource: scheme == .dark ? "telynd-logo-dark" : "telynd-logo-v2", withExtension: "png"), let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: compact ? 155 : 230, height: compact ? 48 : 72, alignment: .leading).accessibilityLabel("Telynd")
        } else { Text("Telynd").font(.largeTitle.bold()) }
    }
}
struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @State private var editing: Desktop?
    @State private var choosingProfile = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Wordmark(compact: true)
                        if store.fixtureMode { Text("Preview · synthetic profiles; network actions disabled").font(.caption) }
                    }
                    Spacer()
                    Button { choosingProfile = true } label: {
                        Label(store.preferences.chromeProfileEmail.isEmpty ? "Choose Chrome profile" : store.preferences.chromeProfileEmail, systemImage: "person.crop.circle")
                            .lineLimit(1).truncationMode(.middle)
                    }.buttonStyle(.borderless).help("Choose the Chrome profile used for connections")
                }
                if store.writeLocked {
                    Label("Settings need attention. Your saved files have been preserved; correct them and reopen Telynd before saving.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                if !store.preferences.guideCompleted && !store.showGuide {
                    HStack { Text("Your completed setup steps are saved."); Spacer(); Button("Continue setup") { store.showGuide = true } }.padding(16).background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                if store.desktops.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "desktopcomputer").font(.system(size: 42)).foregroundStyle(.secondary)
                        Text("Connect your first computer").font(.title2.bold())
                        Text("Choose Chrome, save a computer and open its remote desktop. SSH is optional.").foregroundStyle(.secondary)
                        Button("Get started") { store.showGuide = true }.buttonStyle(PrimaryButton()).disabled(store.writeLocked)
                    }.frame(maxWidth: .infinity).padding(38)
                }
                HStack {
                    Text("Computers").font(.title2.weight(.semibold))
                    Spacer()
                    Button { editing = Desktop(name: "") } label: { Label("Add computer", systemImage: "plus") }.disabled(store.writeLocked)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 290, maximum: 430), alignment: .top)], alignment: .leading, spacing: 18) {
                    ForEach(store.desktops) { item in DesktopCard(desktop: item) { editing = item } }
                }
                HStack {
                    Text("Connections open in Chrome. Recovery is optional.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Setup guide") { store.refreshProfiles(); store.showGuide = true }.buttonStyle(.link).disabled(store.writeLocked)
                }.font(.caption)
            }.padding(24).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minWidth: 680, minHeight: 440)
            .background(Color(nsColor: .windowBackgroundColor))
            .tint(Color(red: 18 / 255, green: 92 / 255, blue: 1))
            .sheet(item: $editing) { DesktopEditor(desktop: $0) }
            .sheet(isPresented: $choosingProfile) { ProfileSheet() }
            .sheet(isPresented: $store.showGuide) { OnboardingGuide() }
            .sheet(item: $store.recoveryDesktop) { RecoverySheet(desktop: $0) }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.refreshOperationNotes() }
            .alert("Telynd", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
}
struct DesktopCard: View {
    @EnvironmentObject var store: AppStore
    let desktop: Desktop
    let edit: () -> Void
    @State private var now = Date()
    @State private var detailsExpanded = false
    var observed: HostObservation { store.observations[desktop.id] ?? HostObservation() }
    var title: String {
        if observed.busy { return "Checking recovery…" }
        if !desktop.hasDirectConnection { return "Connection link needed" }
        if let report = observed.report { return report.isStale(at: now) ? "Recovery status needs a refresh" : report.configurationLabel(at: now) }
        if desktop.target == nil || !desktop.hostPlatform.usesSSHRecovery { return "Connection only" }
        return observed.ssh == nil ? "Recovery not checked" : "Recovery needs attention"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Image(systemName: desktop.symbol).font(.system(size: 21)).foregroundStyle(.blue).frame(width: 42, height: 42).background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 5) {
                    Text(desktop.name).font(.headline)
                    Text(desktop.hostPlatform == .unknown ? title : "\(desktop.hostPlatform.label) · \(title)").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(action: edit) { Image(systemName: "pencil") }.buttonStyle(.borderless).accessibilityLabel("Edit \(desktop.name)").help("Computer details")
            }
            Button { if desktop.hasDirectConnection { store.connect(desktop) } else { edit() } } label: {
                Label(desktop.hasDirectConnection ? "Connect" : "Set connection link", systemImage: desktop.hasDirectConnection ? "arrow.up.right" : "link")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(PrimaryButton()).disabled(store.writeLocked)
            DisclosureGroup("Details & recovery", isExpanded: $detailsExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    StatusDetails(observation: observed, now: now, platform: desktop.hostPlatform)
                    if let launched = desktop.lastLaunch { Text("Last opened: \(launched.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                    if let note = store.operationNotes[desktop.id] { Text(note).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    Divider()
                    HStack {
                        Button("Recovery settings…") { store.recoveryDesktop = desktop }
                        Spacer()
                        if !desktop.hostPlatform.usesSSHRecovery { Button("Import report") { store.importHostReport(desktop) } }
                        else if desktop.target != nil { Button("Recheck") { store.check(desktop) }.disabled(observed.busy) }
                    }.buttonStyle(.link)
                }.padding(.top, 10)
            }.font(.callout)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.08)))
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
struct ProfilePicker: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Select an existing signed-in Chrome profile. This profile is used for all saved computers; selecting it does not sign Telynd into Google.").foregroundStyle(.secondary)
            Picker("Chrome profile", selection: Binding(get: { store.preferences.chromeProfileDirectory ?? "" }, set: { store.chooseProfile($0) })) {
                Text("Choose a profile").tag("")
                ForEach(store.profiles) { profile in Text(profile.label).tag(profile.directory).disabled(!profile.signedIn) }
            }
            if let problem = store.profileProblem { Label(problem, systemImage: "info.circle").foregroundStyle(.secondary) }
            if !store.preferences.chromeProfileEmail.isEmpty && !store.profileReady { Text("The saved profile is unavailable. Select its current signed-in profile to continue.").foregroundStyle(.orange) }
            HStack { Button("Refresh profiles") { store.refreshProfiles() }; Button("Open Chrome to sign in") { store.openChromeForSignIn() } }
        }.onAppear { store.refreshProfiles() }
    }
}
struct ProfileSheet: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) { Text("Chrome profile").font(.title2.bold()); ProfilePicker(); HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) } }.padding(28).frame(width: 620)
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
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Save") { if !sshVisible { desktop.target = nil }; if store.save(desktop) { dismiss() } }.keyboardShortcut(.defaultAction).disabled(!desktop.valid || !desktop.hasDirectConnection) }
        }.padding(28).frame(width: 640)
    }
}
struct ComputerFields: View {
    @Binding var desktop: Desktop
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Name").font(.subheadline.weight(.medium))
            TextField("Computer name, for example Home PC", text: $desktop.name)
            ConnectionLinkFields(desktop: $desktop)
        }
    }
}
struct ConnectionLinkFields: View {
    @EnvironmentObject var store: AppStore
    @Binding var desktop: Desktop
    @State private var pasteError: String?
    @State private var manualEntryExpanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connection link").font(.subheadline.weight(.medium))
            HStack {
                Button("Choose computer in Chrome") { store.openChrome() }.disabled(!store.profileReady)
                Button("Use open computer") {
                    pasteError = nil
                    store.captureChromeConnection { result in
                        switch result {
                        case .success(let link): desktop.chromeURL = link
                        case .failure(let error): pasteError = error.localizedDescription
                        }
                    }
                }.disabled(store.readingChromeConnection)
            }
            if store.readingChromeConnection { ProgressView("Reading Chrome’s open computer…").controlSize(.small) }
            if let pasteError { Text(pasteError).font(.caption).foregroundStyle(.red) }
            else if desktop.hasDirectConnection {
                Text("Connect opens this computer directly in Chrome.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Open your computer in Chrome, then choose Use open computer. macOS will ask permission for Telynd to read Chrome’s current tab address.").font(.callout).foregroundStyle(.secondary)
                Link("Chrome Remote Desktop setup", destination: URL(string: "https://support.google.com/chrome/answer/1649523")!).font(.caption)
            }
            DisclosureGroup("Enter link manually", isExpanded: $manualEntryExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("https://remotedesktop.google.com/access/session/…", text: Binding(
                        get: { desktop.chromeURL == InputValidation.devicePicker || desktop.chromeURL == InputValidation.devicePicker + "/" ? "" : desktop.chromeURL },
                        set: { desktop.chromeURL = $0.isEmpty ? InputValidation.devicePicker : $0; pasteError = nil }
                    )).accessibilityLabel("Individual computer connection link")
                    Button("Paste link") {
                        guard let value = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), InputValidation.directChromeURL(value) else {
                            pasteError = "Copy the address after opening your computer in Chrome Remote Desktop."; return
                        }
                        desktop.chromeURL = value; pasteError = nil
                    }
                    if !InputValidation.chromeURL(desktop.chromeURL) { Text("This is not an individual Google Remote Desktop link.").font(.caption).foregroundStyle(.red) }
                }.padding(.top, 10)
            }.font(.callout)
        }
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
        return store.save(value)
    }
    func finish(recovery: Bool = false) {
        if store.updatePreferences({ $0.guideStep = .finished; $0.guideCompleted = true; $0.guideDraft = nil }) {
            store.showGuide = false
            if recovery, let desktop = chosen { DispatchQueue.main.async { store.recoveryDesktop = desktop } }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack { Wordmark(); Spacer(); Text("Step \(min(step.rawValue + 1, 5)) of 5").font(.callout).foregroundStyle(.secondary) }
            Text(step.title).font(.title2.bold())
            if store.fixtureMode { Text("Preview · synthetic profiles; Chrome launch is simulated").font(.caption).foregroundStyle(.secondary) }
            Group {
                switch step {
                case .welcome:
                    Text("Telynd keeps your remote computers in one place. Google Chrome Remote Desktop provides the screen connection and handles its sign-in and PIN.")
                    Text("First, choose Chrome and save a computer. Optional recovery can be configured afterwards for your remote computer’s operating system. You do not need SSH or administrator access to make your first connection.").foregroundStyle(.secondary)
                case .profile: ProfilePicker()
                case .computer: ComputerFields(desktop: $draft)
                case .connect:
                    if let desktop = chosen {
                        if desktop.hasDirectConnection {
                            Text("Connect to \(desktop.name) in your selected Chrome profile.")
                            Button("Connect") { store.connect(desktop) }.buttonStyle(PrimaryButton())
                            Text("Opening Chrome does not confirm a remote session. You can continue after launching, or record that you connected successfully yourself.").font(.callout).foregroundStyle(.secondary)
                            if desktop.lastLaunch != nil { Text("Chrome launch recorded.").font(.callout) }
                            Button("I connected successfully") { var value = desktop; value.userConfirmedConnection = Date(); if store.save(value) { advance(.recovery) } }
                        } else {
                            ConnectionLinkFields(desktop: $draft)
                            Button("Save connection link") { _ = saveDraft() }.disabled(!draft.valid || !draft.hasDirectConnection)
                        }
                    } else { Text("No computer is saved for this guide. Go back to add one.") }
                case .recovery:
                    Text("Recovery setup depends on the remote computer. Linux uses SSH and a host timer. Mac uses a host-local desktop agent. Windows uses native crash recovery. Each setup explains its permissions and limits.")
                    Text("Recovery cannot fix a sleeping PC, network failure or expired Google authorisation. You can finish now and add recovery from the computer’s card later.").foregroundStyle(.secondary)
                    Button("Set up optional recovery") { finish(recovery: true) }.disabled(chosen == nil)
                case .finished:
                    Text("Your computers and Chrome profile are saved. Open a card to connect, or use Recovery settings when you want to configure recovery for that computer.")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 12)
            Divider()
            HStack {
                Button("Save progress and close") { store.showGuide = false }.keyboardShortcut(.cancelAction)
                Spacer()
                if step != .welcome && step != .finished { Button("Back") { advance(GuideStep(rawValue: step.rawValue - 1) ?? .welcome) } }
                switch step {
                case .welcome: Button("Get started") { advance(.profile) }.buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction)
                case .profile: Button("Continue") { advance(.computer) }.buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction).disabled(!store.profileReady)
                case .computer: Button("Save and continue") { if saveDraft(), store.updatePreferences({ $0.guideDesktopID = draft.id }) { advance(.connect) } }.buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction).disabled(!draft.valid || !draft.hasDirectConnection)
                case .connect: Button("Continue after opening Chrome") { advance(.recovery) }.keyboardShortcut(.defaultAction).disabled(chosen?.lastLaunch == nil || chosen?.hasDirectConnection != true)
                case .recovery: Button("Finish with connection-only access") { finish() }.buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction)
                case .finished: Button("Done") { store.showGuide = false }.buttonStyle(PrimaryButton())
                }
            }
        }.padding(30).frame(width: 730, height: 560)
            .onAppear { draft = step == .connect ? (chosen ?? draft) : (store.preferences.guideDraft ?? chosen ?? draft) }
            .onChange(of: draft) { value in if step == .computer { _ = store.updatePreferences { $0.guideDraft = value } } }
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
        WindowGroup { ContentView().environmentObject(store).preferredColorScheme(store.fixtureAppearance) }.windowStyle(.hiddenTitleBar).defaultSize(width: 900, height: 560)
            .commands { CommandGroup(after: .appInfo) { Button("Setup guide") { store.showGuide = true } } }
    }
}
