#!/bin/bash
# Real launchd against an isolated synthetic host. Disposable CI runner only.
set -euxo pipefail
[ "${TELYND_DISPOSABLE_MACOS:-}" = 1 ] || { echo 'Disposable Mac opt-in required.' >&2; exit 1; }
[ "$(uname -s)" = Darwin ] && [ "$(id -u)" -ne 0 ] || exit 1
domain="gui/$(id -u)"
launchctl print "$domain" >/dev/null 2>&1 || { echo 'No GUI launchd domain: native integration NOT EXECUTED.'; exit 77; }
# The production ancestry guard intentionally rejects world-writable /tmp.
# Use macOS' private per-user temporary hierarchy, as the file fixtures do.
root=$(python3 -c 'import pathlib,tempfile; print(pathlib.Path(tempfile.mkdtemp(prefix="telynd-launchd-")).resolve())')
suffix=$(uuidgen | tr '[:upper:]' '[:lower:]')
google_label="com.telynd.fixture.host.$suffix"
recovery_label="com.telynd.fixture.recovery.$suffix"
cleanup() {
  launchctl bootout "$domain/$recovery_label" >/dev/null 2>&1 || true
  launchctl bootout "$domain/$google_label" >/dev/null 2>&1 || true
  launchctl enable "$domain/$recovery_label" >/dev/null 2>&1 || true
  launchctl enable "$domain/$google_label" >/dev/null 2>&1 || true
  rm -rf "$root"
}
trap cleanup EXIT
repo=$(cd "$(dirname "$0")/.." && pwd)
export TELYND_NATIVE_ROOT="$root" TELYND_NATIVE_GOOGLE_LABEL="$google_label" TELYND_NATIVE_RECOVERY_LABEL="$recovery_label" TELYND_NATIVE_REPO="$repo"
mkdir -p "$root/home/Library/Application Support" "$root/home/Library/LaunchAgents" "$root/Google.app/Contents/MacOS"
cat > "$root/host.c" <<'C'
#include <unistd.h>
int main(void) { sleep(600); return 0; }
C
clang "$root/host.c" -o "$root/Google.app/Contents/MacOS/remoting_me2me_host_service"
python3 - <<'PY'
import os,plistlib
from pathlib import Path
root=Path(os.environ['TELYND_NATIVE_ROOT'])
binary=root/'Google.app/Contents/MacOS/remoting_me2me_host_service'
with (root/'Google.app/Contents/Info.plist').open('wb') as f:
 plistlib.dump({'CFBundleIdentifier':'com.telynd.fixture.host','CFBundleExecutable':binary.name,'CFBundlePackageType':'APPL'},f)
with (root/'google.plist').open('wb') as f:
 plistlib.dump({'Label':os.environ['TELYND_NATIVE_GOOGLE_LABEL'],'ProgramArguments':[str(binary),'--run-from-launchd'],'Disabled':False,'StandardOutPath':'/dev/null','StandardErrorPath':'/dev/null'},f)
(root/'enabled').touch()
s=(Path(os.environ['TELYND_NATIVE_REPO'])/'scripts/macos-recovery.sh').read_text()
s=s.replace('$HOME',str(root/'home'))
s=s.replace('/Library/LaunchAgents/org.chromium.chromoting.plist',str(root/'google.plist'))
s=s.replace('/Library/PrivilegedHelperTools/ChromeRemoteDesktopHost.app',str(root/'Google.app'))
s=s.replace('/Library/PrivilegedHelperTools/org.chromium.chromoting.me2me_enabled',str(root/'enabled'))
s=s.replace('org.chromium.chromoting',os.environ['TELYND_NATIVE_GOOGLE_LABEL'])
s=s.replace('org[.]chromium[.]chromoting',os.environ['TELYND_NATIVE_GOOGLE_LABEL'].replace('.','[.]'))
s=s.replace('com.telynd.recovery',os.environ['TELYND_NATIVE_RECOVERY_LABEL'])
start=s.index('root_tree() {');end=s.index('inspect_google() {',start)
s=s[:start]+'root_tree() { return 0; }\n'+s[end:]
s=s.replace("-R '=anchor apple generic and certificate leaf[subject.OU] = \"EQHXZ8M8AV\"'",'')
(root/'kit.sh').write_text(s)
PY
codesign --force --sign - "$root/Google.app"
launchctl bootstrap "$domain" "$root/google.plist"
id=00000000-0000-0000-0000-000000000001
check_report() { python3 -c 'import json,sys; r=json.load(sys.stdin); assert r[sys.argv[1]] == sys.argv[2],r' "$1" "$2"; }
bash "$root/kit.sh" check "$id" | check_report service stopped
bash "$root/kit.sh" install "$id" | check_report installation verified
bash "$root/kit.sh" recover "$id" | check_report outcome started
for _ in 1 2 3 4 5; do
  state=$(bash "$root/kit.sh" check "$id")
  if printf '%s\n' "$state" | check_report service running 2>/dev/null; then break; fi
  sleep 1
done
printf '%s\n' "$state" | check_report service running
bash "$root/kit.sh" recover "$id" | check_report outcome unchanged
# Native disabled state must stay disabled even when its loaded job exits.
launchctl disable "$domain/$google_label"
launchctl kill SIGTERM "$domain/$google_label"
sleep 1
bash "$root/kit.sh" recover "$id" | check_report outcome unchanged
bash "$root/kit.sh" check "$id" | check_report enablement disabled
bash "$root/kit.sh" disable "$id" | check_report installation disabled
launchctl print-disabled "$domain" | grep -F "\"$recovery_label\"" | grep -E '=>[[:space:]]*(true|disabled)'
bash "$root/kit.sh" uninstall "$id" | check_report installation missing
launchctl print "$domain/$google_label" >/dev/null
echo 'Native launchd install/start/active preservation/persistent disable/removal passed against a synthetic signed host.'
