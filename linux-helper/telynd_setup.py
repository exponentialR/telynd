#!/usr/bin/python3
"""Local Linux setup UI. Only public pairing details leave this computer."""
import base64
from contextlib import contextmanager
import ipaddress
import json
import os
from pathlib import Path
import platform
import pwd
import queue
import re
import socket
import stat
import subprocess
import threading
import time


@contextmanager
def permission_entries(home=None):
    """Pin the account's own paths; never chmod a substituted link or inode."""
    home = Path(pwd.getpwuid(os.getuid()).pw_dir) if home is None else Path(home)
    descriptors = []
    try:
        directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
        home_fd = os.open(home, directory_flags)
        descriptors.append(('Home folder', home_fd, True))
        try:
            ssh_fd = os.open('.ssh', directory_flags, dir_fd=home_fd)
        except FileNotFoundError:
            yield descriptors
            return
        descriptors.append(('SSH folder', ssh_fd, True))
        try:
            key_fd = os.open('authorized_keys', os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW, dir_fd=ssh_fd)
        except FileNotFoundError:
            yield descriptors
            return
        descriptors.append(('Authorised keys file', key_fd, False))
        yield descriptors
    finally:
        for _, descriptor, _ in reversed(descriptors): os.close(descriptor)


def inspect_permission_entries(entries):
    issues = []
    repairable = True
    for label, descriptor, directory in entries:
        attributes = os.fstat(descriptor)
        valid_type = stat.S_ISDIR(attributes.st_mode) if directory else stat.S_ISREG(attributes.st_mode) and attributes.st_nlink == 1
        if not valid_type or attributes.st_uid != os.getuid():
            issues.append(f'{label} needs administrator attention: it must be an ordinary path owned by your Linux account.')
            repairable = False
        elif attributes.st_mode & 0o022:
            issues.append(f'{label} allows other users to write to it; SSH can refuse key login.')
    return issues, bool(issues) and repairable


def permission_status(home=None):
    try:
        with permission_entries(home) as entries:
            return inspect_permission_entries(entries)
    except OSError:
        return ['The home or SSH paths could not be checked safely. Ask the administrator to check ownership, links and access permissions.'], False


def repair_permissions(home=None):
    with permission_entries(home) as entries:
        issues, repairable = inspect_permission_entries(entries)
        if issues and not repairable:
            raise ValueError('These paths need administrator attention. No permissions were changed.')
        for _, descriptor, _ in entries:
            mode = stat.S_IMODE(os.fstat(descriptor).st_mode)
            if mode & 0o022:
                os.fchmod(descriptor, mode & ~0o022)
        remaining, _ = inspect_permission_entries(entries)
        if remaining: raise ValueError('Permissions still need administrator attention. Some paths may have changed; check again.')


def command(args):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=5, check=True)
        return result.stdout
    except (OSError, subprocess.SubprocessError):
        return ''


def allowed_ip(value):
    try:
        ip = ipaddress.IPv4Address(value)
        return not (ip.is_loopback or ip.is_link_local or ip.is_multicast or int(ip) >> 24 == 0 or int(ip) >> 24 >= 224 or value.endswith('.255'))
    except (ValueError, TypeError):
        return False


def addresses(run=command):
    # Prefer an existing private route; do not install or reconfigure a VPN.
    result = [value for value in run(['/usr/bin/tailscale', 'ip', '-4']).split() if allowed_ip(value)]
    try:
        interfaces = json.loads(run(['/usr/sbin/ip', '-j', '-4', 'address', 'show']))
    except (ValueError, TypeError):
        interfaces = []
    for interface in interfaces:
        name = interface.get('ifname', '')
        if 'UP' not in interface.get('flags', []) or name == 'lo' or name.startswith(('docker', 'br-', 'veth', 'virbr')):
            continue
        for item in interface.get('addr_info', []):
            value = item.get('local', '')
            if allowed_ip(value) and value not in result:
                result.append(value)
    return list(dict.fromkeys(result))[:6]


def public_keys(directory=Path('/etc/ssh')):
    result = []
    for kind in ['ed25519', 'ecdsa', 'rsa']:
        path = directory / f'ssh_host_{kind}_key.pub'
        descriptor = None
        try:
            descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
            attributes = os.fstat(descriptor)
            if not stat.S_ISREG(attributes.st_mode) or attributes.st_size > 4096:
                continue
            data = os.read(descriptor, 4097)
            if len(data) > 4096: continue
            fields = data.decode().strip().split()
        except (OSError, UnicodeError):
            continue
        finally:
            if descriptor is not None: os.close(descriptor)
        expected = {'ed25519': 'ssh-ed25519', 'ecdsa': 'ecdsa-sha2-nistp256', 'rsa': 'ssh-rsa'}[kind]
        if len(fields) < 2 or fields[0] != expected:
            continue
        try:
            blob = base64.b64decode(fields[1], validate=True)
        except ValueError:
            continue
        if len(blob) < 19 or len(blob) > 1536:
            continue
        length = int.from_bytes(blob[:4], 'big')
        if blob[4:4 + length] != fields[0].encode():
            continue
        result.append({'type': fields[0], 'key': fields[1]})
    return result


