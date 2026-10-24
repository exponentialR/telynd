# Guided Linux pairing (developer preview)

The normal setup path should not require a user to interpret IP addresses,
choose SSH key files or type discovery commands. Telynd's Linux desktop helper
supplies the connection details, and the Mac checks for a matching route.

## What the user does

1. Add the computer through Google's picker and choose **Linux → Save & set up
   SSH…**, or open its **Recovery settings…** later. Keep its working Google
   remote session open, or use the PC in person.
2. Choose **Open remote desktop** to reach it without leaving setup, then
   **Get setup helper…**. Transfer the exported `.deb` file to that Linux
   PC using a file-transfer method you already trust. Open it with its graphical
   package installer, approve installation and launch **Telynd Setup** from the
   applications menu. Package installation adds the helper and dependencies;
   it does not itself enable SSH.
3. The helper checks the PC. If SSH is stopped or missing, choose **Enable SSH…**
   and approve the Linux administrator prompt. This installs OpenSSH Server if
   needed and starts/enables its service. Existing authentication and firewall
   settings govern where it accepts connections; no firewall/router ports,
   password-login policy, VPN configuration or authorised keys are changed.
4. Choose **Copy setup card**. Return to Telynd on the Mac and choose **Paste
   setup card**. Keep the helper open until pasting because some Linux clipboard
   managers retain data only while its source app is running. If shared
   clipboard is unavailable, choose **Save setup file…**, transfer that file
   back and use **Open setup file…** instead.
5. Confirm the displayed PC/account came from your intended machine, then choose
   **Check this computer**. Telynd tries only the card's supplied addresses,
   preferring an existing Tailscale address when reported, and looks for a
   matching public SSH host key. **Use this computer** fills the details after
   a match. Nothing has logged in or accepted host trust at this point.
6. Choose **Set up SSH access…**. Terminal handles one-time host trust,
   passphrase and Linux login prompts. The card's public fingerprints are
   available to compare against the first trust prompt. An administrator must
   provide initial key access if password login is disabled. After access and
   supported Chrome-service readiness pass, **Enable automatic recovery…**
   offers the separate administrator-approved timer installation.

No passwords or private keys travel in the setup card. Routine checks and
recovery use the existing restricted helpers only after successful setup.
The connection-only option remains available throughout.

## Supported conditions and limits

This first helper targets Ubuntu/Debian graphical desktops with systemd,
Python 3/Tk, PolicyKit and IPv4. Dependencies are declared in the Debian package.
The system must have a configured graphical package installer ([Ubuntu App Center supports downloaded debs](https://ubuntu.com/desktop/docs/en/24.04/explanation/snap-and-deb-packages/)) and administrator
approval agent. Other Linux distributions and headless PCs use the advanced
manual route. Mac/Windows retain their separate host-local developer kits.
Actual distribution-specific package-store UX and a fresh non-technical-user
pilot remain acceptance work; a disposable runner is not that pilot.

Both devices need a route that permits SSH, through a shared network or an
existing private VPN. The helper does not create a cross-network route or open
ports. If no matching route is found, check wakefulness and shared connectivity
or ask the network administrator. Identity comparison uses public keyscan
output; the subsequent SSH handshake and explicit trust decision remain the
host authentication boundary. Pairing never bypasses a changed known-host key.

A card expires after 15 minutes. Copy a fresh one after expiry or network
changes. It contains the normal desktop username, hostname, up to six IPv4
addresses and up to three public SSH host keys. Treat it as private network
metadata, and obtain it through your trusted remote session or file transfer.
Its freshness timestamp limits reuse; it is not a server-issued token or a
cryptographic signature. Telynd contacts no address before the explicit check,
limits each probe to four seconds and stops further probes on cancellation.
It does not write host trust, authenticate or run remote commands during pairing.

The helper's SSH preparation is a fixed, root-owned action requiring local
administrator approval each time. It takes no caller-supplied arguments and
runs Python in isolated mode with a fixed environment. Package installation
has no SSH-changing maintainer scripts. The bundled package is reproducibly
built from `linux-helper/` with `scripts/build_linux_helper.py`; CI checks its
contents, permissions and source equality before the Mac signing pipeline
accepts it as a resource. This remains an unsigned developer-preview package.

Removing the helper through the Linux package manager does not disable OpenSSH
that you approved or remove authorised keys. Disabling SSH is a separate
administrator action and may disconnect existing users. Telynd's recovery timer
also has separate Disable and Uninstall controls in the Mac app.
