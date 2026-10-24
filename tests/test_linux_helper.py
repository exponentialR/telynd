"""Helper protocol, privilege boundary and package checks. No real host changes."""
import base64
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest import mock
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def module(name, source):
    spec = importlib.util.spec_from_file_location(name, ROOT / source)
    result = importlib.util.module_from_spec(spec); spec.loader.exec_module(result)
    return result


HELPER = module('telynd_helper', 'linux-helper/telynd_setup.py')
PREPARE = module('telynd_prepare', 'linux-helper/prepare_ssh.py')
BUILD = module('telynd_package', 'scripts/build_linux_helper.py')


class HelperTest(unittest.TestCase):
    def test_writable_home_is_detected_and_repaired_without_recursive_changes(self):
        with tempfile.TemporaryDirectory() as folder:
            home = Path(folder).resolve(); home.chmod(0o772)
            child = home/'shared-file'; child.write_text('preserved'); child.chmod(0o666)
            issues, repairable = HELPER.permission_status(home)
            self.assertTrue(repairable); self.assertIn('Home folder', issues[0])
            HELPER.repair_permissions(home)
            self.assertEqual(home.stat().st_mode & 0o777, 0o750)
            self.assertEqual(child.stat().st_mode & 0o777, 0o666)
            self.assertEqual(child.read_text(), 'preserved')
            self.assertEqual(HELPER.permission_status(home), ([], False))

    def test_ssh_permissions_are_checked_and_only_write_bits_are_removed(self):
        with tempfile.TemporaryDirectory() as folder:
            home = Path(folder).resolve(); ssh = home/'.ssh'; ssh.mkdir(mode=0o777); ssh.chmod(0o777)
            key = ssh/'authorized_keys'; key.write_text('public data'); key.chmod(0o666)
            issues, repairable = HELPER.permission_status(home)
            self.assertTrue(repairable); self.assertEqual(len(issues), 2)
            HELPER.repair_permissions(home)
            self.assertEqual(ssh.stat().st_mode & 0o777, 0o755)
            self.assertEqual(key.stat().st_mode & 0o777, 0o644)
            self.assertEqual(key.read_text(), 'public data')

    def test_unsafe_paths_are_not_repaired_or_followed(self):
        with tempfile.TemporaryDirectory() as folder:
            home = Path(folder).resolve(); ssh = home/'.ssh'; ssh.mkdir()
            preserved = home/'preserved'; preserved.write_text('unchanged'); preserved.chmod(0o666)
            key = ssh/'authorized_keys'; key.symlink_to(preserved)
            for kind in ['symlink', 'hardlink', 'fifo']:
                if kind == 'hardlink': key.unlink(); os.link(preserved, key)
                if kind == 'fifo': key.unlink(); os.mkfifo(key)
                home.chmod(0o772)
                issues, repairable = HELPER.permission_status(home)
                self.assertTrue(issues); self.assertFalse(repairable)
                with self.assertRaises((OSError, ValueError)): HELPER.repair_permissions(home)
                self.assertEqual(home.stat().st_mode & 0o777, 0o772)
                self.assertEqual(preserved.stat().st_mode & 0o777, 0o666)
            key.unlink(); ssh.rmdir(); ssh.symlink_to(home)
            self.assertFalse(HELPER.permission_status(home)[1])
            with self.assertRaises(OSError): HELPER.repair_permissions(home)

    def test_foreign_owned_paths_require_administrator_review_without_chmod(self):
        with tempfile.TemporaryDirectory() as folder:
            home = Path(folder).resolve(); home.chmod(0o772)
            original = HELPER.os.fstat
            def foreign(descriptor):
                attributes = original(descriptor)
                values = list(attributes); values[4] = os.getuid() + 1
                return os.stat_result(values)
            with mock.patch.object(HELPER.os, 'fstat', side_effect=foreign), mock.patch.object(HELPER.os, 'fchmod') as chmod:
                self.assertFalse(HELPER.permission_status(home)[1])
                with self.assertRaises(ValueError): HELPER.repair_permissions(home)
                chmod.assert_not_called()

    def test_addresses_prefer_existing_vpn_filter_virtual_interfaces_and_limit_scope(self):
        rows = [{'ifname': 'eth0', 'flags': ['UP'], 'addr_info': [{'local': '192.0.2.4'}]},
                {'ifname': 'docker0', 'flags': ['UP'], 'addr_info': [{'local': '10.0.0.1'}]},
                {'ifname': 'eth1', 'flags': [], 'addr_info': [{'local': '192.0.2.5'}]},
                {'ifname': 'tailscale0', 'flags': ['UP'], 'addr_info': [{'local': '100.75.0.12'}]}]
        def run(args): return '100.75.0.12\n' if args[0].endswith('tailscale') else json.dumps(rows)
        self.assertEqual(HELPER.addresses(run), ['100.75.0.12', '192.0.2.4'])
        for address in ['127.0.0.1', '169.254.1.2', '224.0.0.1', '::1', '0.0.0.0', '192.0.2.255', '192.0.2.4;id']:
            self.assertFalse(HELPER.allowed_ip(address))

    def test_public_key_collection_does_not_read_private_keys_or_follow_links(self):
        blob = b'\0\0\0\x0bssh-ed25519\0\0\0\x20' + b'x' * 32
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root/'ssh_host_ed25519_key.pub').write_text('ssh-ed25519 ' + base64.b64encode(blob).decode() + ' ignored comment')
            (root/'ssh_host_rsa_key.pub').symlink_to(root/'ssh_host_ed25519_key.pub')
            (root/'ssh_host_ed25519_key').write_text('PRIVATE-MATERIAL-MUST-STAY-LOCAL')
            keys = HELPER.public_keys(root)
            card = HELPER.make_card('demo', 'Work-PC', ['192.0.2.4'], keys, now=1000)
            value = json.loads(base64.b64decode(card[8:]))
            self.assertEqual(len(value['hostKeys']), 1)
            self.assertNotIn('PRIVATE', str(value)); self.assertNotIn('ignored comment', str(value))
            self.assertEqual(set(value), {'version','platform','createdAt','username','hostname','addresses','hostKeys'})
            with self.assertRaises(ValueError): HELPER.make_card('root', 'PC', ['192.0.2.4'], keys)

    def test_administrator_action_is_fixed_and_never_changes_authentication_or_firewall(self):
        calls = []
        PREPARE.prepare(run=lambda args, **kwargs: calls.append(args), exists=lambda _: False)
        self.assertEqual(calls, [
            ['/usr/bin/apt-get','-y','-o','Dpkg::Options::=--force-confold','install','openssh-server'],
            ['/usr/bin/systemctl','start','ssh.service'], ['/usr/sbin/sshd','-t'], ['/usr/bin/systemctl','enable','ssh.service'],
            ['/usr/bin/systemctl','is-active','--quiet','ssh.service']])
        calls = []
        PREPARE.prepare(run=lambda args, **kwargs: calls.append(args), exists=lambda _: True)
        self.assertEqual(len(calls), 4)
        with mock.patch.object(sys, 'argv', ['prepare-ssh','unexpected']), mock.patch.object(PREPARE, 'prepare') as action:
            with self.assertRaises(SystemExit): PREPARE.main()
            action.assert_not_called()

    def test_socket_activated_ssh_is_supported_but_both_inactive_fail(self):
        calls = []
        def run(args, **kwargs):
            calls.append(args)
            if args[1:3] == ['is-active', '--quiet'] and args[-1] == 'ssh.service':
                raise subprocess.CalledProcessError(3, args)
        PREPARE.prepare(run=run, exists=lambda _: True)
        self.assertEqual(calls[-1], ['/usr/bin/systemctl','is-active','--quiet','ssh.socket'])
        def inactive(args, **kwargs):
            if args[1] == 'is-active': raise subprocess.CalledProcessError(3, args)
        with self.assertRaises(subprocess.CalledProcessError):
            PREPARE.prepare(run=inactive, exists=lambda _: True)

    def test_setup_file_is_private_and_cannot_follow_links_or_write_special_files(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); destination = root/'PC.telynd-setup'
            HELPER.save_card(destination, 'public-card')
            self.assertEqual(destination.stat().st_mode & 0o777, 0o600)
            original = root/'preserved'; original.write_text('unchanged')
            link = root/'link'; link.symlink_to(original)
            with self.assertRaises(OSError): HELPER.save_card(link, 'must-not-write')
            self.assertEqual(original.read_text(), 'unchanged')
            if hasattr(os, 'mkfifo'):
                fifo = root/'pipe'; os.mkfifo(fifo)
                with self.assertRaises(OSError): HELPER.save_card(fifo, 'must-not-block')

    def test_package_matches_reviewable_sources_and_has_no_install_time_ssh_action(self):
        package = BUILD.package()
        self.assertEqual(package, (ROOT/'assets/telynd-setup_0.2.1_all.deb').read_bytes())
        self.assertTrue(package.startswith(b'!<arch>\n'))
        offset = 8; members = {}
        while offset < len(package):
            header = package[offset:offset+60]; size = int(header[48:58]); name = header[:16].decode().strip()
            members[name] = package[offset+60:offset+60+size]; offset += 60 + size + size % 2
        self.assertEqual(members['debian-binary'], b'2.0\n')
        with tarfile.open(fileobj=io.BytesIO(members['control.tar.gz'])) as control:
            self.assertEqual([p.name for p in control.getmembers() if p.isfile()], ['./control'])
        with tarfile.open(fileobj=io.BytesIO(members['data.tar.gz'])) as archive:
            for destination, (source, mode) in BUILD.SOURCES.items():
                item = archive.getmember('./'+destination)
                self.assertEqual(archive.extractfile(item).read(), (ROOT/source).read_bytes())
                self.assertEqual(item.uid, 0); self.assertEqual(item.gid, 0); self.assertEqual(item.mode, mode)
            policy = ET.fromstring(archive.extractfile('./usr/share/polkit-1/actions/org.telynd.setup.policy').read())
            self.assertEqual(policy.find('.//allow_active').text, 'auth_admin')
            self.assertEqual(policy.find('.//allow_any').text, 'no')
            self.assertEqual(policy.find('.//annotate').text, '/usr/lib/telynd-setup/prepare-ssh')


