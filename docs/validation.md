# Onboarding validation record

## Cross-platform recovery implementation, 24 October 2026

The #14 work extends the existing Mac client with platform selection and Mac/
Windows host-local developer kits. It does not establish signed standalone host
installation, novice usability or a working session on registered Google hosts.
The earlier Linux/onboarding evidence below remains scoped to that implementation.

| Environment | Evidence | Practical limit |
| --- | --- | --- |
| Local macOS 26.4.1 / ARM64 | Swift migration/report tests; Mac file/command fixtures; native SwiftUI Windows kit/report-import journey | Synthetic identities and reports; no personal host mutations |
| CI macOS runner, reported 26.6.2 / 25G83 / ARM64 | Real launchd bootstrap, idempotent start, active preservation, deliberate disablement, persistent Telynd disable and verified removal against an ad-hoc signed synthetic host | Fixture replaces Google's identity/root-ownership provider; no Google registration or privacy approval |
| CI Windows Server 2025 / 10.0.26100 / AMD64 | Real SCM service, native policy/security-descriptor queries, policy apply/read-back, retry, drift refusal, ACL refusal, restoration and bounded crash recovery | Synthetic service; Only the synthetic root and signature query are substituted; production host validation runs against real file, registry and service ACLs; no Windows 11 Google-host installation |
| Windows PowerShell 5.1 and PowerShell 7 on that runner | Same native service lifecycle under both runtimes | Does not establish every desktop Windows version or enterprise policy |
| Ubuntu/systemd CI | Existing real Linux install/authorisation/ancestry/removal regression coverage | Synthetic Chrome service; real Google pilot remains #13 |

