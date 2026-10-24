#!/bin/bash
set -eu
cd "$(dirname "$0")"
stage=$(mktemp -d /private/tmp/telynd-build.XXXXXXXX)
trap 'rm -rf "$stage"' EXIT
destination=${1:-"$PWD/build/Telynd.app"}
app="$stage/Telynd.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macos13.0" -O Telynd.swift -o "$app/Contents/MacOS/Telynd"
cp scripts/*.sh scripts/*.command "$app/Contents/Resources/"
cp assets/branding/Telynd.icns "$app/Contents/Resources/"
cp assets/branding/telynd-logo-v2.png assets/branding/telynd-logo-dark.png "$app/Contents/Resources/"
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
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Samuel Adebayo. MIT licence.</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$app"
codesign --force --deep --sign - "$app"
mkdir -p "$(dirname "$destination")"
ditto --norsrc --noextattr "$app" "$destination"
codesign --verify --deep --strict "$destination"
echo "$destination"
