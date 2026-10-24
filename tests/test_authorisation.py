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
resolved = subprocess.run([os.environ['TEST_REAL_SSH'], '-G', '-F', os.environ.get('TEST_SSH_CONFIG', '/dev/null'), *args], capture_output=True, text=True)
if resolved.returncode: sys.stderr.write(resolved.stderr); sys.exit(resolved.returncode)
record = {'args': args, 'input': sys.stdin.read(), 'configuration': resolved.stdout}
with pathlib.Path(os.environ['TEST_LOG']).open('a') as log: log.write(json.dumps(record) + '\\n')
''')
        (commands/'ssh-add').write_text('#!/bin/sh\nprintf "agent-called\\n" >> "$TEST_AGENT_LOG"\n')
        (commands/'ssh-copy-id').write_text('#!/bin/sh\necho Unsafe-helper-invoked >&2\nexit 99\n')
        for command in commands.iterdir(): command.chmod(0o700)
        env = dict(os.environ, PATH=str(commands)+os.pathsep+os.environ['PATH'], TEST_REAL_SSH=shutil.which('ssh'), TEST_LOG=str(root/'calls'), TEST_AGENT_LOG=str(root/'agent-calls'))
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

    def test_mismatched_public_key_fails_before_agent_or_ssh(self):
        root, key, env = self.fixture()
        other = root/'other'
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-C', 'other@example.test', '-f', str(other)], check=True, capture_output=True)
        Path(str(key)+'.pub').write_bytes(Path(str(other)+'.pub').read_bytes())
        result = self.run_setup(root, key, env)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('result=key_pair_mismatch', (root/'receipt').read_text())
        self.assertFalse((root/'calls').exists())
        self.assertFalse((root/'agent-calls').exists())

    def test_invalid_private_key_fails_before_agent_or_ssh(self):
        root, key, env = self.fixture()
        key.write_text('invalid private key')
        result = self.run_setup(root, key, env)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('result=key_validation_failed', (root/'receipt').read_text())
        self.assertFalse((root/'calls').exists())
        self.assertFalse((root/'agent-calls').exists())

    def test_protected_key_pair_uses_openssh_passphrase_handling(self):
        root, _, env = self.fixture()
        askpass = root/'askpass'
        askpass.write_text('#!/bin/sh\nprintf "%s\\n" "$TELYND_TEST_PASSPHRASE"\n'); askpass.chmod(0o700)
        env.update(SSH_ASKPASS=str(askpass), SSH_ASKPASS_REQUIRE='force', DISPLAY='telynd-fixture:0', TELYND_TEST_PASSPHRASE='fixture-only-passphrase')
        for algorithm in ['ed25519', 'rsa', 'ecdsa']:
            with self.subTest(algorithm=algorithm):
                key = root/('protected-'+algorithm)
                subprocess.run(['ssh-keygen', '-q', '-t', algorithm, '-N', 'fixture-only-passphrase', '-C', 'protected@example.test', '-f', str(key)], check=True, capture_output=True)
                result = self.run_setup(root, key, env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('result=ssh_ready', (root/'receipt').read_text())

    def test_additional_identities_are_described_as_account_access(self):
        root, key, env = self.fixture()
        config = root/'ssh-config'; config.write_text('Host *\n IdentityFile /tmp/unrelated_configured_key\n')
        env['TEST_SSH_CONFIG'] = str(config)
        result = self.run_setup(root, key, env)
        self.assertEqual(result.returncode, 0, result.stderr)
        verification = [json.loads(line) for line in (root/'calls').read_text().splitlines()][1]
        identities = [line for line in verification['configuration'].splitlines() if line.startswith('identityfile ')]
        self.assertEqual(identities, ['identityfile '+str(key), 'identityfile /tmp/unrelated_configured_key'])
        self.assertIn('SSH account access verified using your SSH configuration.', result.stdout)
        self.assertIn('Other configured keys may have been used.', result.stdout)
