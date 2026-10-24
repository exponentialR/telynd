"""Exercise the real local key reader and OpenSSH parser; transport stays offline."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('ssh') and shutil.which('ssh-keygen'), 'OpenSSH tools required')
class AuthorisationTest(unittest.TestCase):
    def fixture(self):
        folder = tempfile.TemporaryDirectory(prefix='telynd-authorise-')
        self.addCleanup(folder.cleanup)
        root = Path(folder.name)
        seed = root/'seed'
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-C', '$(touch TELYND_COMMENT_EXECUTED) ; `touch TELYND_COMMENT_EXECUTED`', '-f', str(seed)], check=True, capture_output=True)
        commands = root/'commands'; commands.mkdir()
        (commands/'ssh').write_text(f'#!{sys.executable}\n' + '''import json, os, pathlib, subprocess, sys
args = sys.argv[1:]
resolved = subprocess.run([os.environ['TEST_REAL_SSH'], '-G', '-F', '/dev/null', *args], capture_output=True, text=True)
if resolved.returncode: sys.stderr.write(resolved.stderr); sys.exit(resolved.returncode)
record = {'args': args, 'input': sys.stdin.read(), 'configuration': resolved.stdout}
with pathlib.Path(os.environ['TEST_LOG']).open('a') as log: log.write(json.dumps(record) + '\\n')
''')
        (commands/'ssh-add').write_text('#!/bin/sh\nexit 0\n')
        (commands/'ssh-copy-id').write_text('#!/bin/sh\necho Unsafe-helper-invoked >&2\nexit 99\n')
        for command in commands.iterdir(): command.chmod(0o700)
        env = dict(os.environ, PATH=str(commands)+os.pathsep+os.environ['PATH'], TEST_REAL_SSH=shutil.which('ssh'), TEST_LOG=str(root/'calls'))
        return root, seed, env

    def run_setup(self, root, key, env):
        return subprocess.run(['bash', str(ROOT/'scripts/setup-mac.command'), 'reader@fixture.example', 'authorise', str(key), str(root/'receipt')], input='', env=env, cwd=root, capture_output=True, text=True, timeout=10)

    def test_hostile_filenames_and_comments_stay_data_through_actual_ssh_parser(self):
        root, seed, env = self.fixture()
        fixed_command = None
        for name in ['key with spaces', 'key"quoted', "key'quoted", 'key\\slash', 'key$(touch TELYND_PATH_EXECUTED)', 'key`touch TELYND_PATH_EXECUTED`']:
            with self.subTest(name=name):
                key = root/name
                key.write_bytes(seed.read_bytes()); key.chmod(0o600)
                Path(str(key)+'.pub').write_bytes(Path(str(seed)+'.pub').read_bytes())
                (root/'calls').unlink(missing_ok=True)
                result = self.run_setup(root, key, env)
                self.assertEqual(result.returncode, 0, result.stderr)
                calls = [json.loads(line) for line in (root/'calls').read_text().splitlines()]
                self.assertEqual(len(calls), 2)
                self.assertEqual(calls[0]['input'], Path(str(seed)+'.pub').read_text())
                self.assertIn('identityfile '+str(key), calls[0]['configuration'].splitlines())
                self.assertIn('stricthostkeychecking ask', calls[0]['configuration'].splitlines())
                self.assertIn('stricthostkeychecking true', calls[1]['configuration'].splitlines())
                self.assertEqual(calls[1]['args'][-1], 'true')
                if fixed_command is None: fixed_command = calls[0]['args'][-1]
                self.assertEqual(calls[0]['args'][-1], fixed_command)
                self.assertNotIn(str(key), fixed_command)
                self.assertFalse((root/'TELYND_PATH_EXECUTED').exists())
                self.assertFalse((root/'TELYND_COMMENT_EXECUTED').exists())
                self.assertIn('result=ssh_ready', (root/'receipt').read_text())

    def test_invalid_multiple_and_oversized_keys_fail_before_ssh(self):
        root, key, env = self.fixture()
        public = Path(str(key)+'.pub'); valid = public.read_text()
        for content in ['not a public key', valid+valid, 'a'*16385]:
            with self.subTest(size=len(content)):
                public.write_text(content)
                result = self.run_setup(root, key, env)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((root/'calls').exists())
                self.assertNotIn('result=ssh_ready', (root/'receipt').read_text())
