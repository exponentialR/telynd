import SwiftUI
import AppKit

struct Desktop: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var target: String
    var chromeURL: String = "https://remotedesktop.google.com/access"
    var symbol: String = "desktopcomputer"
}

struct HostStatus {
    var message = "Check SSH access and the Chrome host service."
    var busy = false
    var healthy: Bool? = nil
}

@MainActor final class DesktopStore: ObservableObject {
    @Published var desktops: [Desktop] = []
    @Published var statuses: [UUID: HostStatus] = [:]
    @Published var error: String?
    @Published var chromeProfileEmail = ""
    let support = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Telynd")
    var resources: URL { Bundle.main.resourceURL! }

    init() {
        // Preserve settings from the prototype without overwriting Telynd edits.
        let legacy = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Remote Desktops")
        do {
            for name in ["desktops.json", "preferences.json"] {
                let source = legacy.appendingPathComponent(name)
                let destination = support.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: destination.path),
                   FileManager.default.fileExists(atPath: source.path) {
                    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    try FileManager.default.copyItem(at: source, to: destination)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
                }
            }
        } catch { self.error = "Could not migrate existing settings: \(error.localizedDescription)" }
        let config = support.appendingPathComponent("desktops.json")
        if FileManager.default.fileExists(atPath: config.path) {
            do { desktops = try JSONDecoder().decode([Desktop].self, from: Data(contentsOf: config)) }
            catch { self.error = "Could not read saved desktops: \(error.localizedDescription)" }
        }
        let preferences = support.appendingPathComponent("preferences.json")
        if FileManager.default.fileExists(atPath: preferences.path) {
            do {
                let saved = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: preferences))
                chromeProfileEmail = saved["chromeProfileEmail"] ?? ""
            } catch { self.error = "Could not read Chrome profile settings: \(error.localizedDescription)" }
        }
    }

    func saveChromeProfile(_ value: String) {
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let selected = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let path = support.appendingPathComponent("preferences.json")
            try JSONEncoder().encode(["chromeProfileEmail": selected]).write(to: path, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
            chromeProfileEmail = selected
        } catch { self.error = error.localizedDescription }
    }

    func save(_ desktop: Desktop) {
        var updated = desktops
        if let index = updated.firstIndex(where: { $0.id == desktop.id }) { updated[index] = desktop }
        else { updated.append(desktop) }
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(updated)
            let path = support.appendingPathComponent("desktops.json")
            try data.write(to: path, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
            desktops = updated
        } catch { self.error = error.localizedDescription }
    }

    static func validTarget(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z_][A-Za-z0-9_-]*@[A-Za-z0-9][A-Za-z0-9.-]*$", options: .regularExpression) != nil
    }

    static func validChromeURL(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return url.scheme == "https" && url.host == "remotedesktop.google.com" && url.user == nil && url.password == nil && url.port == nil
    }

    func check(_ desktop: Desktop, recover: Bool = false) {
        guard Self.validTarget(desktop.target) else { error = "Use a target in the form user@host."; return }
        guard statuses[desktop.id]?.busy != true else { return }
        statuses[desktop.id] = HostStatus(message: recover ? "Checking whether recovery is needed…" : "Checking over SSH…", busy: true)
        let script = resources.appendingPathComponent("remote-check.sh")
        let key = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/id_ed25519").path
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let output = Pipe()
            var message: String
            var ok = false
            do {
                let input = try FileHandle(forReadingFrom: script)
                defer { try? input.close() }
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                process.arguments = ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=8",
                    "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=2", "-o", "UseKeychain=yes",
                    "-o", "AddKeysToAgent=yes", "-i", key, desktop.target, "bash -s -- \(recover ? "recover" : "check")"]
                process.standardInput = input
                process.standardOutput = output
                process.standardError = output
                try process.run()
                DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                    if process.isRunning { process.terminate() }
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                ok = process.terminationStatus == 0
                if raw.contains("Permission denied") {
                    message = "SSH key setup needed. Choose Set up access and enter the host password once."
                } else if raw.contains("Host key verification failed") {
                    message = "Host identity needs checking. Use SSH terminal to verify its fingerprint before connecting."
                } else if raw.contains("timed out") || raw.contains("No route") {
                    message = "SSH could not reach this PC. Check that it is awake and Tailscale is connected."
                } else { message = raw.isEmpty ? "SSH ended without a status. Open SSH terminal for details." : String(raw.suffix(1600)) }
            } catch { message = error.localizedDescription }
            DispatchQueue.main.async {
                self.statuses[desktop.id] = HostStatus(message: message, busy: false, healthy: ok)
            }
        }
    }

    private func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    func terminal(_ desktop: Desktop, setup: Bool = false) {
        guard Self.validTarget(desktop.target) else { error = "Invalid SSH target."; return }
        if setup {
            let alert = NSAlert()
            alert.messageText = "Set up \(desktop.name)"
            alert.informativeText = "The terminal will ask for this PC’s login password once, and its sudo password to install recovery. It authorises your existing Mac SSH key and installs a timer that checks every two minutes. Only an enabled, stopped or failed Chrome host is restarted. The account receives permission to run that fixed recovery helper without a password."
            alert.addButton(withTitle: "Open setup")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        do {
            let folder = support.appendingPathComponent("Launchers")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let file = folder.appendingPathComponent("\(desktop.id.uuidString)-\(setup ? "setup" : "ssh").command")
            let helper = resources.appendingPathComponent("launch-host.command").path
            let script = "#!/bin/bash\nexec /bin/bash \(quote(helper)) \(quote(desktop.target)) \(setup ? "setup" : "connect")\n"
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
            NSWorkspace.shared.open(file)
        } catch { self.error = error.localizedDescription }
    }

    func connect(_ desktop: Desktop) {
        guard !chromeProfileEmail.isEmpty else {
            error = "Choose your Chrome profile email in the launcher first."; return
        }
        guard Self.validChromeURL(desktop.chromeURL), let url = URL(string: desktop.chromeURL) else {
            error = "Use an HTTPS Chrome Remote Desktop link."; return
        }
        if let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") {
            let localState = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Google/Chrome/Local State")
            guard let data = try? Data(contentsOf: localState),
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let profile = root["profile"] as? [String: Any],
                  let cache = profile["info_cache"] as? [String: [String: Any]],
                  let directory = cache.first(where: { ($0.value["user_name"] as? String)?.lowercased() == chromeProfileEmail.lowercased() })?.key else {
                error = "The Chrome profile \(chromeProfileEmail) could not be found. Sign in to that profile in Chrome first."
                return
            }
            // Chrome forwards this invocation to the existing browser process,
            // selecting the profile explicitly even when another one is active.
            let process = Process()
            process.executableURL = chrome.appendingPathComponent("Contents/MacOS/Google Chrome")
            process.arguments = ["--profile-directory=\(directory)", url.absoluteString]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { self.error = error.localizedDescription }
        } else { error = "Google Chrome was not found. Install Chrome to use the selected browser profile." }
    }
}

