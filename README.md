# Telynd

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/branding/telynd-logo-dark.svg">
  <img src="assets/branding/telynd-logo-v2.svg" alt="Telynd" width="460">
</picture>

[Logo files, app icon and brand notes](assets/branding/README.md)

A native macOS launcher combining Chrome Remote Desktop links, SSH access and
recovery for stopped Linux Chrome host services. Telynd is an early prototype,
released under the [MIT licence](LICENSE).

The open-portal identity is used in the app header and Mac icon. The header
switches between the light and dark logo variants automatically.

Google Chrome Remote Desktop provides the remote screen connection. This app
adds a launcher, SSH status checks and an optional timer on each Linux host.
A running Linux service is not proof that Google can connect to that host.

## Code map

| File | Responsibility |
| --- | --- |
| `Telynd.swift` | SwiftUI interface, local settings, Chrome profile selection and SSH status checks |
| `scripts/launch-host.command` | Check for recovery, then open an SSH session |
| `scripts/setup-mac.command` | Authorise an existing Mac SSH key and start host installation |
| `scripts/setup-remote.sh` | Generate and install the fixed recovery helper, timer and sudoers rule |
| `scripts/remote-check.sh` | Read the Linux Chrome service state and request recovery when stopped |
| `tests/test_recovery.py` | Exercise recovery decisions against a fake systemctl |
| `build.sh` | Compile, assemble and locally sign the Mac app |

The Mac sends `remote-check.sh` to the host through SSH standard input. A status
check reads service properties without changing the host. A recovery request
calls the installed helper through `sudo -n`; that helper checks the state again
before restarting the fixed service. The host timer calls the same helper.

## Use

Build the app using the command below, then open
`~/Applications/Telynd.app`. A fresh installation starts with no desktops
or selected Google account.

1. Choose **Choose Chrome profile…** and enter the email for an existing signed-in
   Chrome profile.
2. Choose **Add desktop**, name the PC and enter its SSH target, for example
   `researcher@workstation.example`.
3. Optionally save its HTTPS Chrome Remote Desktop device link. The default
   opens Google's device picker in the chosen Chrome profile.
4. Choose **Set up access…** to authorise SSH key access and install recovery.

The terminal unlocks the existing Mac SSH key if necessary, asks for the Linux
login password to install its public key, and asks for the Linux sudo password
to install the recovery helper and timer. Verify the host fingerprint using a
trusted record if SSH asks about a new host. The app does not store passwords.

After setup, **Check status** verifies SSH and the Linux Chrome host service.
**Recover if stopped** runs the fixed recovery helper without a password.
**SSH terminal** checks for recovery first, then opens the usual SSH session.

**Open remote desktop** opens the saved Google link in the chosen Chrome profile.
Use the edit control to save a device's own Chrome Remote Desktop link once its
identity is confirmed. The app does not assume that a Google display name maps
to a particular SSH destination. Additional desktops can be added with the same
controls. Only Linux hosts with the per-account systemd Chrome service support
the recovery installer.

## Recovery boundary

The host-side timer checks every two minutes, including while the Mac is asleep
or the launcher is closed. It restarts an enabled service in `inactive` or
`failed` state. A running, disabled or transitioning service is left alone. A lock
prevents simultaneous recovery requests. A failed restart is reported as a
failure, and the timer has a 60-second execution limit.

Linux service status does **not** establish Google's online status. A running
host with expired Google authorisation, a network fault or a hung process can
still appear offline. This first version does not automatically restart that
case. It cannot wake a powered-off PC. Google's login and remote connection PIN
remain under Chrome's control.

The installer creates root-owned files named with the Linux account's numeric
UID:

- `/usr/local/libexec/remote-desktops-recover-UID`
- `/etc/systemd/system/remote-desktops-recovery-UID.service`
- `/etc/systemd/system/remote-desktops-recovery-UID.timer`
- `/etc/sudoers.d/remote-desktops-recovery-UID`

