#!/bin/bash
# Run only on an ephemeral GitHub Actions runner. No ad-hoc release fallback.
set -euo pipefail
umask 077
for variable in GITHUB_ACTIONS RUNNER_TEMP TELYND_RELEASE_TAG DEVELOPER_ID_APPLICATION APPLE_CERTIFICATE_BASE64 APPLE_CERTIFICATE_PASSWORD APPLE_NOTARY_KEY APPLE_NOTARY_KEY_ID APPLE_NOTARY_ISSUER_ID; do
  [ -n "${!variable:-}" ] || { echo "Missing release prerequisite: $variable" >&2; exit 2; }
done
[ "$GITHUB_ACTIONS" = true ] || { echo 'Signing runs only in the ephemeral CI environment.'; exit 2; }
[[ "$DEVELOPER_ID_APPLICATION" == 'Developer ID Application: '* ]] || { echo 'A Developer ID Application identity is required.'; exit 2; }
[[ "$TELYND_RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
[ "$(git rev-parse HEAD)" = "$(git rev-parse "refs/tags/$TELYND_RELEASE_TAG^{commit}")" ] || { echo 'Tag does not match checkout'; exit 2; }
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo 'Source checkout is modified'; exit 2; }
work=$(mktemp -d "$RUNNER_TEMP/telynd-sign.XXXXXXXX")
keychain="$work/signing.keychain-db"
cleanup() { security delete-keychain "$keychain" >/dev/null 2>&1 || true; rm -rf "$work"; }
trap cleanup EXIT
python3 - "$work" <<'PY'
import base64, os, pathlib, sys
p = pathlib.Path(sys.argv[1])
(p/'identity.p12').write_bytes(base64.b64decode(os.environ['APPLE_CERTIFICATE_BASE64'], validate=True))
(p/'notary.p8').write_text(os.environ['APPLE_NOTARY_KEY'])
PY
keychain_password=$(openssl rand -hex 32)
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$work/identity.p12" -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security -t cert -f pkcs12 -k "$keychain" >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain"
# Build and tests run on this exact tagged revision before credentials are used to sign.
bash build.sh "$work/Telynd.app"
app="$work/Telynd.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
[ "$TELYND_RELEASE_TAG" = "v$version" ] || { echo 'Tag and app version differ'; exit 2; }
codesign --force --options runtime --timestamp --keychain "$keychain" --sign "$DEVELOPER_ID_APPLICATION" "$app"
codesign --verify --deep --strict --verbose=2 "$app"
# Submit a transport ZIP, staple the app, then recreate the user-facing ZIP.
ditto -c -k --keepParent "$app" "$work/submission.zip"
xcrun notarytool submit "$work/submission.zip" --key "$work/notary.p8" --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER_ID" --wait --timeout 30m
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
mkdir -p dist
asset="Telynd-$TELYND_RELEASE_TAG-macos-arm64.zip"
ditto -c -k --keepParent "$app" "dist/$asset"
git rev-parse HEAD > dist/SOURCE_REVISION.txt
printf 'Telynd %s\nmacOS ARM64; minimum build target 13.0\nRuntime validation: macOS 26 ARM64. Earlier systems untested.\n' "$version" > dist/BUILD_INFO.txt
(cd dist && shasum -a 256 "$asset" SOURCE_REVISION.txt BUILD_INFO.txt > SHA256SUMS)
echo 'Signed, notarised and stapled asset prepared. Publish only after the quarantined-download smoke test.'