@unittest.skipUnless(sys.platform == 'linux' and os.environ.get('DISPLAY'), 'Linux desktop test needs Xvfb')
class HelperDesktopTest(unittest.TestCase):
    def test_writable_home_blocks_copy_and_explicit_repair_restores_readiness(self):
        import tkinter as tk
        from tkinter import messagebox
        with tempfile.TemporaryDirectory() as folder:
            home = Path(folder).resolve(); home.chmod(0o772)
            original_status = HELPER.permission_status; original_repair = HELPER.repair_permissions
            original_mainloop = tk.Tk.mainloop; captured = {}
            def visit(window):
                def descendants(widget):
                    for child in widget.winfo_children():
                        yield child
                        yield from descendants(child)
                def interact():
                    widgets = list(descendants(window))
                    repair = next(child for child in widgets if child.winfo_class() == 'TButton' and child.cget('text') == 'Fix folder permissions…')
                    if str(repair.cget('state')) != 'normal': window.after(50, interact); return
                    copy = next(child for child in widgets if child.winfo_class() == 'TButton' and child.cget('text') == 'Copy setup card')
                    captured['blocked'] = str(copy.cget('state')) == 'disabled'
                    with mock.patch.object(messagebox, 'askokcancel', return_value=False): repair.invoke()
                    captured['cancelled_mode'] = home.stat().st_mode & 0o777
                    with mock.patch.object(messagebox, 'askokcancel', return_value=True): repair.invoke()
                    window.after(50, lambda: collect(copy))
                def collect(copy):
                    if str(copy.cget('state')) != 'normal': window.after(50, lambda: collect(copy)); return
                    captured['ready'] = True; window.destroy()
                window.after(50, interact); window.after(5000, window.destroy); original_mainloop(window)
            with mock.patch.object(HELPER, 'addresses', return_value=['192.0.2.4']), mock.patch.object(HELPER, 'public_keys', return_value=[{'type': 'ssh-ed25519', 'key': 'synthetic'}]), mock.patch.object(HELPER, 'command', return_value='active\n'), mock.patch.object(HELPER, 'permission_status', side_effect=lambda: original_status(home)), mock.patch.object(HELPER, 'repair_permissions', side_effect=lambda: original_repair(home)), mock.patch.object(tk.Tk, 'mainloop', visit):
                HELPER.main()
            self.assertTrue(captured['blocked']); self.assertTrue(captured['ready'])
            self.assertEqual(captured['cancelled_mode'], 0o772)
            self.assertEqual(home.stat().st_mode & 0o777, 0o750)

    def test_desktop_helper_opens_without_terminal_and_can_copy_a_fresh_card(self):
        import tkinter as tk
        blob = b'\0\0\0\x0bssh-ed25519\0\0\0\x20' + b'x' * 32
        keys = [{'type': 'ssh-ed25519', 'key': base64.b64encode(blob).decode()}]
        captured = {}
        original_mainloop = tk.Tk.mainloop
        def visit(window):
            def descendants(widget):
                for child in widget.winfo_children():
                    yield child
                    yield from descendants(child)
            def interact():
                copy = next(child for child in descendants(window) if child.winfo_class() == 'TButton' and child.cget('text') == 'Copy setup card')
                if str(copy.cget('state')) != 'normal':
                    window.after(50, interact); return
                copy.invoke()
                window.after(50, collect)
            def collect():
                try: captured['card'] = window.clipboard_get()
                except tk.TclError:
                    window.after(50, collect); return
                window.destroy()
            window.after(20, lambda: captured.update(responsive=True))
            window.after(50, interact)
            window.after(5000, window.destroy)
            original_mainloop(window)
        with mock.patch.object(HELPER, 'addresses', return_value=['192.0.2.4']), mock.patch.object(HELPER, 'public_keys', return_value=keys), mock.patch.object(HELPER, 'permission_status', return_value=([], False)), mock.patch.object(HELPER, 'command', return_value='active\n'), mock.patch.object(tk.Tk, 'mainloop', visit):
            HELPER.main()
        value = json.loads(base64.b64decode(captured['card'][8:]))
        self.assertEqual(value['addresses'], ['192.0.2.4'])
        self.assertTrue(captured['responsive'])
        self.assertLess(abs(value['createdAt'] - __import__('time').time()), 5)


if __name__ == '__main__': unittest.main()
