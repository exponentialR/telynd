#!/bin/bash
set -eu
cd "$(dirname "$0")"
stage=$(mktemp -d /private/tmp/telynd-build.XXXXXXXX)
candidate=''
cleanup() {
  code=$?
  if [ -n "$candidate" ]; then
    if [ -d "$candidate/previous.app" ] && { [ "$code" -ne 0 ] || [ ! -e "$destination" ]; }; then
      if [ -e "$destination" ]; then mv "$destination" "$candidate/failed.app"; fi
      mv "$candidate/previous.app" "$destination"
    fi
    rm -rf "$candidate"
  fi
  rm -rf "$stage"
}
trap cleanup EXIT
destination=${1:-"$PWD/build/Telynd.app"}
app="$stage/Telynd.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
configuration=${TELYND_BUILD_CONFIGURATION:-release}
case "$configuration" in release|debug) ;; *) echo 'Unknown build configuration'; exit 2;; esac
swift build -c "$configuration" --arch arm64
binary_dir=$(swift build -c "$configuration" --arch arm64 --show-bin-path)
cp "$binary_dir/Telynd" "$app/Contents/MacOS/Telynd"
cp -R "$binary_dir/SwiftTerm_SwiftTerm.bundle" "$app/Contents/Resources/"
cp .build/checkouts/SwiftTerm/LICENSE "$app/Contents/Resources/SwiftTerm-LICENSE.txt"
cp scripts/macos-recovery.sh scripts/windows-recovery.ps1 scripts/WindowsServicePolicy.cs scripts/authorise-remote.sh scripts/ssh-policy.sh scripts/remote-check.sh scripts/setup-remote.sh scripts/uninstall-remote.sh scripts/launch-host.command scripts/setup-mac.command "$app/Contents/Resources/"
cp assets/branding/Telynd.icns "$app/Contents/Resources/"
cp assets/branding/telynd-logo-v2.png assets/branding/telynd-logo-dark.png "$app/Contents/Resources/"
cp assets/chrome-setup.html "$app/Contents/Resources/"
cp assets/telynd-setup_0.2.2_all.deb "$app/Contents/Resources/"
chmod 755 "$app/Contents/MacOS/Telynd" "$app/Contents/Resources/"*.command "$app/Contents/Resources/"*.sh
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Telynd</string>
<key>CFBundleIdentifier</key><string>com.samueladebayo.telynd</string>
<key>CFBundleName</key><string>Telynd</string>
<key>CFBundleDisplayName</key><string>Telynd</string>
<key>CFBundleIconFile</key><string>Telynd</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Samuel Adebayo. MIT licence.</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>When you choose a computer, Telynd opens Chrome Remote Desktop and reads that setup tab’s address for up to five minutes. Use open computer reads the front tab once. You confirm before saving.</string>
</dict></plist>
PLIST
# Fixture injection exists only in a debug build and cannot affect release settings.
if [ "$configuration" = debug ] && [ -n "${TELYND_FIXTURE_DIRECTORY:-}" ]; then
  /usr/libexec/PlistBuddy -c "Add :TelyndFixtureDirectory string $TELYND_FIXTURE_DIRECTORY" "$app/Contents/Info.plist"
  case "${TELYND_PREVIEW_APPEARANCE:-}" in
    light|dark) /usr/libexec/PlistBuddy -c "Add :TelyndPreviewAppearance string $TELYND_PREVIEW_APPEARANCE" "$app/Contents/Info.plist";;
    '') ;;
    *) echo 'Unknown preview appearance'; exit 2;;
  esac
fi
xattr -cr "$app"
codesign --force --deep --entitlements scripts/macos-app.entitlements --sign - "$app"
codesign --verify --deep --strict "$app"
mkdir -p "$(dirname "$destination")"
[ ! -L "$destination" ] || { echo 'Choose the actual application path, not a symlink.'; exit 2; }
if [ -e "$destination" ]; then
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")" = com.samueladebayo.telynd ] || { echo 'Refusing to replace an unrecognised application.'; exit 2; }
fi
# Replace the whole bundle, so obsolete resources and Finder metadata cannot
# survive an update. Validate the replacement before moving the existing app.
candidate=$(mktemp -d "$(dirname "$destination")/.telynd-install.XXXXXXXX")
ditto --norsrc --noextattr "$app" "$candidate/Telynd.app"
xattr -cr "$candidate/Telynd.app"
codesign --verify --deep --strict "$candidate/Telynd.app"
if [ -e "$destination" ]; then mv "$destination" "$candidate/previous.app"; fi
mv "$candidate/Telynd.app" "$destination"
codesign --verify --deep --strict "$destination"
echo "$destination"