struct DesktopCard: View {
    @EnvironmentObject var store: DesktopStore
    let desktop: Desktop
    var edit: () -> Void
    var status: HostStatus { store.statuses[desktop.id] ?? HostStatus() }
    var colour: Color { status.healthy == true ? .green : status.healthy == false ? .orange : .secondary }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: desktop.symbol).font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Color.accentColor).frame(width: 54, height: 54)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 5) {
                    Text(desktop.name).font(.title2.weight(.semibold))
                    Text(desktop.target).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                Button(action: edit) { Image(systemName: "slider.horizontal.3") }.buttonStyle(.borderless).help("Edit desktop")
            }
            HStack(alignment: .top, spacing: 9) {
                if status.busy { ProgressView().controlSize(.small) }
                else { Circle().fill(colour).frame(width: 8, height: 8).padding(.top, 5) }
                Text(status.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 62, alignment: .top)
            Button { store.connect(desktop) } label: {
                Label("Open remote desktop", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity).padding(.vertical, 4)
            }.buttonStyle(TelyndPrimaryButtonStyle())
            HStack {
                Button("Check status") { store.check(desktop) }
                Button("Recover if stopped") { store.check(desktop, recover: true) }
            }.disabled(status.busy)
            Divider()
            HStack {
                Button { store.terminal(desktop) } label: { Label("SSH terminal", systemImage: "terminal") }
                Spacer()
                Button("Set up access…") { store.terminal(desktop, setup: true) }
            }.buttonStyle(.link).font(.callout)
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.primary.opacity(0.08)))
    }
}

