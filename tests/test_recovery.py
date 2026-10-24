"""Exercise recovery decisions with a fake systemctl; never touch live hosts."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RecoveryTest(unittest.TestCase):
    def fixture(self, tmp, state, enabled=True, start_fails=False):
        ctl = tmp / "systemctl"
        ctl.write_text('''#!/bin/bash
set -eu
case "$1" in
  show) cat "$TEST_WORK/state" ;;
  is-enabled) echo "$TEST_ENABLED"; case "$TEST_ENABLED" in enabled|enabled-runtime) exit 0;; *) exit 1;; esac ;;
  start)
    echo start >> "$TEST_WORK/actions"
    test "$TEST_FAIL" = no
    if [ "$TEST_DELAY" = yes ]; then sleep 0.3; fi
    echo active > "$TEST_WORK/state" ;;
  is-active) test "$(cat "$TEST_WORK/state")" = active ;;
  *) exit 99 ;;
esac
''')
        ctl.chmod(0o755)
        (tmp / "state").write_text(state)
        source = (ROOT / "scripts/setup-remote.sh").read_text()
        helper = source.split('cat > "$work/recover" <<EOF\n', 1)[1].split('\nEOF', 1)[0]
        helper = (helper.replace('$guard_definition', 'telynd_secure_directories() { return 0; }').replace('\\$', '$')
                  .replace('$systemctl_path', str(ctl))
                  .replace('$install_path', shutil.which('install'))
                  .replace("unit='$unit'", "unit='chrome-remote-desktop@test.service'")
                  .replace('/run/remote-desktops-recovery-${desktop_uid}', str(tmp / 'private-lock')))
        if shutil.which('flock'):
            helper = helper.replace('$flock_path', shutil.which('flock'))
        else:
            helper = helper.replace("'$flock_path' -n 9", 'true')
        script = tmp / "recover"
        script.write_text(helper)
        env = dict(os.environ, TEST_WORK=str(tmp), TEST_ENABLED=('enabled' if enabled is True else 'disabled' if enabled is False else enabled), TEST_FAIL='yes' if start_fails else 'no', TEST_DELAY='no')
        return script, env

    def run_case(self, state, enabled=True, start_fails=False, args=()):
        with tempfile.TemporaryDirectory() as folder:
            tmp = Path(folder)
            script, env = self.fixture(tmp, state, enabled, start_fails)
            result = subprocess.run(['/bin/bash', str(script), *args], env=env, capture_output=True, text=True, timeout=4)
            actions = (tmp / 'actions').read_text() if (tmp / 'actions').exists() else ''
            if not args:
                self.assertEqual((tmp / 'private-lock').stat().st_mode & 0o777, 0o700)
                self.assertTrue((tmp / 'private-lock/lock').is_file())
            return result, actions

    def test_running_service_is_never_restarted(self):
        result, actions = self.run_case('active')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(actions, '')

    def test_stopped_or_failed_service_recovers(self):
        for state in ['inactive', 'failed']:
            with self.subTest(state=state):
                result, actions = self.run_case(state)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(actions, 'start\n')
                self.assertIn('recovered', result.stdout)

    def test_disabled_service_stays_disabled(self):
        for enablement in ['disabled', 'masked', 'static', 'indirect', 'linked', 'unknown']:
            result, actions = self.run_case('inactive', enabled=enablement)
            self.assertNotEqual(result.returncode, 0, enablement)
            self.assertEqual(actions, '', enablement)

    def test_transition_and_unknown_states_are_left_alone(self):
        for state in ['activating', 'deactivating', 'reloading', 'unknown', '']:
            with self.subTest(state=state):
                result, actions = self.run_case(state)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(actions, '')

    def test_failed_start_is_not_reported_as_recovery(self):
        result, actions = self.run_case('failed', start_fails=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(actions, 'start\n')
        self.assertNotIn('recovered', result.stdout)

    def test_arguments_cannot_redirect_the_privileged_helper(self):
        result, actions = self.run_case('failed', args=('another.service',))
        self.assertEqual(result.returncode, 2)
        self.assertEqual(actions, '')

    @unittest.skipUnless(shutil.which('flock'), 'Linux flock is needed for the concurrency check')
    def test_concurrent_recovery_starts_the_service_only_once(self):
        with tempfile.TemporaryDirectory() as folder:
            tmp = Path(folder)
            script, env = self.fixture(tmp, 'failed')
            env['TEST_DELAY'] = 'yes'
            first = subprocess.Popen(['/bin/bash', str(script)], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                deadline = time.monotonic() + 3
                while not (tmp / 'actions').exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue((tmp / 'actions').exists(), 'First recovery did not reach service start')
                second = subprocess.run(['/bin/bash', str(script)], env=env, capture_output=True, text=True, timeout=3)
                self.assertEqual(second.returncode, 0, second.stderr)
                self.assertIn('already running', second.stdout)
                stdout, stderr = first.communicate(timeout=3)
                self.assertEqual(first.returncode, 0, stderr)
                self.assertIn('recovered', stdout)
                self.assertEqual((tmp / 'actions').read_text(), 'start\n')
            finally:
                if first.poll() is None:
                    first.kill()
                    first.communicate()


if __name__ == '__main__':
    unittest.main()