def save_card(destination, value):
    descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_NONBLOCK | os.O_NOFOLLOW, 0o600)
    try:
        attributes = os.fstat(descriptor)
        if not stat.S_ISREG(attributes.st_mode) or attributes.st_uid != os.getuid() or attributes.st_nlink != 1:
            raise OSError('Choose a regular file owned by your desktop account with no hard links.')
        os.fchmod(descriptor, 0o600)
        os.ftruncate(descriptor, 0)
        with os.fdopen(descriptor, 'w', closefd=False) as stream:
            stream.write(value)
    finally:
        os.close(descriptor)


def make_card(username, hostname, candidates, keys, now=None):
    if username == 'root':
        raise ValueError('Open Telynd Setup from your normal Linux desktop account, not as root.')
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_-]*', username):
        raise ValueError('This Linux login name is not supported by Telynd. Ask the administrator for a supported desktop account.')
    if not candidates or not keys:
        raise ValueError('Enable SSH, connect this PC to your shared network or existing VPN, then check again.')
    if not hostname or len(hostname.encode()) > 128 or any(ord(c) < 32 or ord(c) == 127 for c in hostname):
        raise ValueError('This PC has an unsupported computer name. Ask its administrator to check the hostname.')
    value = dict(version=1, platform='linux', createdAt=time.time() if now is None else now, username=username,
                 hostname=hostname, addresses=candidates, hostKeys=keys)
    payload = json.dumps(value, separators=(',', ':')).encode()
    if len(payload) > 8192:
        raise ValueError('The setup details exceeded the supported size.')
    return 'TELYND1:' + base64.b64encode(payload).decode()


