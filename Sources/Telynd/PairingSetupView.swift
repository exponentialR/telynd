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
            Label("Prepare the remote PC", systemImage: "desktopcomputer").font(.headline)
            Text("Open your working Google remote session. Transfer the helper to that Linux PC, open the package installer, then launch Telynd Setup from its applications menu. The helper supplies the connection details for you.").font(.callout).foregroundStyle(.secondary)
            Button("Get setup helper…") { store.exportLinuxSetupHelper() }
            Text("Ubuntu/Debian desktop preview. The package manager installs its desktop dependencies. Enabling SSH inside the helper requires administrator approval and preserves existing authentication and firewall policy.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Label("Bring back its setup card", systemImage: "doc.on.clipboard").font(.headline)
            Text("In the helper, choose Copy setup card. Return to Telynd on this Mac and paste it here. If clipboard sharing is unavailable, save a setup file on the PC and transfer that file back instead.").font(.callout).foregroundStyle(.secondary)
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
        }.onChange(of: desktop) { _ in cancel(); card = nil; matchedAddress = nil }
            .onDisappear { cancel() }
    }
}
