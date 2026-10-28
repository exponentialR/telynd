import AppKit
import SwiftUI
import SwiftTerm
import TelyndCore

/// One native Telynd window per computer. Repeated Start SSH clicks focus it.
@MainActor final class SSHTerminalWindows {
    private var windows: [UUID: SSHTerminalWindow] = [:]

    func open(_ desktop: Desktop, identity: String) {
        if let existing = windows[desktop.id] {
            if existing.session.desktop.target != desktop.target || existing.session.identity != identity {
                existing.close()
            } else {
                existing.showWindow(nil)
                existing.window?.makeKeyAndOrderFront(nil)
                existing.window?.makeFirstResponder(existing.session.terminalView)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }
        let controller = SSHTerminalWindow(session: SSHSession(desktop: desktop, identity: identity))
        controller.onClosed = { [weak self] in self?.windows[desktop.id] = nil }
        windows[desktop.id] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.session.start()
    }
}

@MainActor final class SSHTerminalWindow: NSWindowController, NSWindowDelegate {
    let session: SSHSession
    var onClosed: (() -> Void)?
    private var quitObserver: NSObjectProtocol?

    init(session: SSHSession) {
        self.session = session
        let desktop = session.desktop
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 580),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "\(desktop.name) — SSH"
        window.minSize = NSSize(width: 640, height: 380)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SSHSessionView(session: session))
        window.delegate = self
        window.center()
        quitObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.session.disconnect() }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let quitObserver { NotificationCenter.default.removeObserver(quitObserver) } }

    func windowWillClose(_ notification: Notification) {
        if session.isRunning {
            // Retain the closing controller until OpenSSH exits and is reaped.
            session.onEnded = { [self] in session.onEnded = nil }
            session.disconnect()
        }
        onClosed?()
    }
}

/// OpenSSH owns authentication. Input and output remain in this in-memory PTY.
final class SSHSession: NSObject, ObservableObject, LocalProcessTerminalViewDelegate, TerminalViewDelegate {
    let desktop: Desktop
    let identity: String
    let terminalView = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 900, height: 520))
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Ready"
    var onEnded: (() -> Void)?
    private var disconnecting = false
    private let launch: (LocalProcessTerminalView, [String]) -> Void

    init(desktop: Desktop, identity: String,
         launch: @escaping (LocalProcessTerminalView, [String]) -> Void = { view, args in view.startProcess(executable: "/usr/bin/ssh", args: args) }) {
        self.desktop = desktop
        self.identity = identity
        self.launch = launch
        super.init()
        terminalView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        terminalView.nativeBackgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        terminalView.nativeForegroundColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        terminalView.processDelegate = self
        // Proxy transport callbacks while retaining the delegate's safe defaults
        // for remote clipboard requests. User-initiated Copy and Paste still work.
        terminalView.terminalDelegate = self
    }

    func start() {
        guard !isRunning, let target = desktop.target, InputValidation.target(target), InputValidation.identityPath(identity) else { return }
        disconnecting = false
        isRunning = true
        status = "SSH session · \(target)"
        terminalView.terminal.resetToInitialState()
        terminalView.feed(text: "\r\nConnecting to \(target)…\r\n")
        launch(terminalView, SSHPolicy.interactiveArguments(identity: identity, target: target))
        if !terminalView.process.running {
            isRunning = false
            status = "SSH could not start. Try reconnecting."
        }
        terminalView.window?.makeFirstResponder(terminalView)
    }

    func disconnect() {
        guard isRunning, !disconnecting else { return }
        disconnecting = true
        status = "Disconnecting…"
        let process = terminalView.process!
        let pid = process.shellPid
        guard pid > 0 else { return }
        // Keep SwiftTerm's exit monitor alive so it reaps the child. Calling
        // terminate() cancels that monitor before waitpid can collect the exit.
        kill(pid, SIGHUP)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if self.isRunning, self.terminalView.process === process, process.shellPid == pid { kill(pid, SIGKILL) }
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        // SwiftTerm 1.x reports waitpid's status, including signal termination.
        let code = exitCode.map { ($0 & 0x7f) == 0 ? ($0 >> 8) & 0xff : 128 + ($0 & 0x7f) }
        isRunning = false
        if disconnecting { status = "Disconnected" }
        else if code == 0 { status = "Session ended" }
        else { status = "SSH ended\(code.map { " (exit \($0))" } ?? ""). Check the terminal output." }
        disconnecting = false
        onEnded?()
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        terminalView.sizeChanged(source: source, newCols: newCols, newRows: newRows)
    }
    func setTerminalTitle(source: TerminalView, title: String) {}
    func send(source: TerminalView, data: ArraySlice<UInt8>) { terminalView.send(source: source, data: data) }
    func scrolled(source: TerminalView, position: Double) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct EmbeddedSSHTerminal: NSViewRepresentable {
    let session: SSHSession
    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = session.terminalView
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }
    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {}
}

private struct SSHSessionView: View {
    @ObservedObject var session: SSHSession
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(session.status, systemImage: "terminal").font(.callout).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer()
                if session.isRunning { Button("Disconnect") { session.disconnect() } }
                else { Button("Reconnect") { session.start() } }
            }.padding(12)
            Divider()
            EmbeddedSSHTerminal(session: session)
            Text("Closing this window disconnects SSH. Verify any new host fingerprint before accepting it.")
                .font(.caption).foregroundStyle(.secondary).padding(8)
        }
    }
}

struct SSHSettingsSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let desktop: Desktop
    @State private var address = SSHAddress()
    @State private var identity = ""
    @State private var problem: String?
    var key: String { (identity as NSString).expandingTildeInPath }

    func save(start: Bool) {
        guard var current = store.desktops.first(where: { $0.id == desktop.id }) else { problem = "Restore this computer before saving SSH settings."; return }
        guard current.target == desktop.target, current.identityPath == desktop.identityPath else { problem = "SSH settings changed in another window. Close this sheet and reopen SSH settings."; return }
        current.target = address.target
        current.identityPath = key
        guard store.save(current) else { problem = store.error; store.error = nil; return }
        dismiss()
        if start { store.startSSH(current) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("SSH for \(desktop.name)").font(.title2.weight(.semibold))
            Text("Enter the login details for this computer. Start SSH opens a terminal inside Telynd.").foregroundStyle(.secondary)
            TextField("Username", text: $address.username)
            TextField("Hostname or IP address", text: $address.host)
            HStack {
                TextField("SSH private key path", text: $identity)
                Button("Choose key…") {
                    let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.showsHiddenFiles = true
                    if panel.runModal() == .OK, let url = panel.url { identity = url.path }
                }
            }
            Text("SSH must be enabled on the remote computer. Password and key-passphrase prompts appear in the terminal. These details are also used by Linux recovery. Custom ports can be set in your SSH configuration.")
                .font(.caption).foregroundStyle(.secondary)
            if let problem { Text(problem).font(.callout).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { save(start: false) }.disabled(address.target == nil || !InputValidation.identityPath(key) || store.writeLocked)
                Button("Start SSH") { save(start: true) }.buttonStyle(ConnectButton()).keyboardShortcut(.defaultAction)
                    .disabled(address.target == nil || !InputValidation.identityPath(key) || store.writeLocked)
            }
        }.padding(28).frame(width: 540)
            .onAppear { address = SSHAddress(target: desktop.target); identity = store.suggestedIdentity(for: desktop) }
    }
}
