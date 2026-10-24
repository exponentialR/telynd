import AppKit
import SwiftUI
import TelyndCore

struct PairingSetupView: View {
    @EnvironmentObject var store: AppStore
    let desktop: Desktop
    let use: (PairingCard, String) -> Void
    @State private var card: PairingCard?
    @State private var matchedAddress: String?
    @State private var note: String?
    @State private var checking = false
    @State private var request: UUID?
    @State private var control: PairingProbeControl?
    @State private var downloadCopied = false

    private func cancel() { control?.cancel(); control = nil; request = nil; checking = false }
    private func receive(_ text: String?) {
        cancel(); card = nil; matchedAddress = nil; note = nil
        do {
            guard let text else { throw PairingError.invalid }
            card = try PairingCard.parse(text)
        } catch { note = error.localizedDescription }
    }
    private func openFile() {
        let panel = NSOpenPanel(); panel.title = "Open the setup file from the Linux PC"
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        cancel(); card = nil; matchedAddress = nil; note = nil
        do {
            receive(String(data: try LocalHostReport.read(from: url), encoding: .utf8))
        } catch { note = error.localizedDescription }
    }
    private func check() {
        guard let card else { return }
        cancel(); note = nil; matchedAddress = nil
        let id = UUID(), guardControl = PairingProbeControl()
        request = id; control = guardControl; checking = true
        let original = desktop
        store.checkPairing(card, desktop: original, control: guardControl) { result in
            guard request == id, !guardControl.cancelled, desktop == original else { return }
            checking = false; request = nil; control = nil
            switch result {
            case .success(let address): matchedAddress = address
            case .failure(let error): note = error.localizedDescription
            }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if card == nil {
                Label("On this Mac", systemImage: "laptopcomputer").font(.headline)
                Text("Copy the Linux download link, then open this computer’s Google remote desktop. SSH is not needed yet.").font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Copy Linux download link") { downloadCopied = store.copyLinuxSetupDownloadLink() }
                    Button("Open remote desktop") { store.connect(desktop) }
                        .disabled(!desktop.hasDirectConnection || !store.profileReady(for: desktop))
                }
                if downloadCopied {
                    Label("Link copied. Paste it into a browser inside the Linux remote desktop.", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Label("Inside the Linux remote desktop", systemImage: "desktopcomputer").font(.headline)
                Text("Open a web browser there, paste the link into its address bar and press Enter. This downloads the installer onto the Linux PC.").font(.callout).foregroundStyle(.secondary)
                Text("When the download finishes, open \(LinuxSetupDownload.filename) from that browser’s Downloads list. Choose Install and approve the administrator prompt. Then find Telynd Setup in that PC’s applications and open it.").font(.callout).foregroundStyle(.secondary)
                Text("In Telynd Setup, choose Enable SSH if offered and approve the prompt. When ready, choose Copy setup card. The helper finds your login name and addresses for you.").font(.callout).foregroundStyle(.secondary)
                Text("Ubuntu/Debian desktop preview, downloaded from Telynd’s public GitHub repository. Keep the helper open until you have pasted its setup card.").font(.caption).foregroundStyle(.secondary)
                Divider()
            }
            Label("Back in Telynd on this Mac", systemImage: "doc.on.clipboard").font(.headline)
            Text("Return from the remote desktop and choose Paste setup card below. A setup card is the connection information copied by the Linux helper; it contains no password.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Paste setup card") { receive(NSPasteboard.general.string(forType: .string)) }
                Button("Open setup file…", action: openFile)
            }.disabled(checking)
            if let card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(card.hostname) · \(card.username)").font(.headline)
                    Text("Confirm that this card came from the PC you want to recover. Checking contacts only its listed addresses and compares the public SSH identity. It does not log in or accept host trust.").font(.caption).foregroundStyle(.secondary)
                    if let matchedAddress {
                        Label("Matching connection found", systemImage: "checkmark.circle").font(.callout.weight(.medium))
                        Button("Use this computer") {
                            do { try card.validate(); cancel(); use(card, matchedAddress) }
                            catch { self.matchedAddress = nil; note = error.localizedDescription }
                        }.buttonStyle(ConnectButton())
                    } else if checking {
                        ProgressView("Finding a matching connection…").controlSize(.small)
                        Button("Cancel check", action: cancel)
                    } else {
                        Button("Check this computer", action: check).buttonStyle(ConnectButton())
                    }
                }.padding(14).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }
            if let note { Text(note).font(.callout).foregroundStyle(.secondary) }
            Text("The card contains public setup details and expires after 15 minutes. Keep it private. It does not contain a password, private key or permission to connect.").font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Download or clipboard not working?") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("If the Linux PC cannot download from GitHub: save the installer on this Mac, then use File transfer → Upload file in Google’s remote-session side panel to send it to that PC. Find the uploaded file on Linux and open it there. If upload is unavailable, ask its administrator to provide the installer.")
                    Button("Save installer on this Mac…") { store.exportLinuxSetupHelper() }
                    Text("If the copied card cannot be pasted here: choose Save setup file in the Linux helper. Use Google’s File transfer → Download file to bring that file to this Mac, then choose Open setup file above. Both transfer directions depend on Google’s available session controls and your organisation’s policy.")
                    Text("Enabling SSH requires administrator approval on Linux. Existing authentication and firewall policy remain in control; no VPN is installed. Installation and access approval are separate steps.")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }.font(.callout)
        }.onChange(of: desktop) { _ in cancel(); card = nil; matchedAddress = nil }
            .onDisappear { cancel() }
    }
}