The sudoers entry grants this account access only to its fixed helper. The helper
accepts no arguments and targets only its own Chrome service. No general
password-free sudo rule is installed. The existing Chrome service is not
enabled if it was disabled. Host installation is only performed when the user
runs **Set up access…** and completes authentication in the terminal.

## Build and verification

```sh
git clone https://github.com/exponentialR/telynd.git
cd telynd
bash build.sh "$HOME/Applications/Telynd.app"
python3 -m unittest discover -s tests -v
for script in scripts/*.sh scripts/*.command build.sh; do bash -n "$script"; done
```

Requires macOS, Google Chrome and an existing `~/.ssh/id_ed25519` key with its
matching `.pub` file. Create a key yourself with `ssh-keygen -t ed25519` if needed.
For service recovery, the remote account must have sudo access during setup,
and the Linux host needs systemd, flock, Bash and a registered per-user
`chrome-remote-desktop@USERNAME.service`. Tailscale is optional; a reachable SSH
connection is sufficient. The target format is `user@hostname` or `user@IPv4`;
custom ports and IPv6 literals are not currently supported by the editor.

The build targets macOS 13 or later and was checked locally on Apple silicon
macOS 26. Earlier macOS releases, Intel hardware and live host installation have
not been validated locally. GitHub Actions also builds the app on its current
macOS runner and runs the recovery tests on Linux. CI does not connect to a real
desktop. The app is locally signed, not notarised for distribution.

Requires the Mac's Swift toolchain to build. The installed app has no Python or
third-party runtime dependency. Recovery tests use a fake systemctl and make no
SSH connections. They cover running, stopped, failed, disabled, transitioning
and unknown states, including a failed start and attempts to pass an arbitrary
service name to the helper. They do not validate a live Linux install or Chrome
connection. Linux runs the concurrent-recovery test using real flock; macOS
skips that test because flock is not installed by default. The helper uses a
private directory under root-owned `/run` for its lock. It uses `systemctl start`
so a concurrent service start does not cause a running session to be restarted.

Desktop configuration is stored in
`~/Library/Application Support/Telynd/desktops.json`; the Chrome account
is stored in `preferences.json` in the same directory. Both files are written
with owner-only permissions. Chrome's local profile metadata is read to find the
selected account's profile directory. Cookies and browser passwords are not
read by the app. SSH host keys remain checked. Existing Mac SSH credentials are
used through the agent and macOS keychain. Desktop names, SSH targets and the
chosen Chrome account are loaded from local settings; they are not embedded in
the source. Original local launchers and the
personal preview screenshot are excluded by `.gitignore`. Building the generic
app does not replace any existing Desktop scripts.

On first launch, Telynd copies existing desktop and profile settings from
`~/Library/Application Support/Remote Desktops/` if the corresponding Telynd
settings do not exist. Existing Telynd settings take precedence. The Linux
helper and timer retain their `remote-desktops-*` identifiers for compatibility.

## Remove host-side recovery

On each Linux PC, replace UID below with `id -u`, then disable the timer:

```sh
sudo systemctl disable --now remote-desktops-recovery-UID.timer
```

Remove the four app-specific files listed above and run
`sudo systemctl daemon-reload` to remove the installation completely. This does
not remove Chrome Remote Desktop or its host registration. SSH public-key
access remains until the corresponding entry is removed from that account's
`~/.ssh/authorized_keys`.

Linux Chrome host status and service behaviour were checked against the
[Chromium host source](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/remoting/host/linux/linux_me2me_host.py).
See [Google's access guide](https://support.google.com/chrome/answer/1649523)
for connection authentication and host setup.

## Contributing and licences

See [CONTRIBUTING.md](CONTRIBUTING.md) for local checks and change expectations.
The code and original branding sources use the MIT licence. The bundled Manrope
font is distributed under its own [SIL Open Font Licence](assets/branding/source/OFL.txt).
Telynd is an independent project and is not affiliated with Google or Apple.
