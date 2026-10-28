#!/bin/bash
# Explicit developer-preview packaging; the Developer ID release path is separate.
set -euo pipefail
cd "$(dirname "$0")/.."
tag=${1:?Usage: bash scripts/package-preview.sh vMAJOR.MINOR.PATCH-preview.N}
[[ "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)-preview\.[0-9]+$ ]] || { echo 'A versioned preview tag is required.' >&2; exit 2; }
version=${BASH_REMATCH[1]}
[ -z "$(git status --porcelain)" ] || { echo 'Commit the reviewed source before packaging.' >&2; exit 2; }
[ "${TELYND_BUILD_CONFIGURATION:-release}" = release ] || { echo 'Preview packages require a release build.' >&2; exit 2; }
revision=$(git rev-parse HEAD)
destination="$PWD/dist/$tag"
[ ! -e "$destination" ] || { echo 'Refusing to overwrite an existing preview.' >&2; exit 2; }
stage=$(mktemp -d /private/tmp/telynd-preview.XXXXXXXX)
trap 'rm -rf "$stage"' EXIT
bash build.sh "$stage/Telynd.app"
actual=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$stage/Telynd.app/Contents/Info.plist")
[ "$actual" = "$version" ] || { echo 'Preview tag and app version differ.' >&2; exit 2; }
ditto --norsrc --noextattr -c -k --keepParent "$stage/Telynd.app" "$stage/transport.zip"
python3 scripts/prepare_release_input.py "$stage/transport.zip" "$stage/validated" --tag "v$version" --revision "$revision"
app="$stage/validated/Telynd.app"
codesign --verify --deep --strict "$app"
mkdir "$stage/payload" "$stage/output"
ditto --norsrc --noextattr "$app" "$stage/payload/Telynd.app"
cp docs/preview-installation.txt "$stage/payload/READ_ME_FIRST.txt"
cp LICENSE "$stage/payload/LICENSE.txt"
printf '%s\n' "$revision" > "$stage/output/SOURCE_REVISION.txt"
cat > "$stage/output/BUILD_INFO.txt" <<EOF
Telynd $tag
Source: $revision
Source URL: https://github.com/exponentialR/telynd/tree/$revision
App bundle version: $version
Architecture: arm64 (Apple silicon only)
Minimum build target: macOS 13.0; runtime validation covers macOS 26 only
Signature: ad-hoc; no Apple Developer ID
Apple notarisation: NOT NOTARISED
Distribution channel: developer preview
Packaging validates the ARM64 executable, bundle metadata, signature and source resources.
See release-notes.md and docs/validation.md for test evidence and remaining checks.
EOF
cp docs/release-notes.md "$stage/output/release-notes.md"
cp docs/preview-installation.txt "$stage/output/READ_ME_FIRST.txt"
cp LICENSE "$stage/output/LICENSE.txt"
cp "$stage/output/BUILD_INFO.txt" "$stage/output/SOURCE_REVISION.txt" "$stage/payload/"
asset="Telynd-$tag-macos-arm64.zip"
ditto --norsrc --noextattr -c -k "$stage/payload" "$stage/output/$asset"
(cd "$stage/output" && shasum -a 256 "$asset" BUILD_INFO.txt SOURCE_REVISION.txt READ_ME_FIRST.txt LICENSE.txt release-notes.md > SHA256SUMS)
[ "$(git rev-parse HEAD)" = "$revision" ] && [ -z "$(git status --porcelain)" ] || { echo 'Source changed during packaging.' >&2; exit 2; }
mkdir -p dist
mv "$stage/output" "$destination"
echo "$destination"
echo 'Developer preview prepared. Browser-download validation is required before publishing.'