The first complete passing cross-platform PR run is
[Checks 40100653327](https://github.com/exponentialR/telynd/actions/runs/40100653327)
at source `ccefab4f944bc9337af1021f5c58f423cd674f1f`. Subsequent commits refine
UI copy, bounded regular-file report reads, native-test output isolation and
additional service-security coverage; inspect the PR's current checks before merging.

Current local coverage: 30 Swift tests and 42 discovered Python tests (41 run on
macOS, one Linux-only flock test skipped; Linux skips ten Mac-only tests).
Windows and native launchd tests are separate disposable CI scripts. File
fixtures replace fixed command/path providers only in copies; product scripts
have no testing bypass parameter or configurable service target.

Native UI inspection used a debug app under a temporary directory, with three
synthetic desktops. Mac and Windows recovery sheets show local-kit instructions
without SSH setup. Importing the Windows fixture displays crash-only scope,
host timestamp, unknown live identity and Google availability; no Linux timer or
SSH success is inferred. Layout was visually inspected. These checks do not
constitute a novice study or full VoiceOver walkthrough. The normal installed
app was not restored and the user's backed-up desktops/settings remain separate.

Self-review corrected persistent Mac disablement, foreign launch-label refusal,
fail-closed enablement vocabulary across launchctl versions, unknown service
states, safe parent ACL interpretation, PowerShell optional-string marshalling
and atomic ledger replacement. Completed Mac removal no longer fails merely
because Google's installation is unhealthy. Read-only inspection of an existing
Google Mac bundle refused a damaged sealed subcomponent; it was not repaired or
used for a live recovery test. This is implementer self-review, not an independent
security audit.

### Critical-review follow-up

The follow-up fixes preserve Windows hosts intentionally stopped by Google:
Manual and Disabled modes remain stopped, and setup/manual recovery require
Automatic mode. The Windows fixture now executes the production host validator
with only its synthetic installation root/signature provider substituted. It
exercises rejected launch paths/accounts, invalid signatures/publishers, writable
executables, registry keys and service DACLs, then verifies safe restoration.
This exposed and corrected a real Windows PowerShell 5.1 registry-provider lookup
failure that the earlier whole-validator substitution had hidden.

The Mac kit uses a native descriptor lock that releases after process death;
fixtures prove concurrent refusal, partial readiness while busy and recovery
after SIGKILL. Legacy directory locks remain fail-closed with partial readiness.
Unsupported native locking is refused before helper/agent installation. Review
also found that malformed retry state could block ticks while reporting ready:
checks now report partial readiness, and state updates use an atomic replacement.
Local follow-up validation passed 30 Swift tests and 42 discovered Python tests
(41 run on macOS, one Linux-only skip). Native Windows and launchd verification
remain separate disposable CI checks; consult the PR's final source checks.

### Real-host evidence still required

Keep #16/#17 open for real installed Google hosts and their signing/distribution
criteria, #18 for Mac/Windows operational validation, #13 for the Linux pilot
and #11 for signed Mac client browser-download testing. Before a disruptive
test, approve the specific non-critical host and establish independent access.
Record the client/helper revisions, OS/architecture, Google version, actual
permissions/setup prompts, failure trigger, start attempts and separately
confirmed Google reconnection. Repeat with the controlling Mac closed; verify
intentional disablement, active-session preservation, updates and removal.
Restore the agreed host state. Publish only sanitised outcomes and failures.

Windows orderly-stop recovery is explicitly excluded from automatic crash
recovery. Mac recovery before login, automatic privacy approval, Intel/earlier
Mac runtime support, Windows desktop hardware coverage, and ordinary standalone
signed kit installation are unverified. Imported snapshots do not authenticate
the host or current state and cannot authorise remote mutations.

---

Validation date: 24 October 2026. This is engineering verification by the
implementer, including self-review. It is not a study of independent novice
users and does not establish usability timings or a live Google connection.

## Automated checks

Local security-update results: 20 Swift tests passed; Python discovers 32 tests
(31 passed and one flock test skipped on macOS). Linux runs all 32 and the
systemd integration.

- Swift core tests cover connection-only and legacy models, strict supported
  links, corrupt/future settings, duplicate identities, private atomic saves,
  migration precedence, resumable guide/draft data, ambiguous/missing profiles,
  stale evidence, SSH failure categories and bounded process execution.
  Incomplete output and failed SSH transport cannot establish readiness.
- Python fixtures cover unsupported OS/systemd, missing/stopped services,
  read-only checks, active/failed/disabled/transitioning services, failed starts,
  helper argument rejection, Linux flock concurrency, separate authorisation,
  missing/existing keys, explicit passphrase prompting, failed upload and
  distinct authentication/verification receipts. These use command stubs, not
  real login passwords. macOS skips flock concurrency; Linux executes it.
- `tests/linux-integration.sh` runs only in an explicitly disposable systemd
  environment. It creates a synthetic account and sleep-based Chrome unit,
  tests rejection of foreign files, injected interruption between copies,
  retry, root read-back, disabled-host preservation, real sudoers argument
  restrictions, denial of unrelated sudo commands, idempotent start, permission
  drift, a missing owned component, disable and repeated uninstall. The Chrome
  unit and its PID survive removal. Its temporary broad administrator rule is
  test-fixture infrastructure and is removed before checking the product's
  narrow permissions; production installation never creates that rule.
- SSH tests use real offline `ssh -G` resolution against deliberately unsafe
  defaults. Both Swift readiness and shell actions override host trust,
  forwarding, local commands and multiplexing. Authorisation fixtures verify
  first-contact prompting and a subsequent strict fresh connection.
  Swift and shell policy tests also pass paths containing spaces, quotes,
  backslashes, tabs and comment characters through the real offline SSH parser,
  checking that the selected identity is preserved.
- Authorisation tests use real local key validation and offline OpenSSH option
  parsing with filenames containing quotes, backslashes, spaces, command
  substitutions and backticks. Key comments remain stdin data, and malformed,
  multiple or oversized keys fail before SSH. The Keychain/transport adapters
  do not contact real accounts. Mac CI runs these cases too.
  Mismatched pairs and invalid private keys stop before agent or SSH calls.
  Encrypted Ed25519, RSA and ECDSA fixtures exercise OpenSSH's standard passphrase
  reader through a fixture askpass program. An additional configured identity
  remains visible in real SSH option resolution, and success wording reports
  account access with that limitation.
- `tests/linux-authorisation.sh` uses a disposable Linux account and actual
  shell execution, key tools, file permissions and locks. It covers hostile
  comments, existing restricted entries, missing final newlines, concurrent
  retries and symlink/hardlink refusal. It also runs the actual Mac wrapper's
  fixed remote command through a local transport adapter into that account.
  This verifies the command/data boundary without a live SSH server or password.
  It passed locally in a disposable Debian container with networking disabled
  and no host-folder mounts; CI repeats it on Ubuntu.
  Fault cases cover a missing lookup tool, non-zero lookup status (including
  misleading stdout), empty/unexpected output and failed final-byte reads.
  A real unreadable-file case verifies restricted contents and permissions are
  unchanged. Test-only copies substitute the command path for adapters; the
  production installer retains its fixed system path and has no fault flags.
- Deterministic host-check state tests deliver superseded completions while a
  newer request is busy and after it has completed. They also cover returning
  to the original target, discarding the current request, retry and independent
  desktops. These exercise the state component used by AppStore without live
  SSH or timing-dependent sleeps.
- Release tests reject off-main commits, moved tag objects and insufficient
  protection. Archive tests reject traversal, links, duplicate or extra files,
  resource changes, preview metadata and excessive size. They use synthetic
  binaries; separate Mac CI validates the real ad-hoc app archive and signature.
- The real directory guards passed in a disposable Linux container without
  host mounts or networking, covering writable/non-root-owned ancestors,
  symlinks, missing directories and invalid path forms. Systemd integration
  adds actual installer, readiness, helper and uninstaller refusal when
  `/usr/local` becomes writable.

The disposable Debian 13.4 ARM64 VM passed that integration script, including an
interrupted upgrade with mixed old/new components and refusal of content drift, and all Linux
recovery decision tests including concurrency, and installation/readiness
read-back. It had no host-folder mounts. This validates real systemd/sudoers
behaviour against the synthetic service, not Google's registered host binary.
GitHub Checks repeats the integration on an Ubuntu runner. The first CI run
found a test-fixture assumption that `/usr/local/libexec` already existed; the
fixture now prepares that directory before placing its synthetic foreign file.

## Native Mac journey

Local environment: macOS 26.4.1 (25E253), ARM64, Swift 6.3.3. A debug-only app
used an isolated Application Support fixture with synthetic `example.test`
accounts. Chrome launches were simulated and SSH actions were blocked. Release
builds ignore the preview configuration and use the normal private settings.

Observed through the native interface:

| Journey | Outcome |
| --- | --- |
| Empty settings | Welcome guide opens; SSH is not requested |
| Multiple profiles | Existing profiles listed; explicit selection enables Continue |
| Signed-out profile | Label directs user to Chrome sign-in; refresh offered |
| Computer without SSH | Name + Google picker saved as connection-only |
| Invalid Google link | Save remains disabled |
| Unconfigured Google host | Setup guidance and Google's picker are available |
| Close at connection step, quit/relaunch | Saved computer/profile and connection step resume |
| Simulated Chrome launch | Launch recorded; no connected-session claim |
| Defer recovery | Guide finishes and connection-only card remains usable |
| Relaunch after completion | No forced first-run sheet |
| Existing installed app | Both saved desktops unchanged; requested Chrome profile migrated; no forced guide |
| Recovery settings | SSH details and key path separate from connection fields; unknown states explicit |
| Keyboard | Text-field Tab navigation and visible focus inspected; Return/Escape shortcuts provided |
| Accessibility | Native accessibility tree exposes descriptive field/button names, including named Edit controls |
| Light/dark | Native light welcome/card and dark card/editor inspected for clipping and readable text |

![Synthetic connection-only desktop in dark appearance](images/connection-only-dark.png)

To repeat the isolated UI journey, create a private fixture directory with a
`chrome-state.json` containing only synthetic `profile.info_cache` metadata,
then build using `TELYND_BUILD_CONFIGURATION=debug` and
`TELYND_FIXTURE_DIRECTORY=/absolute/fixture/path`. Set
`TELYND_PREVIEW_APPEARANCE=light` or `dark` to inspect an app-only appearance.
Use a separate output app and quit it before replacing it. Empty fixture
settings start the guide; completed fixtures exercise relaunch. Do not publish
real Chrome profile data or screenshots containing personal host details.

## Review corrections

The final authorisation pass requires a successful explicit presence/absence
lookup before appending and checks the final-byte read independently. Tool
failures cannot add an unrestricted duplicate of a restricted entry. The Mac
wrapper also derives and compares the selected private key's public identity
before agent or network activity. Final connection verification is described
as account access using the user's SSH configuration; additional identities
can participate. It is separate from the local key-pair comparison.

The dependency-level review found that the installed `ssh-copy-id` evaluated
key filenames internally. A harmless isolated marker reproduced substitution
before any network connection. Telynd now removes that dependency from
authorisation: validated public-key text travels only on stdin to a fixed
Linux installer command. Filenames are never inserted into remote commands,
and the installer discards comments without evaluating them. It serialises
updates, preserves existing restrictions and refuses unsafe destination types.
The earlier stub-only setup tests could not establish this boundary; the new
tests exercise real parsing and the real installer under a disposable account.

A further pre-merge pass found unescaped `IdentityFile` configuration values
and a late-completion race after target/key edits. Both Swift and shell policy
now quote and escape the path for SSH configuration syntax. AppStore owns a
request-aware host-check state component: saved target/key edits invalidate the
old request, and only the current request may publish or clear its observation.
Matching target/key strings alone cannot accept an older result after an
A-to-B-to-A edit.

The security review identified four additional issues: writable directory
ancestors could permit replacement of a root-executed helper; initial
`ssh-copy-id` could inherit disabled host checks; background SSH could inherit
agent forwarding or reuse an existing connection; and arbitrary tagged release
scripts could run in the signing environment. The fixes validate full Linux
directory ancestry, impose explicit SSH policy, pin reviewed main-history
source under protection checks and isolate builds from credentialed signing.
The release job treats artifacts as data and executes only trusted workflow-main
validation/signing scripts. GitHub protection configuration and Apple credentials
remain prerequisites; the credentialed release path has not been executed.

Self-review tightened SSH time/output bounds and rejects partial success
protocols, clears observations when the target or key changes, blocks recovery
from unsaved or stale details, and associates Terminal receipts with the exact
saved target/key. A prepared action cannot inherit an old successful receipt.
Root helpers use a fixed system PATH. Recovery requires explicit enabled or
enabled-runtime state; systemd static/indirect/linked states are left alone too. The installer serialises setup operations, verifies surviving recorded files before retry and refuses
unknown files or content drift. Application replacement validates a fresh whole
bundle before swapping it, preventing obsolete resources and Finder metadata
from surviving an update. Settings writes also reapply owner-only permissions
when replacing an older file with broader metadata. Unfinished guide drafts are private and distinct
from saved valid desktops.

## Concrete remaining limits

Missing Chrome and changed/removed Chrome profiles have automated launch-plan
and profile fixtures; Chrome was not uninstalled from the user's Mac to test
that guard. Protected-key unlocking, wrong real passwords and first host trust
remain standard interactive SSH/Keychain operations; fixtures check failure
handling, but no personal account was modified during this validation. Native
accessibility labels were inspected; a complete spoken VoiceOver walkthrough
with a screen-reader user remains useful follow-up validation. Full button Tab
navigation depends on the user's macOS Keyboard Navigation setting.

No Mac Intel runtime or macOS 13–25 runtime was tested. No Google PIN,
sign-in state or active screen session was inspected by the test fixture.
A real registered Google-host end-to-end pilot remains separate from the
controlled systemd installation evidence. No private Alienware/QUB host was
changed. No signed-release/quarantined-download test was performed: Apple
credentials are absent, as recorded in [release preparation](releasing.md).
