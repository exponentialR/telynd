# Telynd

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/branding/telynd-logo-dark.svg">
  <img src="assets/branding/telynd-logo-v2.svg" alt="Telynd" width="460">
</picture>

A native macOS app that keeps your remote computers in one place. Choose your
Chrome profile, save a computer and open Google Chrome Remote Desktop. SSH and
Linux service recovery are optional.

Google provides the remote screen connection and handles sign-in and its PIN.
Telynd adds a launcher and an optional Linux timer that starts an enabled Chrome
host service if it stops or fails. Service status does not prove Google can
connect. Recovery cannot wake a sleeping PC or fix expired Google authorisation.

**Early developer preview:** no signed public download is available yet. The
[release pipeline](docs/releasing.md) is prepared; Apple signing credentials and
the real download smoke test remain prerequisites. Source and original branding
are released under the [MIT licence](LICENSE).

- [Connect your first computer](docs/quick-start.md)
- [Optional SSH and Linux recovery, troubleshooting and uninstall](docs/recovery.md)
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
SSH access and recovery. Tailscale is an optional existing network route.

## Code map

| Path | Responsibility |
| --- | --- |
| `Sources/Telynd/` | SwiftUI guide, cards, profile picker and Terminal hand-off |
| `Sources/TelyndCore/` | Models, private persistence, profile metadata, readiness and bounded process execution |
| `scripts/remote-check.sh` | Read-only structured readiness; explicit recovery mode |
| `scripts/setup-mac.command` | Separate SSH authorisation, key creation and installer actions, with private receipts |
| `scripts/authorise-remote.sh` | Fixed Linux public-key installer; stdin data, private files and preserved restrictions |
| `scripts/setup-remote.sh` | Root-owned fixed helpers, timer, narrow sudoers and verification record |
| `scripts/uninstall-remote.sh` | Explicit verified disable/uninstall |
| `tests/` | Swift core tests, shell protocol/decision fixtures and disposable Linux integration |
| `build.sh` | Build and assemble a locally signed ARM64 app |
| `scripts/release-macos.sh` | Credential-gated signing, notarisation and versioned release assets |

## Local data and security boundaries

Settings live under `~/Library/Application Support/Telynd/`: `desktops.json`,
`preferences.json` and private Terminal launchers/receipts. Files use owner-only
permissions. Existing settings under `Application Support/Remote Desktops/` are
copied only when the corresponding Telynd file is absent. Existing users retain
their desktop identities and are not forced through first-run setup. Corrupt or
future-version settings are preserved and saving is locked until corrected.

Telynd reads only Chrome's local profile names, email labels and directory IDs.
It does not read cookies, browser passwords, OAuth tokens or remote screen
contents. Profile selection is not Google authentication. There is no telemetry
or automatic device import. Supported Google links are checked before launch;
SSH and Google device identities are never assumed to be equivalent.

Routine readiness checks are explicit, bounded and read-only. One-time changes
are explained before Terminal opens. Login passwords and passphrases stay in
standard SSH, Keychain and sudo prompts. SSH host identity checks remain enabled.
The root permissions permit only the account's fixed recovery and read-only
status helpers with no arguments. The installer leaves active, disabled and
transitioning Chrome services alone; uninstall preserves Chrome and SSH keys.

See [CONTRIBUTING.md](CONTRIBUTING.md) for verification and contribution guidance.
The bundled Manrope font retains its [SIL Open Font Licence](assets/branding/source/OFL.txt).
Telynd is independent and is not affiliated with Google or Apple.
