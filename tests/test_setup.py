"""OS commands are stubbed here; real systemd checks live in linux-integration.sh."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SetupTest(unittest.TestCase):
    def flow(self, mode, fail='', existing=True, failure_code=1):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        root = Path(folder.name)
        key = root / 'test key'
        if existing:
            key.write_text('synthetic-private-key'); Path(str(key)+'.pub').write_text('synthetic-public-key')
        actions = root / 'actions'
        stub = '''#!/bin/bash
set -eu
name=${0##*/}
printf '%s\\n' "$name $*" >> "$TEST_ACTIONS"
if [ "$name" = "$TEST_FAIL" ]; then exit "$TEST_FAIL_CODE"; fi
if [ "$name" = ssh ] && [[ "$*" == *mktemp* ]]; then echo /tmp/telynd-setup.12345678; fi
'''
        for command in ['ssh','scp','ssh-add','ssh-copy-id','ssh-keygen']:
            path = root / command; path.write_text(stub); path.chmod(0o755)
        receipt = root / 'result'
        env = dict(os.environ, PATH=str(root)+os.pathsep+os.environ['PATH'], TEST_ACTIONS=str(actions), TEST_FAIL=fail, TEST_FAIL_CODE=str(failure_code))
        result = subprocess.run(['bash', str(ROOT/'scripts/setup-mac.command'), 'reader@host.example', mode, str(key), str(receipt)], env=env, capture_output=True, text=True, timeout=5)
        return result, receipt.read_text(), actions.read_text() if actions.exists() else '', root

    def test_authorisation_never_installs_and_verifies_before_success(self):
        result, receipt, actions, root = self.flow('authorise')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('result=ssh_ready', receipt)
        self.assertIn('StrictHostKeyChecking=yes', actions)
        copy = next(line for line in actions.splitlines() if line.startswith('ssh-copy-id '))
        self.assertIn('StrictHostKeyChecking=ask', copy)
        self.assertIn('ForwardAgent=no', copy)
        self.assertIn('ControlPath=none', copy)
        self.assertNotIn('scp ', actions); self.assertNotIn('sudo', actions)
        self.assertEqual((root/'result').stat().st_mode & 0o777, 0o600)

    def test_login_and_verification_failures_have_distinct_receipts(self):
        for command, expected in [('ssh-copy-id','authentication_failed'),('ssh','verification_unavailable')]:
            result, receipt, actions, _ = self.flow('authorise', command)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('result='+expected, receipt)
            self.assertNotIn('result=ssh_ready', receipt)

    def test_cancelled_authorisation_never_reports_ready(self):
        result, receipt, actions, _ = self.flow('authorise', 'ssh-copy-id', failure_code=130)
        self.assertEqual(result.returncode, 130)
        self.assertIn('result=cancelled', receipt)
        self.assertNotIn('result=ssh_ready', receipt)
        self.assertNotIn('scp ', actions)

    def test_missing_key_and_overwrite_are_refused(self):
        result, receipt, actions, _ = self.flow('authorise', existing=False)
        self.assertNotEqual(result.returncode, 0); self.assertEqual(actions, '')
        result, receipt, actions, root = self.flow('generate-key')
        self.assertNotEqual(result.returncode, 0); self.assertEqual(actions, '')
        self.assertEqual((root/'test key').read_text(), 'synthetic-private-key')

    def test_key_creation_is_explicit_and_does_not_choose_empty_passphrase(self):
        result, _, actions, _ = self.flow('generate-key', existing=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('ssh-keygen -t ed25519', actions)
        self.assertNotIn(' -N', actions)
        self.assertNotIn('ssh-copy-id', actions)

    def test_failed_upload_never_reports_installed(self):
        result, receipt, actions, _ = self.flow('install', 'scp')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('result=failed', receipt)
        self.assertNotIn('result=installed', receipt)
        self.assertNotIn('ssh-copy-id', actions)

if __name__ == '__main__': unittest.main()
