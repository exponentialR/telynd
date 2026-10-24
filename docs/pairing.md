# Guided Linux pairing (developer preview)

The normal setup path should not require a user to interpret IP addresses,
choose SSH key files or type discovery commands. Telynd's Linux desktop helper
supplies the connection details, and the Mac checks for a matching route.

## What the user does

1. **On this Mac:** add the computer through Google's picker and choose
   **Linux → Save & set up SSH…**, or open **Recovery settings…** later. Choose
   **Copy Linux download link**, then **Open remote desktop**. SSH is not
   required for these steps: Google's working connection is the initial route.
2. **Inside the Linux remote desktop:** open a web browser on that PC, paste the
   copied link into its address bar and press Enter. The installer downloads
   directly to the Linux PC. Open it from that browser's Downloads list, choose
   **Install** in the graphical software installer and approve installation.
   Find **Telynd Setup** in that PC's applications and open it. Package
   installation adds the helper and dependencies; it does not itself enable SSH.
3. **Still on Linux:** if the helper offers **Enable SSH…**, choose it and
   approve the administrator prompt. It installs OpenSSH Server if needed and
   starts/enables its service. Existing authentication and firewall settings
   govern where it accepts connections. It does not change password-login
   policy, VPN configuration or authorised keys, or open firewall/router ports.
   When ready, choose **Copy setup card**. The helper collects the login name,
   addresses and public SSH identity; the user does not have to find them.
4. **Back in Telynd on this Mac:** choose **Continue to paste setup card**,
   then **Paste setup card**. A setup card is
   the connection information copied by the Linux helper. Keep the helper open
   until pasting because some Linux clipboard managers retain data only while
   the source app runs. If copied text does not reach this Mac, use the
   file-transfer alternative below.
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

## If direct download or shared clipboard is unavailable

Expand **Download or clipboard not working?** in Telynd.

- To transfer the installer: choose **Save installer on this Mac…** and select
  a folder you can find. In the connected Google remote session, expand its
  right-hand side panel and choose **File transfer → Upload file**. Select
  the saved `.deb`, then find and open the uploaded file on Linux. Transfer
  availability depends on the session and organisation policy; ask the PC's
  administrator to provide the installer if upload is unavailable.
- To transfer the setup card as a file: choose **Save setup file…** in the Linux
  helper. In Google's remote-session side panel choose **File transfer →
  Download file** and select that file. Back in Telynd on the Mac choose
  **Open setup file…** and select the downloaded file before its 15-minute expiry.

The normal route uses the existing Google session and a direct download on
Linux. It does not require SSH in order to install SSH, or require moving an
installer from the Mac. The user opens the download on Linux and approves
installation; Telynd does not silently install or remotely launch it.

The preview download comes from Telynd's public GitHub repository at a fixed
commit. Its URL is supplied only when the bundled installer matches the pinned
SHA256. This was checked against an actual HTTPS download; it is not a mutable
latest link or a signed public release. The Linux PC needs HTTPS access to that
host and its package repositories. Public hosting availability and local
organisation policy can still prevent download.

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
