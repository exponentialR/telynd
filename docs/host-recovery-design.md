# Platform-aware host recovery

Decision, 24 October 2026. Implements the shared contract in #15, under #14.

The Telynd client remains a Mac app. Google Chrome Remote Desktop owns the
screen connection and Google authentication for Linux, Mac and Windows hosts.
Selecting an operating system is a setup hint; each adapter verifies its actual
OS and service identity before changes. Old desktops decode as `unknown`, with
their saved links, IDs, SSH details and launch evidence preserved. Old SSH
desktops retain Linux discovery; no migration contacts a host.

## Recovery and transport

| Host | Automatic mechanism | Setup/control | Evidence |
| --- | --- | --- | --- |
| Linux/systemd | Existing fixed per-account timer/helper | Explicit SSH with verified host keys; one-time sudo | Live bounded read-only SSH check |
| macOS | User launch agent, every 120 seconds, maximum three starts per 30-minute window | Kit run as the signed-in desktop user, no sudo | Manually exported/imported snapshot |
| Windows | Service Control Manager failure actions: restart after 60s, after 120s, then none; failure count resets after a quiet day | Kit run locally; explicit administrator PowerShell for policy changes | Manually exported/imported snapshot |

There is no new network listener, hosted service, stored account password or
generic privileged command endpoint. Host-local recovery operates without the
controlling Mac being open. Mac recovery needs an Aqua login and the existing
Google launch job to be loaded; it does not recover before login or bootstrap
an absent Google job. Windows recovers service failures, not a successful
orderly stop. Its existing native restart policy is recorded before an optional
bounded policy is applied. The native failure-on-non-crash flag is left intact.

Chromium already ships a Windows restart-on-crash policy. Adding another timer
would obscure ownership and risk fighting the OS. The Mac launch plist inspected
here has RunAtLoad but no KeepAlive; a separate user agent can request an
idempotent start of an enabled, stopped job, without changing Google's plist or
issuing a force-kill restart. Native behaviour and version differences remain
part of real-host validation, not assumptions of universal compatibility.

## Status contract

Linux retains its existing `TELYND:key=value` SSH protocol for compatibility.
Mac/Windows export JSON schema 1: `desktopID`, actual `platform`, `osVersion`,
`architecture`, Unix UTC `checkedAt`, `service`, `enablement`, `installation`,
`recovery`, `permissions`, and action `outcome`. `LocalHostReport` bounds size,
validates enumerations, rejects a mismatched computer/selected OS and future
timestamps. The importer opens a bounded regular file without following links;
named pipes, directories and other special files are refused before reading. Windows PowerShell UTF-16 output is decoded before JSON validation.

Imported reports are user-supplied data, not authenticated identity or live
status. They cannot supply commands or enable Mac-to-host mutations. The UI
labels their provenance, retains the host timestamp, expires evidence after
five minutes and clears it on relaunch or target/key/platform edits. Privacy
permissions remain unknown unless separately reviewed on the host. A service
observation never verifies a Google session. Reporting a verified Telynd
installation is distinct from proving Google registration or permission access.

## Ownership and recovery safety

Mac installation touches only the current user's `TelyndRecovery` directory and
`com.telynd.recovery` launch agent. It refuses root execution, unsafe ancestors,
symlinks, hardlinked owned files and unrecognised drift. The ledger hashes the
helper/agent; a failed bootstrap is retryable, incomplete/unrecognised writes
require review. A new script revision requires explicit verified uninstall.
The agent checks Google's root-owned installation, signed Google team identity,
enablement marker and launchd disablement before every start. Google config and
credentials are never read. Deliberately disabled, running, transitioning,
missing-session and throttled jobs are left alone. Disabling the agent persists across logins; explicit installation re-enables it.
A stale mutation lock fails
closed; review it manually after interruption. Telynd does not bypass TCC or SIP.

Windows checks the fixed `chromoting` service, signed Google executable under
Program Files, local-system account, file/registry ancestry and service DACL.
Only administrator/SYSTEM/TrustedInstaller protected paths are accepted; reparse
points and unrecognised writable installations are refused. The private
ProgramData ledger records original and desired failure actions and service
image before mutation. An exclusive file lock serialises actions. Recognised
prepared state supports retry; third-party drift stops setup/removal. Disable
restores the previous policy; uninstall restores it and removes the ledger.
Neither action changes Google start mode, registration or passwords. A manually
requested start checks current disabled/stopped state; it is not unattended
orderly-stop recovery. Product scripts expose no configurable service target.

## Packaging and evidence boundaries

The Mac app bundles the source kits and exports only the selected platform's
fixed files plus instructions/checksums. Kits are unsigned developer source,
not public installers. App signing would cover bundled files; standalone Mac
helper distribution and Windows script signing/SmartScreen still need their
own reviewed delivery path. Do not recommend ExecutionPolicy bypass, quarantine
removal, disabling Defender or widening firewall access.

The implementation is testable with isolated file/command providers and a real
synthetic Windows SCM service. That does not validate actual Google hosts,
privacy approval, all OS versions or novice installation. #16/#17 retain their
external packaging/real-installation prerequisites; #18 and Linux pilot #13
track operational evidence. #11 tracks the Mac client signed download.

## Primary evidence inspected

- [Google: supported remote host platforms](https://support.google.com/chrome/answer/1649523).
- [Chromium macOS constants](https://github.com/chromium/chromium/blob/main/remoting/host/mac/constants_mac.cc)
  and [launch plist](https://github.com/chromium/chromium/blob/main/remoting/host/installer/mac/LaunchAgents/org.chromium.chromoting.plist).
  A local installed launch plist and Google Team ID were inspected read-only;
  strict signature verification refused a damaged sealed subcomponent. No repair,
  registration change or private Google configuration read was performed.
- [Chromium Windows installer](https://github.com/chromium/chromium/blob/main/remoting/host/installer/win/chromoting.wxs):
  fixed `chromoting` service, `remoting_host.exe`, LocalSystem and existing restart actions.
- [Microsoft failure actions](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/ns-winsvc-service_failure_actionsa)
  and [non-crash failure flag](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/ns-winsvc-service_failure_actions_flag).
- [Apple Remote Desktop privacy permissions](https://support.apple.com/en-gb/guide/mac-help/mchle046574e/mac).

Sources checked on the decision date. Installed service layout and policy are
verified at runtime; upstream `main` links can change.
