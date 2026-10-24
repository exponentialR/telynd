#!/bin/bash
set -eu
cd "$(dirname "$0")/../.."
root=$(mktemp -d /private/tmp/telynd-viewer-lab.XXXXXXXX)
chmod 700 "$root"
app="$root/Telynd Viewer Lab.app"
mkdir -p "$app/Contents/MacOS"
swiftc experiments/embedded-viewer/Probe.swift -o "$app/Contents/MacOS/TelyndViewerProbe" -framework AppKit -framework WebKit
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TelyndViewerProbe</string>
<key>CFBundleIdentifier</key><string>com.telynd.viewerprobe</string>
<key>CFBundleName</key><string>Telynd Viewer Lab</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
printf '%s\n' "$app"
