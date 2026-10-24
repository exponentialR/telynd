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
its deployment branches/tags and enable required maintainer review before use.
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
explicit onboarding-validation confirmation. No release runs automatically on
a push. The workflow repeats Linux integration, Swift tests and build checks
against the tagged revision, then signs with hardened runtime and a timestamp,
notarises, staples and verifies the app. It recreates the ZIP after stapling.

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
