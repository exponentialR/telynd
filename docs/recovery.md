# Optional Linux recovery and SSH

Recovery supports a reachable Linux account with systemd and an existing
`chrome-remote-desktop@USERNAME.service`. The account needs administrator
approval during installation. Bash, sudo, install, flock, stat, sha256sum,
visudo and systemctl must be available at the expected system locations.
An existing Tailscale route can be used; Tailscale is not required. The editor
accepts `user@hostname` and `user@IPv4`. Explicit ports and IPv6 literals are
not supported in the address field; custom ports can be set for a hostname in
`~/.ssh/config`.

For a normal interactive login, choose **Start SSH** on the computer’s row.
The terminal opens inside Telynd and uses its saved target and key. **… → SSH
settings…** edits these details independently of recovery or Chrome. See
[the terminal guide](quick-start.md#open-an-ssh-terminal). Recovery installation
and authorisation still open macOS Terminal for their separate approvals.

## Set up access

Open a computer's **… → Recovery settings…** and select **Linux**. Telynd
checks previously saved access automatically when this screen opens. New setup
has three steps. The header shows the current step and all three stages.
**Enable automatic recovery…** stays visible at the bottom, with the reason
it is locked until current access and installation requirements pass:

1. Follow [guided pairing](pairing.md): download and install the desktop helper inside
   the Ubuntu/Debian remote desktop, approve SSH preparation if needed and bring its setup
   card back to this Mac. Confirm the PC, choose **Check this computer**, then
   **Use this computer**. Telynd selects a listed address whose public host key
   matches the card; it does not authenticate or accept trust. Existing saved
   connections skip pairing. Advanced users can expand **Advanced: enter
   connection details** to enter a username/address or paste one simple
   `ssh user@computer` command. SSH options and custom ports are not accepted.
2. Choose **Approve this Mac…**. Telynd creates a key pair if both files are
   absent, or reuses the selected pair. New connections normally use
   `~/.ssh/telynd_ed25519`; existing SSH settings retain their previous key.
   Existing or incomplete key files are never overwritten. Choose a passphrase,
   compare the host fingerprint against a trusted record and enter the Linux
   login password directly in Terminal when requested. macOS Keychain handles
   supported passphrase storage; Telynd does not choose or save a password.
3. Return to Telynd. It reads the action's receipt and checks current access.
   Once the host's supported Chrome service and required tools are verified,
   **Enable automatic recovery…** offers the separate administrator-approved
   installation. Already-enabled recovery is shown without repeating setup.

**Check access** skips authorisation and performs a bounded read-only
check. Key selection, **Start SSH**, detailed status, manual
recovery, disabling and uninstalling are under **Advanced settings & diagnostics**.
Editing the target or key makes the old verification inapplicable until checked.

For the advanced manual route, SSH must already be enabled and reachable.
The desktop helper can enable it locally after administrator approval, but
Telynd cannot bootstrap a computer through a connection that does not exist.
It cannot infer SSH access from a Google URL or grant access without an existing
login method. The normal pairing route supplies these details without commands;
the following command-based fallback is for advanced users. The in-app help explains Ubuntu's Secure Shell settings and links
[Ubuntu's OpenSSH guide](https://ubuntu.com/server/docs/how-to/security/openssh-server/).
It also provides fixed read-only commands to show the remote username,
addresses and public host-key fingerprints. **Copy Linux details command**
provides one command to run in a Terminal on Linux through an existing Google
session or physical access. It prints a labelled username and ready-to-copy
`ssh user@address` lines. If the Tailscale CLI reports an IPv4 address, that
route is shown separately; use it only when both devices already share that
Tailscale network. See [Tailscale's connectivity guide](https://tailscale.com/docs/how-to/connect-to-devices).
The other candidates can include virtual interfaces and are not proof of
reachability. Choose the network shared with this Mac, or ask the administrator.
Copy just one SSH line, then click **Paste SSH address** to fill both fields.
IPv6 is omitted because this SSH form does not support it. The separate SHA256
fingerprints identify the server: compare the matching key type during the SSH
trust prompt; do not put them into either address field. If password login is disabled
and no key already works, ask the administrator to authorise this Mac. Telynd
does not enable password authentication or open firewall/router ports.

A changed host fingerprint requires investigation through a trusted route.
Telynd leaves host checks enabled; do not blindly remove the old trust record.
Authorisation adds only the selected public key to the specified Linux account
and then verifies non-interactive account access. Recovery is installed separately.

During the confirmed **Approve this Mac** action, before agent or host
changes, OpenSSH validates a single public-key snapshot. It derives the public
identity from the selected private key and compares it with that snapshot. A mismatch or
unreadable private key stops setup. Protected keys may prompt for their
passphrase during this check and again during Keychain setup. Routine checks
use existing Keychain/agent access.

Terminal then unlocks the key through SSH/macOS Keychain and sends the public
key as data to a fixed Linux-side installer over SSH. Linux login passwords
are typed directly into SSH. Telynd does not call `ssh-copy-id` or evaluate key
filenames or comments as shell text.

A new strict, non-interactive connection then verifies **SSH account access
using your SSH configuration**. Additional configured identities may take part;
this result does not identify which key authenticated. The app and Terminal
state that scope explicitly. Repeating authorisation recognises the key
even when its existing entry has a different comment or access restrictions;
it preserves that entry and never adds an unrestricted duplicate. New entries
contain only the key type and public material. This action does not install
recovery.

This installation step requires Linux with `flock`, `stat`, `awk` and standard
shell tools. A private `.ssh/.telynd-authorise.lock` serialises concurrent
attempts. The installer uses a private `.ssh` directory and `authorized_keys`
file, preserves unrelated entries, and refuses symlinked directories or
symlinked/hardlinked files. A failed or interrupted attempt may have created
these paths; return to Telynd and recheck readiness. Standard Ed25519, RSA,
ECDSA and OpenSSH security-key public keys are supported; certificates and
files containing authorised-key options require separate administrator setup.
Missing tools, lookup errors, unexpected lookup output and final-byte read
failures stop installation before any key is appended. Existing restricted
entries are preserved when their contents cannot be checked.

First-contact authorisation explicitly prompts for host-key trust even if the
user's SSH configuration disables checking. Subsequent automated connections
require an already trusted host. Telynd disables agent, X11 and port forwarding,
local commands and SSH connection sharing for these connections, including the
verification step. Hostname and routing configuration can still be inherited;
an SSH agent can authenticate locally without being forwarded to the host.

After readiness identifies the supported service, **Enable automatic recovery** explains
the scope and opens Terminal for administrator approval. The installer validates
a narrow sudoers rule, installs root-owned components, records hashes, and
checks permissions, timer enablement and timer activity. Return to Telynd; the guided flow checks current readiness automatically. Terminal outcomes are stored in private receipts;
an interrupted operation may have made partial changes and is never described
as rolled back.

## What the timer does

Every two minutes, the fixed helper checks that account's Chrome host service.
It starts an **enabled** service only when inactive or failed. Active, disabled,
transitioning and unknown states are left alone. A private root-owned lock
prevents concurrent starts. The timer continues while the Mac or Telynd is
closed. It does not enable a disabled Chrome service.

This does not detect Google's online state. A running process with expired
Google authorisation, a network failure, sleeping hardware or a hung service
can still be unavailable. Telynd does not automatically restart an active
service in those cases. Google's account and PIN remain in Chrome.

## Installation record and permissions

All paths are scoped to the desktop account's numeric UID:

| Component | Path | Owner/mode |
| --- | --- | --- |
| Recovery helper | `/usr/local/libexec/remote-desktops-recover-UID` | root / 0755 |
| Read-only verifier | `/usr/local/libexec/remote-desktops-status-UID` | root / 0755 |
| Unit and timer | `/etc/systemd/system/remote-desktops-recovery-UID.{service,timer}` | root / 0644 |
| Sudo rule | `/etc/sudoers.d/remote-desktops-recovery-UID` | root / 0440 |
| Record | `/var/lib/telynd/recovery-UID/` | root / 0700; files 0600 |
| Runtime lock | `/run/remote-desktops-recovery-UID/` | root / 0700 |

The sudo rule permits only those two fixed helpers **with no arguments**. It
does not grant a shell or arbitrary service control. The status helper reads
its ownership record and hashes; the recovery helper controls only its fixed
Chrome unit. Password-free routine checks and recovery depend on successful
one-time SSH and administrator setup.

Every ancestor of these directories must be a real, root-owned directory with
no group or other write permission, including `/usr/local`, `/usr`, `/etc`,
`/var` and `/run`. Installation checks the chain from `/` before any root
write. Readiness, removal and the installed helpers also check ancestry.
Symlinked layouts and shared writable parents are refused; the installer does
not change their ownership or permissions. Ask the administrator to assess an
unsupported layout. Reinstall existing recovery components to receive these
helper checks; updating the Mac app alone does not replace Linux components.

A recognised partial installation can be retried. Surviving files must match
the recorded hashes; changed content requires administrator review. An older
Telynd prototype without an ownership record is deliberately not claimed or
overwritten automatically. Ask the host administrator to inspect and remove
its exact old files before reinstalling.

## Disable, uninstall and troubleshoot

**Disable timer** stops and disables Telynd's timer, then checks both states.
**Uninstall recovery** verifies ownership, modes and hashes before removing
only the recorded Telynd components. Both are explicit Terminal actions with
administrator approval. Chrome registration, the Chrome unit and SSH keys are
preserved. Modified or incomplete removal records require review; no unrelated
files are deleted. The empty private runtime-lock directory may remain until
reboot. Removing an SSH authorisation is a separate administrator task: identify
the exact public key in that account's `authorized_keys` before changing it.

| Observation | Next step |
| --- | --- |
| SSH unreachable | Wake the computer; check its address and network route |
| Authentication needed | Choose the correct key; authorise SSH access in Terminal |
| Folder permissions need attention | In Linux Telynd Setup, choose Check again and review Fix folder permissions; unexpected ownership or links need administrator review |
| Authorisation ran, key login still fails | Check Linux folder permissions first; if safe, ask the administrator to review SSH policy |
| New/changed identity | Verify the fingerprint through a trusted route |
| No systemd / non-Linux | Keep connection-only access |
| Chrome service missing | Configure Google's Linux host for this desktop account |
| Missing tools | Ask the host administrator to install the listed prerequisites |
| Recovery unverified/partial | Inspect the receipt and root record; retry a recognised install |
| Permission/content drift | Administrator review before replacing or removing files |
| Stale result | Recheck; observations expire after five minutes and reset on relaunch |
| Service active, Google offline | Diagnose Google sign-in, network and Chrome separately |

If Terminal closes before completion, the app reports failure, interruption or
unknown completion. Remote cleanup cannot be guaranteed after a lost SSH
connection; a private `/tmp/telynd-setup.*` script may remain. Do not assume a
successful receipt is current status: always recheck.
