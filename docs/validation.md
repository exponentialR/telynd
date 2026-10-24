# Onboarding validation record

Validation date: 24 October 2026. This is engineering verification by the
implementer, including self-review. It is not a study of independent novice
users and does not establish usability timings or a live Google connection.

## Automated checks

Local security-update results: 20 Swift tests passed; Python discovers 28 tests
(27 passed and one flock test skipped on macOS). Linux runs all 28 and the
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
- `tests/linux-authorisation.sh` uses a disposable Linux account and actual
  shell execution, key tools, file permissions and locks. It covers hostile
  comments, existing restricted entries, missing final newlines, concurrent
  retries and symlink/hardlink refusal. It also runs the actual Mac wrapper's
  fixed remote command through a local transport adapter into that account.
  This verifies the command/data boundary without a live SSH server or password.
  It passed locally in a disposable Debian container with networking disabled
  and no host-folder mounts; CI repeats it on Ubuntu.
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