struct TelyndPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Color(red: 18.0 / 255, green: 92.0 / 255, blue: 1)
                    .opacity(configuration.isPressed ? 0.82 : 1),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct DesktopEditor: View {
    @EnvironmentObject var store: DesktopStore
    @Environment(\.dismiss) var dismiss
    @State var desktop: Desktop
    var valid: Bool { !desktop.name.trimmingCharacters(in: .whitespaces).isEmpty && DesktopStore.validTarget(desktop.target) && DesktopStore.validChromeURL(desktop.chromeURL) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Desktop details").font(.title2.bold())
            Form {
                TextField("Name", text: $desktop.name)
                TextField("SSH address", text: $desktop.target)
                TextField("Chrome Remote Desktop URL", text: $desktop.chromeURL)
            }
            Text("Use user@hostname or user@Tailscale-IP. Paste a device link from Chrome Remote Desktop to open that PC directly. Until then, the button opens Google’s device picker.")
                .font(.callout).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") { store.save(desktop); dismiss() }.keyboardShortcut(.defaultAction).disabled(!valid) }
        }.padding(26).frame(width: 580)
    }
}

struct ContentView: View {
    @EnvironmentObject var store: DesktopStore
    @State private var editing: Desktop?
    @State private var choosingProfile = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("YOUR WORKSPACE, ANYWHERE").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                        TelyndWordmark()
                        Text("Your computers. One place to connect and recover.").font(.title3).foregroundStyle(.secondary)
                        Button { choosingProfile = true } label: {
                            Label(store.chromeProfileEmail.isEmpty ? "Choose Chrome profile…" : store.chromeProfileEmail, systemImage: "person.crop.circle")
                        }.buttonStyle(.link).font(.callout)
                    }
                    Spacer()
                    Button { editing = Desktop(name: "", target: "") } label: { Label("Add desktop", systemImage: "plus") }.controlSize(.large)
                }
                if store.desktops.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "desktopcomputer").font(.system(size: 42)).foregroundStyle(.secondary)
                        Text("Add your first desktop").font(.title2.weight(.semibold))
                        Text("Save its SSH address and choose the Chrome profile you use for remote access.").foregroundStyle(.secondary)
                        Button("Add desktop") { editing = Desktop(name: "", target: "") }.buttonStyle(TelyndPrimaryButtonStyle())
                    }.frame(maxWidth: .infinity).padding(40)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), alignment: .top)], alignment: .leading, spacing: 22) {
                    ForEach(store.desktops) { desktop in
                        DesktopCard(desktop: desktop) { editing = desktop }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label("Recovery that runs on the PC", systemImage: "arrow.triangle.2.circlepath").font(.headline)
                    Text("After one-time setup, a two-minute timer checks the Chrome host even when this Mac app is closed. It restarts an enabled service only when stopped or failed. An awake PC, internet access and valid Google authorisation are still required.")
                    Text("Status checks report the Linux service. Confirm availability in Chrome Remote Desktop. Google sign-in and its connection PIN remain managed by Chrome.")
                }.font(.callout).foregroundStyle(.secondary).padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
            }.padding(34)
        }.background(Color(nsColor: .windowBackgroundColor))
        .tint(Color(red: 18.0 / 255, green: 92.0 / 255, blue: 1))
        .frame(minWidth: 830, minHeight: 620)
        .sheet(item: $editing) { DesktopEditor(desktop: $0).environmentObject(store) }
        .sheet(isPresented: $choosingProfile) { ChromeProfileEditor(email: store.chromeProfileEmail).environmentObject(store) }
        .alert("Telynd", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

struct TelyndWordmark: View {
    @Environment(\.colorScheme) private var colourScheme
    var body: some View {
        let name = colourScheme == .dark ? "telynd-logo-dark" : "telynd-logo-v2"
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let logo = NSImage(contentsOf: url) {
            Image(nsImage: logo).resizable().scaledToFit()
                .frame(width: 252, height: 78, alignment: .leading)
                .accessibilityLabel("Telynd")
        } else {
            Text("Telynd").font(.system(size: 36, weight: .bold, design: .rounded))
        }
    }
}

struct ChromeProfileEditor: View {
    @EnvironmentObject var store: DesktopStore
    @Environment(\.dismiss) var dismiss
    @State var email: String
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Chrome profile").font(.title2.bold())
            TextField("Google account email", text: $email)
            Text("Choose the email shown for your existing Chrome profile. Remote desktop links open in that profile even when another profile is active. This setting stays on your Mac.").font(.callout).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") { store.saveChromeProfile(email); dismiss() }.keyboardShortcut(.defaultAction).disabled(!email.contains("@")) }
        }.padding(26).frame(width: 520)
    }
}

@main struct TelyndApp: App {
    @StateObject private var store = DesktopStore()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(store) }
            .windowStyle(.hiddenTitleBar)
            .defaultSize(width: 1000, height: 710)
    }
}
