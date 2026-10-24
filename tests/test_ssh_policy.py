"""Resolve real OpenSSH settings against unsafe defaults, without connecting."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

@unittest.skipUnless(shutil.which('ssh'), 'OpenSSH is required for offline policy resolution')
class SSHPolicyTest(unittest.TestCase):
    def test_shell_trust_forwarding_and_mux_overrides(self):
        with tempfile.TemporaryDirectory() as folder:
            config = Path(folder)/'config'
            config.write_text('Host *\n StrictHostKeyChecking no\n ForwardAgent yes\n ForwardX11 yes\n ControlMaster auto\n ControlPath /tmp/unsafe-mux\n ControlPersist yes\n PermitLocalCommand yes\n LocalCommand echo should-not-run\n LocalForward 12345 localhost:12345\n')
            for trust, expected in [('ask', 'ask'), ('yes', 'true')]:
                result = subprocess.run(['bash','-c','source "$1"; telynd_ssh_policy "$2" /tmp/synthetic_key; printf "%s\\0" "${telynd_ssh_options[@]}"','_',str(ROOT/'scripts/ssh-policy.sh'),trust],capture_output=True,check=True)
                options = result.stdout.decode().rstrip('\0').split('\0')
                output = subprocess.run(['ssh','-G','-F',str(config),*options,'reader@fixture.example'],capture_output=True,text=True,check=True).stdout
                fields = dict(line.split(' ',1) for line in output.splitlines() if ' ' in line)
                self.assertEqual(fields['stricthostkeychecking'], expected)
                self.assertEqual(fields['forwardagent'], 'no')
                self.assertEqual(fields['forwardx11'], 'no')
                self.assertEqual(fields['controlmaster'], 'false')
                self.assertIn(fields.get('controlpath'), [None, 'none'])
                self.assertEqual(fields['controlpersist'], 'no')
                self.assertEqual(fields['permitlocalcommand'], 'no')
                self.assertEqual(fields['clearallforwardings'], 'yes')
