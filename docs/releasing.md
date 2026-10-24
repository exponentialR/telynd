# macOS release preparation

Status on 24 October 2026: the maintainer does not yet have an available Apple
Developer signing identity. No signing secrets are configured and **no signed
or notarised public binary has been produced**. The authorised delivery is the
prepared pipeline and recorded prerequisite. Issue #11 remains open for real
signing and the download smoke test.

## Supported and tested combinations

| Combination | Evidence |
| --- | --- |
| macOS 26 / Apple silicon | Local build, core tests and native UI inspection |
| macOS 13–25 / Apple silicon | Build minimum is 13; runtime behaviour untested |
| Intel Mac | Not included in the first binary; no runtime validation |
| Debian 13 / ARM64 / systemd | Disposable VM installer tests against a synthetic unit |
| Ubuntu / systemd | Disposable CI runner integration; inspect current Actions outcome |
| Google remote connection | Browser-owned; synthetic UI tests do not establish a connected session |

Local `build.sh` creates an ad-hoc signed ARM64 developer app. It is not a
substitute for the signed download. The identifier stays
`com.samueladebayo.telynd`; settings remain outside the bundle in Application
Support. Replacing the app must preserve that directory and identifier.

## Maintainer prerequisites

Obtain Apple Developer membership and a Developer ID Application certificate
with its private key through the normal Apple process. Do not put credentials
in issues or source. Configure the `macos-release` GitHub environment, restrict
its deployment branch to `main` and enable required maintainer review before use.
Do not permit protection bypass or self-approval. The trusted workflow and its
validators must first be reviewed and merged into `main`.

Configure two active repository rulesets, with no exclusions or bypass actors:

- A branch ruleset explicitly covering `refs/heads/main` (or all branches),
  requiring at least one approving review, dismissal of stale approvals and
  current `mac-app`, `recovery` and `windows-recovery` status checks with strict update policy.
- A tag ruleset covering `refs/tags/v*` (or all tags), blocking updates and
  deletion. Create version tags only after source review; do not add a bypass
  actor to make existing tags mutable.

Set repository variables `RELEASE_MAIN_RULESET_ID` and
`RELEASE_TAG_RULESET_ID` to their numeric IDs. The pipeline checks their active
rules through GitHub's API and refuses missing or weakened protection. GitHub
hides bypass actors from read-only API callers, so the environment's required
reviewer must separately verify that neither ruleset grants bypass access.
Record that check with the release evidence. No broader API token is needed.
These protections and IDs were not configured when the pipeline was prepared;
release preparation fails closed until they are available.

Provide environment variable `DEVELOPER_ID_APPLICATION` with the approved
certificate's full identity name, and these environment secrets:

- `APPLE_CERTIFICATE_BASE64`: base64 PKCS#12 certificate and private key.
- `APPLE_CERTIFICATE_PASSWORD`: password protecting that PKCS#12 export.
- `APPLE_NOTARY_KEY`: App Store Connect API private key in P8 format.
- `APPLE_NOTARY_KEY_ID` and `APPLE_NOTARY_ISSUER_ID`: notarisation API identifiers.

Verify the account's notarisation permissions and rotate/revoke exports under
the maintainer's credential policy. The workflow uses an ephemeral private
keychain and deletes its temporary credentials on exit. It never falls back to
ad-hoc signing when release credentials are missing.

## Prepare a draft

Review the desired commit, green Checks run, onboarding evidence and release
notes. Tag that reviewed commit with `vMAJOR.MINOR.PATCH` matching the bundle's
version. Run **Prepare signed macOS release** with that existing tag and the
explicit onboarding-validation confirmation, selecting `main` as the workflow
branch. No release runs automatically on a push. Four jobs enforce the boundary:

1. Trusted workflow-main code verifies that the tag's commit is in that main
   snapshot's history, validates protection and records the commit and tag object.
2. Linux tests run against the pinned commit without Apple credentials.
3. A separate Mac runner tests and builds the pinned commit without Apple
   credentials, then uploads an immutable build artifact.
4. After environment approval, a fresh Mac runner checks out workflow-main code,
   rechecks the tag and validates the artifact as data. It rejects unexpected
   files, links, unsafe paths, oversized archives, preview metadata and resource
   scripts differing from the pinned source. It verifies the ad-hoc signature
   before importing credentials. Trusted main's signer signs with hardened
   runtime and a timestamp, notarises, staples and verifies without rebuilding
   or executing the app. The remote tag is checked again before creating a draft.

The credentialed job never executes the requested tag's build scripts or Swift
package manifest. Normal Mac CI exercises ZIP validation and signature
preservation without signing credentials. The public ZIP is recreated after
stapling.

The output is a **draft GitHub release**, with an ARM64 ZIP, `SHA256SUMS`,
`SOURCE_REVISION.txt` and `BUILD_INFO.txt`. There is no automatic public publish
step. Retrying an existing draft is deliberately not an overwrite operation:
review/delete an unsuccessful draft in GitHub before retrying the same tag.

[Apple's notarisation workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
explains submission and why a stapled app must be re-archived when distributing
as ZIP. The pipeline is prepared, but the credentialed path is unexecuted until
the prerequisites are available.

## Required quarantined-download smoke test

Download the actual draft ZIP through a normal browser on a supported clean
Mac. Preserve its quarantine metadata and normal Gatekeeper checks. Verify its
checksum and recorded revision, extract, move Telynd to Applications and open
normally. Do not strip quarantine or bypass a security warning. Check the setup
guide, Chrome hand-off, closing/relaunching, and replacing the earlier app while
preserving settings. Check both online and offline ticket validation where
practical, and record exact OS/architecture, tag, outcome and any warning.

Only after that evidence is reviewed should a maintainer publish the draft and
add its **direct asset link** to the quick start. Until then, the
[release page](https://github.com/exponentialR/telynd/releases) is a status page,
not a promised download. A failed smoke test keeps the draft unpublished.

## Host kit distribution

The Mac/Windows recovery resources are developer source kits, not signed host
installers. Passing client signing does not establish host-helper distribution
or actual Google reconnection. Review #16/#17 for platform signing and real
installation prerequisites, #18 for Mac/Windows operational evidence, and #13
for Linux. The release workflow runs Windows SCM fixture checks in a separate
credential-free job before signing the Mac client.