def main():
    import tkinter as tk
    from tkinter import ttk, messagebox, filedialog

    if platform.system() != 'Linux' or os.getuid() == 0:
        raise SystemExit('Open Telynd Setup from the Linux desktop account you want to recover.')
    username = pwd.getpwuid(os.getuid()).pw_name
    root = tk.Tk()
    root.title('Telynd Setup')
    root.geometry('640x670')
    root.minsize(580, 640)
    frame = ttk.Frame(root, padding=28)
    frame.pack(fill='both', expand=True)
    ttk.Label(frame, text='Prepare this PC for recovery', font=('', 18, 'bold')).pack(anchor='w', pady=(0, 14))
    ttk.Label(frame, text='Keep your Google remote session open. This helper supplies the details that Telynd needs on your Mac.', wraplength=560).pack(anchor='w', pady=(0, 18))
    ttk.Label(frame, text=f'Computer: {socket.gethostname()}\nLinux account: {username}').pack(anchor='w', pady=(0, 18))
    status = tk.StringVar(value='Checking this PC…')
    ttk.Label(frame, textvariable=status, wraplength=560).pack(anchor='w', pady=(0, 16))
    cached = {'addresses': [], 'keys': [], 'ready': False, 'busy': False, 'preparing': False, 'active': False, 'permission_issues': [], 'repairable': False}
    completed = queue.Queue()

    def buttons():
        prepare_button.configure(text='SSH is running' if cached['active'] else 'Enable SSH…', state='disabled' if cached['busy'] or cached['active'] else 'normal')
        repair_button.configure(state='normal' if cached['repairable'] and not cached['busy'] else 'disabled')
        check_button.configure(state='disabled' if cached['busy'] else 'normal')
        for button in [copy_button, save_button]:
            button.configure(state='normal' if cached['ready'] and not cached['busy'] else 'disabled')

    def poll():
        # Tk calls stay on its main thread, including worker completion callbacks.
        try:
            while True: completed.get_nowait()()
        except queue.Empty:
            pass
        root.after(100, poll)

    def refresh(after=None):
        if cached['busy']: return
        cached['busy'] = True
        buttons()
        status.set('Checking this PC…')
        def worker():
            candidates, keys = addresses(), public_keys()
            active = command(['/usr/bin/systemctl', 'is-active', 'ssh.service']).strip() == 'active' or command(['/usr/bin/systemctl', 'is-active', 'ssh.socket']).strip() == 'active'
            issues, repairable = permission_status()
            def finish():
                cached.update(addresses=candidates, keys=keys, active=active, permission_issues=issues, repairable=repairable, ready=active and bool(candidates) and bool(keys) and not issues, busy=False)
                if issues:
                    status.set(' '.join(issues) + (' Choose Fix folder permissions to review the repair.' if repairable else ''))
                elif not active:
                    status.set('SSH is not running. Choose Enable SSH and approve the administrator prompt, or ask the administrator to enable it.')
                elif not candidates:
                    status.set('No supported network route was found. Connect this PC to your shared IPv4 network or existing VPN, then choose Check again.')
                elif not keys:
                    status.set('The public SSH identity could not be read. Ask the administrator to check this PC’s OpenSSH host keys; Telynd never reads private keys.')
                else:
                    status.set('Ready to create a setup card. No passwords or private keys are included.')
                buttons()
                if after: after()
            completed.put(finish)
        threading.Thread(target=worker, daemon=True).start()

    def repair():
        if cached['busy'] or not cached['repairable']: return
        if not messagebox.askokcancel('Fix folder permissions?', 'This removes group and other users’ write permission from your home folder, SSH folder or authorised keys file where needed. Shared users may lose write access to these paths. It does not change permissions recursively, alter other files or SSH settings, or use administrator access.'):
            return
        try:
            repair_permissions()
        except (OSError, ValueError) as error:
            messagebox.showinfo('Permissions need attention', str(error) + ' Some permissions may already have been tightened. Choose Check again or ask the administrator.')
        refresh()

    def prepare():
        if cached['busy']: return
        if not messagebox.askokcancel('Enable SSH on this PC?', 'This installs OpenSSH Server if needed and enables its SSH service wherever this PC’s existing SSH configuration and firewall allow access. It does not change authentication policy, open router/firewall ports or authorise a Mac. You must have administrator permission.'):
            return
        cached.update(busy=True, preparing=True)
        buttons()
        status.set('Approve the system administrator prompt. Preparation may take a few minutes.')
        def worker():
            try:
                result = subprocess.run(['/usr/bin/pkexec', '/usr/lib/telynd-setup/prepare-ssh'], capture_output=True, text=True, timeout=360)
                ok = result.returncode == 0
            except (OSError, subprocess.SubprocessError):
                ok = False
            def finish():
                cached.update(busy=False, preparing=False)
                refresh()
                if not ok:
                    messagebox.showinfo('Preparation did not complete', 'Approval was cancelled or SSH needs administrator attention. You can still connect through Google. Ask the administrator to enable OpenSSH; existing SSH authentication policy is preserved.')
            completed.put(finish)
        threading.Thread(target=worker, daemon=True).start()

    def card():
        # copy/save refresh asynchronously before reaching this callback.
        if not cached['ready']:
            raise ValueError('This PC is not ready. Resolve the permission or SSH message above, then check again.')
        return make_card(username, socket.gethostname(), cached['addresses'], cached['keys'])

    def copy():
        try:
            value = card()
            root.clipboard_clear()
            root.clipboard_append(value)
            status.set('Setup card copied. On your Mac, choose Paste setup card in Telynd, confirm this PC and check the connection. Keep this helper open until you have pasted it. The card expires in 15 minutes.')
        except ValueError as error:
            messagebox.showinfo('Setup needs attention', str(error))

    def save():
        try:
            value = card()
            destination = filedialog.asksaveasfilename(defaultextension='.telynd-setup', initialfile='This-PC.telynd-setup', filetypes=[('Telynd setup card', '*.telynd-setup')])
            if destination:
                # The file dialog handles overwrite consent. Public metadata only.
                save_card(destination, value)
                status.set('Setup file saved. Transfer it to your Mac and choose Open setup file in Telynd within 15 minutes.')
        except (ValueError, OSError) as error:
            messagebox.showinfo('Setup needs attention', str(error))

    prepare_button = ttk.Button(frame, text='Enable SSH…', command=prepare)
    prepare_button.pack(anchor='w', pady=(0, 8))
    repair_button = ttk.Button(frame, text='Fix folder permissions…', command=repair)
    repair_button.pack(anchor='w', pady=(0, 8))
    check_button = ttk.Button(frame, text='Check again', command=refresh)
    check_button.pack(anchor='w', pady=(0, 18))
    ttk.Separator(frame).pack(fill='x', pady=(0, 18))
    ttk.Label(frame, text='Bring the setup card back to your Mac', font=('', 12, 'bold')).pack(anchor='w', pady=(0, 10))
    copy_button = ttk.Button(frame, text='Copy setup card', command=lambda: refresh(copy))
    copy_button.pack(anchor='w', pady=(0, 8))
    save_button = ttk.Button(frame, text='Save setup file…', command=lambda: refresh(save))
    save_button.pack(anchor='w', pady=(0, 18))
    ttk.Label(frame, text='Telynd on the Mac chooses a reachable address whose public SSH identity matches this card. It will ask separately before authorising access or installing recovery. This helper does not install a VPN.', wraplength=560).pack(anchor='w')
    def close():
        if cached['preparing']:
            messagebox.showinfo('Preparation is still running', 'Wait for SSH preparation to finish before closing this helper. Package installation may take a few minutes.')
        else:
            root.destroy()
    root.protocol('WM_DELETE_WINDOW', close)
    buttons()
    root.after(0, refresh)
    root.after(100, poll)
    root.mainloop()


if __name__ == '__main__':
    main()
