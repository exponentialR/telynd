#!/usr/bin/python3 -I
"""Fixed, package-owned administrator action. Takes no caller-supplied input."""
import os
from pathlib import Path
import subprocess
import sys


def prepare(run=subprocess.run, exists=lambda name: Path(name).is_file()):
    # Do not change authentication settings, keys, firewall rules or VPNs.
    if not exists('/usr/sbin/sshd'):
        run(['/usr/bin/apt-get', '-y', '-o', 'Dpkg::Options::=--force-confold', 'install', 'openssh-server'], check=True, timeout=300)
    # systemd creates sshd's runtime directory and runs the packaged preflight.
    run(['/usr/bin/systemctl', 'start', 'ssh.service'], check=True, timeout=30)
    run(['/usr/sbin/sshd', '-t'], check=True, timeout=10)
    run(['/usr/bin/systemctl', 'enable', 'ssh.service'], check=True, timeout=30)
    # Ubuntu may retain a listening socket while its on-demand service is idle.
    try:
        run(['/usr/bin/systemctl', 'is-active', '--quiet', 'ssh.service'], check=True, timeout=10)
    except subprocess.CalledProcessError:
        run(['/usr/bin/systemctl', 'is-active', '--quiet', 'ssh.socket'], check=True, timeout=10)


def main():
    if len(sys.argv) != 1 or sys.platform != 'linux' or os.geteuid() != 0:
        raise SystemExit('This fixed action needs administrator approval on the Linux PC.')
    os.chdir('/')
    os.environ.clear()
    os.environ.update(PATH='/usr/sbin:/usr/bin:/sbin:/bin', LANG='C', DEBIAN_FRONTEND='noninteractive')
    try:
        prepare()
    except (subprocess.SubprocessError, OSError) as error:
        raise SystemExit('SSH preparation did not complete. Existing policy was preserved; ask the administrator to check the SSH installation.') from error


if __name__ == '__main__':
    main()
