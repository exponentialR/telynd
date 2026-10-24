# Telynd

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/branding/telynd-logo-dark.svg">
  <img src="assets/branding/telynd-logo-v2.svg" alt="Telynd" width="460">
</picture>

A native macOS app that keeps your remote computers in one place. Choose your
browser account for each computer and open Google Chrome Remote Desktop. SSH and
platform-specific service recovery are optional.

Google provides the remote screen connection and handles sign-in and its PIN.
Telynd adds a launcher and optional host recovery. Linux uses a timer; new Mac
and Windows developer kits use a user launch agent and native crash recovery
respectively, pending real-host validation. Service status does not prove Google can
connect. Recovery cannot wake a sleeping PC or fix expired Google authorisation.

**[Download Telynd 0.2.0 Preview 1 for Apple silicon](https://github.com/exponentialR/telynd/releases/download/v0.2.0-preview.1/Telynd-v0.2.0-preview.1-macos-arm64.zip).**
This free developer preview is ad-hoc signed and **not notarised by Apple**.
Read the included `READ_ME_FIRST.txt`: macOS may block its first opening and
require an app-specific **Open Anyway** approval in Privacy & Security.
No Xcode, Swift or Python installation is needed on the Mac. Runtime validation
covers macOS 26 on Apple silicon; the build minimum is macOS 13, with earlier
versions untested. Intel Macs are unsupported by this package.

[Release notes, checksums and installation evidence](https://github.com/exponentialR/telynd/releases/tag/v0.2.0-preview.1)
record the tested source and the initial macOS approval-prompt interruption.
Apple Developer ID signing and notarisation remain follow-up work under the
[release pipeline](docs/releasing.md). Source and original branding are released
under the [MIT licence](LICENSE).

- [Connect your first computer](docs/quick-start.md)
- [Guided Linux pairing without choosing an IP address](docs/pairing.md)
- [Optional SSH and Linux recovery, troubleshooting and uninstall](docs/recovery.md)
- [Mac and Windows recovery kits and their limits](docs/platform-recovery.md)
- [Host recovery architecture](docs/host-recovery-design.md)
- [Validation evidence and known gaps](docs/validation.md)
- [Device-import research decision](docs/device-import-decision.md)
- [Brand assets and logo](assets/branding/README.md)

## Build a developer app

On an Apple silicon Mac with the Swift toolchain:

```sh
git clone https://github.com/exponentialR/telynd.git
cd telynd
swift test
bash build.sh "$HOME/Applications/Telynd.app"
python3 -m unittest discover -s tests -v
for script in scripts/*.sh scripts/*.command tests/*.sh build.sh; do bash -n "$script"; done
```

The local build is ad-hoc signed and targets macOS 13+. Local runtime validation
covers macOS 26 / ARM64. Earlier macOS versions and Intel hardware are not yet
validated. The installed app needs no Python or third-party runtime. Google
Chrome is needed for screen connections; an SSH key is needed only for optional
Linux SSH access and recovery. Mac/Windows kits run locally on their hosts. Tailscale is an optional existing network route.

## Code map

| Path | Responsibility |
| --- | --- |
| `Sources/Telynd/` | SwiftUI guide, searchable computer rows, per-computer accounts and Terminal hand-off |
| `Sources/TelyndCore/` | Models, private persistence, profile metadata, readiness and bounded process execution |
| `linux-helper/` | Ubuntu/Debian desktop pairing helper and fixed administrator-approved SSH preparation |
| `scripts/build_linux_helper.py` | Builds the bundled Debian package from reviewable sources |
| `scripts/remote-check.sh` | Read-only structured readiness; explicit recovery mode |
| `scripts/setup-mac.command` | Separate SSH authorisation, key creation and installer actions, with private receipts |
| `scripts/authorise-remote.sh` | Fixed Linux public-key installer; stdin data, private files and preserved restrictions |
| `scripts/setup-remote.sh` | Root-owned fixed helpers, timer, narrow sudoers and verification record |
| `scripts/uninstall-remote.sh` | Explicit verified disable/uninstall |
| `scripts/macos-recovery.sh` | Host-local signed-in Mac agent and bounded recovery |
| `scripts/windows-recovery.ps1` | Host-local native crash policy with verified restoration |
| `scripts/WindowsServicePolicy.cs` | Windows SCM policy/security adapter |
| `tests/` | Swift core tests, platform fixtures and disposable Linux/launchd/SCM integration |
| `build.sh` | Build and assemble a locally signed ARM64 app |
| `scripts/release-macos.sh` | Credential-gated signing, notarisation and versioned release assets |

## Local data and security boundaries

Settings live under `~/Library/Application Support/Telynd/`: `desktops.json`,
`preferences.json` and private Terminal launchers/receipts. Files use owner-only
permissions. Existing settings under `Application Support/Remote Desktops/` are
copied only when the corresponding Telynd file is absent. Existing users retain
their desktop identities and are not forced through first-run setup. Corrupt or
future-version settings are preserved and saving is locked until corrected.

Telynd reads Chrome's local profile names, email labels and directory IDs.
**Choose computer in Chrome** requests macOS Automation access and opens a
new window in the chosen profile. A temporary local-page marker binds that exact
tab before Telynd navigates it to Google's device picker. It checks that tab's
address once per second, including while Chrome is in the background, until a
valid computer link is detected or setup ends. You confirm the link before it
fills the draft, then Save. Detection stops on cancellation, closing setup,
changing the draft or after five minutes. Closed or moved tabs require a retry.
The optional **Use open computer** fallback reads the front tab's address once.
macOS's permission permits broader app automation; this implementation reads
addresses and tab/window identifiers and navigates only its marked setup tab.
It does not enumerate tabs or read page content, cookies, browser passwords,
OAuth tokens or remote screen contents. Manual entry remains available if
permission is denied. Sign-in and PIN prompts stay in Chrome.
Each computer remembers its Chrome profile directory and email label. There is
no global account switch. New computers use the sole available signed-in
profile automatically; multiple profiles require a one-time selection. Missing
or changed profiles require an explicit choice and never fall back to another
account. Existing global choices are migrated once to existing computers and
setup drafts, preserving their SSH settings. Preferences use schema 3,
which older builds reject rather than ignoring account choices or saved removals.
The account label reflects Chrome metadata; the URL reader cannot identify the
Google account active in the captured tab. Profile selection is not Google authentication. There is no telemetry or
Google device-list API integration. Captured and saved Google links are checked before launch;
SSH and Google device identities are never assumed to be equivalent.

Removed entries are kept privately in preferences for Undo and **Help → Recently
removed computers** with no automatic expiry. **Delete permanently…** in that
screen deletes a saved entry after confirmation, without an option to restore.
Removal and permanent deletion do not unregister the Google host, revoke SSH
keys or uninstall host recovery. Terminal launchers and receipts remain in
place. Those host and access changes have their own explicit actions.

Adding a computer has two visible steps: **Connection → Recovery (optional)**.
The recovery step explains the selected operating system's route. For Linux,
**Save & set up recovery…** opens the guided setup immediately after saving. **Save
connection only** skips recovery. Editing retains saved SSH details, and saving
without opening recovery never disables an existing host timer.

Linux recovery starts with guided pairing. Copy the pinned Ubuntu/Debian
helper download link, open a browser inside the existing Google remote session
and download/install it directly on that Linux PC. Existing SSH is not needed
for this step. The screen separates actions on this Mac from actions inside
the Linux desktop; manual installer transfer is a fallback. It collects public connection details and can enable SSH
after local administrator approval. Bring its short-lived setup card back to
Telynd; the Mac checks only those candidate IPv4 addresses for a matching public
host key. It does not log in, trust keys automatically or install a VPN. The
normal route does not ask users to choose an IP or key file. Advanced manual
connection entry remains available. First SSH trust and passwords still stay
in Terminal, followed by separate recovery installation. See [pairing](docs/pairing.md)
for supported hosts, approvals and network prerequisites.
Saved Linux recovery settings and completed Terminal actions trigger bounded,
read-only readiness checks. New or edited details also have an explicit check.
One-time changes
are explained before Terminal opens. Login passwords and passphrases stay in
standard SSH, Keychain and sudo prompts. SSH host identity checks remain enabled.
The root permissions permit only the account's fixed recovery and read-only
status helpers with no arguments. The installer leaves active, disabled and
transitioning Chrome services alone; uninstall preserves Chrome and SSH keys.

See [CONTRIBUTING.md](CONTRIBUTING.md) for verification and contribution guidance.
The bundled Manrope font retains its [SIL Open Font Licence](assets/branding/source/OFL.txt).
Telynd is independent and is not affiliated with Google or Apple.

## Session windows

Connect opens the saved computer link in a separate Chrome window using that
computer’s saved browser account. **… → Open in Chrome tab** keeps the tab
option available. Google still owns the screen connection and sign-in; this
is not a viewer embedded inside Telynd. The [viewer feasibility record](docs/session-viewer.md)
explains the native WebKit probe, account/window checks and remaining integration
requirements. Recovery behaviour is unchanged.
