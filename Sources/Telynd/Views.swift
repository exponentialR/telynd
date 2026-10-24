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
    var body: some View {
        if let url = Bundle.main.url(forResource: scheme == .dark ? "telynd-logo-dark" : "telynd-logo-v2", withExtension: "png"), let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: 230, height: 72, alignment: .leading).accessibilityLabel("Telynd")
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
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Wordmark()
                        if store.fixtureMode { Text("Preview · synthetic profiles; network actions disabled").font(.caption) }
                        Text("Your computers. One place to connect and recover.").font(.title3).foregroundStyle(.secondary)
                        Button { choosingProfile = true } label: {
                            Label(store.preferences.chromeProfileEmail.isEmpty ? "Choose Chrome profile" : store.preferences.chromeProfileEmail, systemImage: "person.crop.circle")
                        }.buttonStyle(.link)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 12) {
                        Button { editing = Desktop(name: "") } label: { Label("Add computer", systemImage: "plus") }.controlSize(.large).disabled(store.writeLocked)
                        Button("Setup guide") { store.refreshProfiles(); store.showGuide = true }.buttonStyle(.link).disabled(store.writeLocked)
                    }
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 350), alignment: .top)], alignment: .leading, spacing: 22) {
                    ForEach(store.desktops) { item in DesktopCard(desktop: item) { editing = item } }
                }
                VStack(alignment: .leading, spacing: 9) {
                    Label("Connect first. Recovery is optional.", systemImage: "arrow.triangle.2.circlepath").font(.headline)
                    Text("Google Chrome Remote Desktop provides the screen connection and handles sign-in and its PIN. Telynd can also recover an enabled Linux Chrome host service if it stops or fails.")
                    Text("A running service does not prove Google can connect. A sleeping PC, network fault or expired Google authorisation may need separate attention.")
                }.font(.callout).foregroundStyle(.secondary).padding(22).frame(maxWidth: .infinity, alignment: .leading).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
            }.padding(30)
        }.frame(minWidth: 850, minHeight: 650)
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
    var observed: HostObservation { store.observations[desktop.id] ?? HostObservation() }
    var title: String {
        if desktop.target == nil { return "Connection only" }
        if let report = observed.report { return report.configurationLabel(at: now) }
        return observed.ssh == nil ? "Recovery verification unknown" : "Setup needs attention"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top) {
                Image(systemName: desktop.symbol).font(.system(size: 25)).foregroundStyle(.blue).frame(width: 50, height: 50).background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 5) {
                    Text(desktop.name).font(.title2.weight(.semibold))
                    Text(title).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: edit) { Image(systemName: "slider.horizontal.3") }.buttonStyle(.borderless).accessibilityLabel("Edit \(desktop.name)")
            }
            if desktop.target != nil { StatusDetails(observation: observed, now: now) }
            else { Text("Open your saved Google link. You can add optional Linux recovery later.").font(.callout).foregroundStyle(.secondary).frame(minHeight: 42, alignment: .top) }
            Button { store.connect(desktop) } label: { Label("Open remote desktop", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButton())
            if let launched = desktop.lastLaunch { Text("Last opened in Chrome: \(launched.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
            if let note = store.operationNotes[desktop.id] { Text(note).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            Divider()
            HStack {
                Button(desktop.target == nil ? "Set up recovery…" : "Recovery settings…") { store.recoveryDesktop = desktop }
                Spacer()
                if desktop.target != nil { Button("Recheck") { store.check(desktop) }.disabled(observed.busy) }
            }.buttonStyle(.link)
        }.padding(23).frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.primary.opacity(0.08)))
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
    }
}
struct StatusDetails: View {
    let observation: HostObservation
    var now = Date()
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if observation.busy { ProgressView("Checking readiness…").controlSize(.small) }
            else {
                Text("SSH: \(observation.ssh == .ready ? "access verified" : "not verified")")
                Text("Chrome service: \(observation.report?.serviceLabel ?? "unknown")")
                Text("Recovery timer: \(observation.report?.values["timer"] ?? "unknown")")
                Text("Google connection: not verified by Telynd")
                if let date = observation.checkedAt { Text("Checked \(date.formatted(date: .omitted, time: .shortened))\(now.timeIntervalSince(date) > 300 ? " · stale — recheck" : "")") }
                if let report = observation.report {
                    if report.values["service_loaded"] == "not-found" { Text("Set up the Linux Chrome host for this account using Google’s guide, then recheck.") }
                    if let missing = report.values["missing_tools"], !missing.isEmpty { Text("Ask the host administrator to provide: \(missing). Recheck afterwards.") }
                    if !report.supported { Text("Keep connection-only access; recovery needs Linux with systemd.") }
                }
                Text(observation.note)
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
    init(desktop: Desktop) { _desktop = State(initialValue: desktop); _sshVisible = State(initialValue: desktop.target != nil) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Computer details").font(.title2.bold())
            ComputerFields(desktop: $desktop)
            Toggle("Configure SSH address (optional)", isOn: $sshVisible)
            if sshVisible {
                TextField("SSH address: user@hostname", text: Binding(get: { desktop.target ?? "" }, set: { desktop.target = $0.isEmpty ? nil : $0 }))
                Text("SSH is used for command-line access and Linux recovery. It is not needed to open a remote desktop.").font(.callout).foregroundStyle(.secondary)
            }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Save") { if !sshVisible { desktop.target = nil }; if store.save(desktop) { dismiss() } }.keyboardShortcut(.defaultAction).disabled(!desktop.valid) }
        }.padding(28).frame(width: 640)
    }
}
struct ComputerFields: View {
    @EnvironmentObject var store: AppStore
    @Binding var desktop: Desktop
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            TextField("Computer name, for example Home PC", text: $desktop.name)
            TextField("Chrome Remote Desktop link", text: $desktop.chromeURL)
            Text("The default link opens Google’s device picker. For a direct link, open the computer in Chrome Remote Desktop, copy its /access/session/… address, and paste it here.").font(.callout).foregroundStyle(.secondary)
            Button("Open Google’s device picker") { store.openChrome() }.disabled(!store.profileReady)
            Link("Need to set up Chrome Remote Desktop first?", destination: URL(string: "https://support.google.com/chrome/answer/1649523")!)
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
                    Text("First, choose Chrome and save a computer. Optional Linux recovery can be configured afterwards. You do not need SSH or administrator access to make your first connection.").foregroundStyle(.secondary)
                case .profile: ProfilePicker()
                case .computer: ComputerFields(desktop: $draft)
                case .connect:
                    if let desktop = chosen {
                        Text("Open \(desktop.name) in your selected Chrome profile. Choose the computer in Google if you saved the device-picker link.")
                        Button("Open remote desktop") { store.connect(desktop) }.buttonStyle(PrimaryButton())
                        Text("Opening Chrome does not confirm a remote session. You can continue after launching, or record that you connected successfully yourself.").font(.callout).foregroundStyle(.secondary)
                        if desktop.lastLaunch != nil { Text("Chrome launch recorded.").font(.callout) }
                        Button("I connected successfully") { var value = desktop; value.userConfirmedConnection = Date(); if store.save(value) { advance(.recovery) } }
                    } else { Text("No computer is saved for this guide. Go back to add one.") }
                case .recovery:
                    Text("On supported Linux computers, Telynd can start the Chrome host service if it stops or fails. This needs a separate SSH authorisation and one-time administrator approval.")
                    Text("Recovery cannot fix a sleeping PC, network failure or expired Google authorisation. You can finish now and add recovery from the computer’s card later.").foregroundStyle(.secondary)
                    Button("Set up optional recovery") { finish(recovery: true) }.disabled(chosen == nil)
                case .finished:
                    Text("Your computers and Chrome profile are saved. Open a card to connect, or use Recovery settings when you want to configure Linux recovery.")
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
                case .computer: Button("Save and continue") { if saveDraft(), store.updatePreferences({ $0.guideDesktopID = draft.id }) { advance(.connect) } }.buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction).disabled(!draft.valid)
                case .connect: Button("Continue after opening Chrome") { advance(.recovery) }.keyboardShortcut(.defaultAction).disabled(chosen?.lastLaunch == nil)
                case .recovery: Button("Finish with connection-only access") { finish() }.buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction)
                case .finished: Button("Done") { store.showGuide = false }.buttonStyle(PrimaryButton())
                }
            }
        }.padding(30).frame(width: 730, height: 560)
            .onAppear { draft = store.preferences.guideDraft ?? chosen ?? draft }
            .onChange(of: draft) { value in if step == .computer { _ = store.updatePreferences { $0.guideDraft = value } } }
    }
}
struct RecoverySheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State var desktop: Desktop
    @State private var target = ""
    @State private var identity = ""
    @State private var now = Date()
    var observed: HostObservation { store.observations[desktop.id] ?? HostObservation() }
    var current: Desktop { store.desktops.first(where: { $0.id == desktop.id }) ?? desktop }
    func saveDetails() -> Bool {
        var value = current; value.target = target.isEmpty ? nil : target
        value.identityPath = (identity as NSString).expandingTildeInPath
        return store.save(value)
    }
    var detailsSaved: Bool { target == current.target && (identity as NSString).expandingTildeInPath == (current.identityPath ?? store.defaultIdentity) }
    var valid: Bool { InputValidation.target(target) && InputValidation.identityPath((identity as NSString).expandingTildeInPath) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Recovery for \(desktop.name)").font(.title2.bold())
            Text("Optional recovery supports Linux with systemd and an existing per-account Chrome host service. Other computers can remain connection-only. An existing reachable SSH route is needed; Tailscale is optional.").font(.callout).foregroundStyle(.secondary)
            TextField("SSH account and host, for example researcher@workstation.example", text: $target)
            HStack { TextField("Private key path", text: $identity); Button("Choose key…") { let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.showsHiddenFiles = true; if panel.runModal() == .OK, let url = panel.url { identity = url.path } } }
            HStack {
                Button("Save and check readiness") { if saveDetails() { store.check(current) } }.disabled(!valid || observed.busy)
                Button("SSH Terminal") { if saveDetails() { store.terminal(current, action: "connect") } }.disabled(!valid)
            }
            StatusDetails(observation: observed, now: now)
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
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 800)
            .onAppear { target = current.target ?? ""; identity = current.identityPath ?? store.defaultIdentity }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
    }
}

@main struct TelyndApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(store).preferredColorScheme(store.fixtureAppearance) }.windowStyle(.hiddenTitleBar).defaultSize(width: 1040, height: 780)
            .commands { CommandGroup(after: .appInfo) { Button("Setup guide") { store.showGuide = true } } }
    }
}
