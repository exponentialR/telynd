"""Mac file/agent lifecycle under isolated fixtures; no personal launchd changes."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
ID = '00000000-0000-0000-0000-000000000001'


@unittest.skipUnless(sys.platform == 'darwin', 'macOS file tools required')
class MacRecoveryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='telynd-mac-fixture-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.home = self.root/'home'
        (self.home/'Library/Application Support').mkdir(parents=True)
        (self.home/'Library/LaunchAgents').mkdir()
        self.bin = self.root/'bin'; self.bin.mkdir()
        self.google = self.root/'google'; self.google.mkdir()
        app = self.google/'ChromeRemoteDesktopHost.app'
        (app/'Contents/MacOS').mkdir(parents=True)
        binary = app/'Contents/MacOS/remoting_me2me_host_service'; binary.touch()
        with (self.google/'org.chromium.chromoting.plist').open('wb') as f:
            plistlib.dump({'Label':'org.chromium.chromoting', 'Disabled':False, 'ProgramArguments':[str(binary),'--run-from-launchd']}, f)
        self.marker = self.google/'org.chromium.chromoting.me2me_enabled'; self.marker.touch()
        (self.root/'service').write_text('stopped')
        # Only this test copy's fixed paths, Google-root/signature adapter and
        # launchctl are changed. Actual private file/manifest/lock logic runs.
        source = (ROOT/'scripts/macos-recovery.sh').read_text()
        source = source.replace('PATH=/usr/bin:/bin:/usr/sbin:/sbin', f'PATH={self.bin}:/usr/bin:/bin:/usr/sbin:/sbin')
        source = source.replace('$HOME', str(self.home))
        source = source.replace('/Library/LaunchAgents/org.chromium.chromoting.plist', str(self.google/'org.chromium.chromoting.plist'))
        source = source.replace('/Library/PrivilegedHelperTools/ChromeRemoteDesktopHost.app', str(app))
        source = source.replace('/Library/PrivilegedHelperTools/org.chromium.chromoting.me2me_enabled', str(self.marker))
        start=source.index('root_tree() {'); end=source.index('inspect_google() {', start)
        source=source[:start]+'root_tree() { return 0; }\n'+source[end:]
        self.script=self.root/'macos-recovery.sh'; self.script.write_text(source)
        (self.bin/'codesign').write_text('''#!/bin/bash
[[ "$*" == *'=anchor apple generic'* && "$*" == *EQHXZ8M8AV* ]] || exit 2
[ ! -e "$TELYND_FIXTURE_ROOT/bad-signature" ]
''')
        (self.bin/'launchctl').write_text('''#!/bin/bash
set -eu
root=$TELYND_FIXTURE_ROOT
case "$1" in
 print-disabled) if [ -f "$root/disabled" ]; then echo '"org.chromium.chromoting" => true'; else echo '{}'; fi;;
 print)
   if [[ "$2" == */com.telynd.recovery ]]; then
     [ -f "$root/loaded" ] || exit 1
     if [ -f "$root/foreign-job" ]; then echo ' path = /tmp/foreign.plist'
     else echo " path = $root/home/Library/LaunchAgents/com.telynd.recovery.plist"; fi
   else [ ! -f "$root/no-session" ] || exit 1; printf ' state = %s\\n' "$(cat "$root/service")"; fi;;
 bootstrap) [ ! -f "$root/fail-bootstrap" ] && [ ! -f "$root/agent-disabled" ] || exit 1; touch "$root/loaded";;
 disable) touch "$root/agent-disabled";;
 enable) rm -f "$root/agent-disabled";;
 bootout) rm "$root/loaded";;
 kickstart) printf 'start\\n' >> "$root/starts"; if [ ! -f "$root/keep-stopped" ]; then echo running > "$root/service"; fi;;
 *) exit 2;;
esac
''')
        for p in self.bin.iterdir(): p.chmod(0o755)
        self.env=dict(os.environ, TELYND_FIXTURE_ROOT=str(self.root))

    def run_mode(self, mode, ok=True):
        r=subprocess.run(['bash',str(self.script),mode,ID],env=self.env,capture_output=True,text=True,timeout=15)
        if ok: self.assertEqual(r.returncode,0,r.stderr)
        else: self.assertNotEqual(r.returncode,0,r.stdout)
        return json.loads(r.stdout) if ok else r

    @property
    def folder(self): return self.home/'Library/Application Support/TelyndRecovery'

    def test_read_only_check_and_full_install_disable_remove(self):
        self.assertEqual(self.run_mode('check')['installation'],'missing')
        self.assertFalse(self.folder.exists())
        self.assertEqual(self.run_mode('install')['installation'],'verified')
        self.assertEqual(self.run_mode('install')['installation'],'verified')
        self.assertEqual(self.run_mode('recover')['outcome'],'started')
        self.assertEqual(self.run_mode('recover')['outcome'],'unchanged')
        self.assertEqual((self.root/'starts').read_text(),'start\n')
        self.assertEqual(self.run_mode('disable')['installation'],'disabled')
        self.assertTrue((self.root/'agent-disabled').exists())
        self.assertEqual(self.run_mode('install')['installation'],'verified')
        self.assertFalse((self.root/'agent-disabled').exists())
        self.assertEqual(self.run_mode('uninstall')['installation'],'missing')
        self.assertTrue(self.marker.exists())

    def test_disabled_running_transitioning_and_missing_session_are_untouched(self):
        self.run_mode('install')
        for state in ['running','spawning','spawn scheduled','throttled','unrecognised-state']:
            (self.root/'service').write_text(state)
            self.assertEqual(self.run_mode('tick')['outcome'],'unchanged')
        (self.root/'service').write_text('stopped')
        for flag in ['disabled','no-session']:
            p=self.root/flag; p.touch()
            self.assertEqual(self.run_mode('tick')['outcome'],'unchanged'); p.unlink()
        self.marker.unlink()
        self.assertEqual(self.run_mode('tick')['outcome'],'unchanged')
        self.assertFalse((self.root/'starts').exists())

    def test_crash_loop_is_bounded_and_bad_retry_state_fails_closed(self):
        self.run_mode('install'); (self.root/'keep-stopped').touch()
        for _ in range(3): self.assertEqual(self.run_mode('tick')['outcome'],'started')
        self.assertEqual(self.run_mode('tick')['outcome'],'retry-limit')
        self.assertEqual(len((self.root/'starts').read_text().splitlines()),3)
        (self.folder/'attempts').write_text('malformed')
        self.run_mode('tick',ok=False)

    def test_signature_drift_links_and_lock_refuse_changes(self):
        (self.root/'bad-signature').touch()
        self.run_mode('install',ok=False)
        self.assertFalse((self.root/'loaded').exists())
        (self.root/'bad-signature').unlink()
        self.run_mode('install')
        helper=self.folder/'macos-recovery.sh'; original=helper.read_text()
        helper.write_text(original+'\n# drift\n')
        self.run_mode('uninstall',ok=False)
        self.assertTrue((self.root/'loaded').exists())
        helper.write_text(original)
        (self.folder/'lock').mkdir()
        self.run_mode('recover',ok=False)
        (self.folder/'lock').rmdir()
        helper.unlink(); helper.symlink_to(self.script)
        self.run_mode('recover',ok=False)
        self.assertFalse((self.root/'starts').exists())

    def test_failed_bootstrap_is_retryable_and_unrecognised_partial_is_preserved(self):
        (self.root/'fail-bootstrap').touch()
        self.run_mode('install',ok=False)
        self.assertEqual(self.run_mode('check')['installation'],'disabled')
        (self.root/'fail-bootstrap').unlink()
        self.assertEqual(self.run_mode('install')['installation'],'verified')
        (self.folder/'manifest').unlink()
        self.run_mode('install',ok=False)
        self.assertTrue((self.folder/'macos-recovery.sh').exists())

    def test_foreign_loaded_launch_label_is_never_replaced_or_unloaded(self):
        (self.root/'loaded').touch(); (self.root/'foreign-job').touch()
        self.run_mode('install',ok=False)
        self.assertFalse((self.folder/'macos-recovery.sh').exists())
        (self.root/'foreign-job').unlink(); (self.root/'loaded').unlink()
        self.run_mode('install')
        (self.root/'foreign-job').touch()
        self.assertEqual(self.run_mode('check')['installation'],'drift')
        self.run_mode('disable',ok=False)
        self.assertTrue((self.root/'loaded').exists())


if __name__ == '__main__': unittest.main()
