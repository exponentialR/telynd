"""Readiness protocol fixtures; no service writes or real SSH."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class ReadinessTest(unittest.TestCase):
    def run_check(self, system='Linux', loaded='loaded', state='inactive', systemd=True):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            scripts = {
                'uname': '#!/bin/bash\necho "$TEST_OS"\n',
                'id': '#!/bin/bash\nif [ "$1" = -u ]; then echo 987654; else echo fixture; fi\n',
                'systemctl': '''#!/bin/bash
set -eu
printf '%s\\n' "$*" >> "$TEST_ACTIONS"
if [ "$*" = 'show -p Version --value' ]; then test "$TEST_SYSTEMD" = yes; exit; fi
case "$1" in
 show) case "$*" in *LoadState*) echo "$TEST_LOADED";; *) echo "$TEST_STATE";; esac;;
 is-enabled) echo disabled; exit 1;;
 *) exit 99;;
esac
'''}
            for name, text in scripts.items():
                p=root/name; p.write_text(text); p.chmod(0o755)
            env=dict(os.environ, PATH=str(root)+os.pathsep+os.environ['PATH'], TEST_OS=system, TEST_LOADED=loaded, TEST_STATE=state, TEST_SYSTEMD='yes' if systemd else 'no', TEST_ACTIONS=str(root/'actions'))
            r=subprocess.run(['bash',str(ROOT/'scripts/remote-check.sh'),'check'],env=env,capture_output=True,text=True,timeout=5)
            commands=(root/'actions').read_text() if (root/'actions').exists() else ''
            self.assertEqual(r.returncode,0,r.stderr)
            self.assertIn('TELYND:check=complete',r.stdout)
            self.assertNotIn('start ',commands); self.assertNotIn('enable ',commands); self.assertNotIn('stop ',commands)
            return r.stdout

    def test_unsupported_os_and_missing_systemd_are_not_authentication_failures(self):
        self.assertIn('TELYND:os=other',self.run_check(system='Darwin'))
        self.assertIn('TELYND:systemd=unavailable',self.run_check(systemd=False))

    def test_missing_service_and_stopped_service_are_structured_read_only_results(self):
        self.assertIn('TELYND:service_loaded=not-found', self.run_check(loaded='not-found'))
        for state in ['active','inactive','failed','activating']:
            self.assertIn('TELYND:service='+state,self.run_check(state=state))

if __name__ == '__main__': unittest.main()
