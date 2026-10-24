# Optional Linux recovery and SSH

Recovery supports a reachable Linux account with systemd and an existing
`chrome-remote-desktop@USERNAME.service`. The account needs administrator
approval during installation. Bash, sudo, install, flock, stat, sha256sum,
visudo and systemctl must be available at the expected system locations.
An existing Tailscale route can be used; Tailscale is not required. The editor
accepts `user@hostname` and `user@IPv4`. Custom SSH ports and IPv6 literals are
not yet supported.

## Set up access

Open **Recovery settings** on a computer's card. Enter its SSH account/address
and choose an existing private key with a matching `.pub` file. If you need a
key, choose an unused path and **Create a new SSH key**. Choose a passphrase in
the standard SSH prompt. Existing keys are never overwritten; Telynd does not
choose an empty passphrase or store one.

**Save and check readiness** performs a bounded, non-interactive SSH check.
It reads service and installation state; it does not install anything, add
keys or start services. Its messages distinguish missing network access,
authentication and host identity problems. When first trusting a host, compare
its fingerprint against a trusted record using **SSH Terminal**. A changed
host identity needs investigation; do not bypass the warning or blindly delete
a known-host record.

**Authorise SSH access** is a separate, confirmed action. Terminal unlocks the
key through SSH/macOS Keychain, validates a single public key with OpenSSH and
sends it as data to a fixed Linux-side installer over SSH. Linux login passwords
are typed directly into SSH. Telynd does not call `ssh-copy-id` or evaluate key
filenames or comments as shell text.
The selected key is then checked with a new non-interactive connection before
authorisation is reported as ready. Repeating authorisation recognises the key
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

First-contact authorisation explicitly prompts for host-key trust even if the
user's SSH configuration disables checking. Subsequent automated connections
require an already trusted host. Telynd disables agent, X11 and port forwarding,
local commands and SSH connection sharing for these connections, including the
verification step. Hostname and routing configuration can still be inherited;
an SSH agent can authenticate locally without being forwarded to the host.

After readiness identifies the supported service, **Install recovery** explains
the scope and opens Terminal for administrator approval. The installer validates
a narrow sudoers rule, installs root-owned components, records hashes, and
checks permissions, timer enablement and timer activity. Return to Telynd and
recheck current readiness. Terminal outcomes are stored in private receipts;
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
