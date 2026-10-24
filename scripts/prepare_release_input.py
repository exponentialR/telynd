#!/usr/bin/env python3
"""Validate/extract a build artifact as data in a fresh signing job."""
import argparse
import hashlib
from pathlib import Path, PurePosixPath
import plistlib
import re
import stat
import struct
import subprocess
import zipfile

RESOURCES = {
    **{name: f'scripts/{name}' for name in ['macos-recovery.sh', 'windows-recovery.ps1', 'WindowsServicePolicy.cs', 'authorise-remote.sh', 'remote-check.sh', 'setup-remote.sh', 'uninstall-remote.sh', 'setup-mac.command', 'launch-host.command', 'ssh-policy.sh']},
    **{name: f'assets/branding/{name}' for name in ['Telynd.icns', 'telynd-logo-v2.png', 'telynd-logo-dark.png']},
    'chrome-setup.html': 'assets/chrome-setup.html',
    'telynd-setup_0.2.0_all.deb': 'assets/telynd-setup_0.2.0_all.deb',
}
PREFIX = 'Telynd.app/Contents/'
FILES = {PREFIX + 'Info.plist', PREFIX + 'MacOS/Telynd', PREFIX + '_CodeSignature/CodeResources'} | {PREFIX + 'Resources/' + name for name in RESOURCES}
DIRECTORIES = {str(parent) + '/' for file in FILES for parent in PurePosixPath(file).parents if str(parent) != '.'}
LIMIT = 128 * 1024 * 1024


def validate_and_extract(archive, destination, tag, revision):
    if not re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+', tag) or not re.fullmatch(r'[0-9a-f]{40}', revision):
        raise ValueError('Invalid release identity')
    destination = Path(destination)
    if destination.exists() or destination.is_symlink():
        raise ValueError('Signing input must use a new directory')
    data = {}
    with zipfile.ZipFile(archive) as bundle:
        seen = set()
        size = 0
        for entry in bundle.infolist():
            name = entry.filename
            if name in seen or '\\' in name or entry.flag_bits & 1:
                raise ValueError('Duplicate, encrypted or invalid archive member')
            seen.add(name)
            if name not in FILES | DIRECTORIES:
                raise ValueError(f'Unexpected archive member: {name}')
            mode = entry.external_attr >> 16
            kind = stat.S_IFMT(mode)
            if kind not in (0, stat.S_IFDIR if entry.is_dir() else stat.S_IFREG):
                raise ValueError('Archive links and special files are forbidden')
            size += entry.file_size
            if size > LIMIT or len(seen) > 64:
                raise ValueError('Release artifact exceeds limits')
            if not entry.is_dir():
                data[name] = bundle.read(entry)
    if not FILES <= data.keys():
        raise ValueError('The app bundle is incomplete')
    info = plistlib.loads(data[PREFIX + 'Info.plist'])
    required = {'CFBundleExecutable': 'Telynd', 'CFBundleIdentifier': 'com.samueladebayo.telynd', 'CFBundleName': 'Telynd', 'CFBundleDisplayName': 'Telynd', 'CFBundlePackageType': 'APPL', 'CFBundleIconFile': 'Telynd', 'CFBundleShortVersionString': tag[1:], 'LSMinimumSystemVersion': '13.0', 'NSHighResolutionCapable': True, 'NSAppleEventsUsageDescription': 'When you choose a computer, Telynd opens Chrome Remote Desktop and reads that setup tab’s address for up to five minutes. Use open computer reads the front tab once. You confirm before saving.'}
    if set(info) != set(required) | {'CFBundleVersion', 'NSHumanReadableCopyright'} or any(info.get(key) != value for key, value in required.items()):
        raise ValueError('Unexpected release bundle metadata')
    if not isinstance(info['CFBundleVersion'], str) or not info['CFBundleVersion'].isdecimal():
        raise ValueError('Invalid bundle version')
    binary = data[PREFIX + 'MacOS/Telynd']
    if len(binary) < 16 or struct.unpack('<IIII', binary[:16])[0:2] != (0xFEEDFACF, 0x0100000C) or struct.unpack('<IIII', binary[:16])[3] != 2:
        raise ValueError('Expected an ARM64 Mach-O executable')
    # Resolve only fixed blob paths in the validated commit; git cat-file does
    # not execute filters, Package.swift, build scripts or hooks from that tag.
    for name, source in RESOURCES.items():
        blob = f'{revision}:{source}'
        if int(subprocess.check_output(['git', 'cat-file', '-s', blob])) > LIMIT:
            raise ValueError('Source resource exceeds limits')
        expected = subprocess.check_output(['git', 'cat-file', 'blob', blob])
        if hashlib.sha256(expected).digest() != hashlib.sha256(data[PREFIX + 'Resources/' + name]).digest():
            raise ValueError(f'Resource differs from validated source: {name}')
    destination.mkdir(mode=0o700, parents=True)
    for name, content in data.items():
        output = destination / name
        output.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
        with output.open('xb') as file:
            file.write(content)
        output.chmod(0o755 if name == PREFIX + 'MacOS/Telynd' or name.endswith(('.sh', '.command')) else 0o644)
    return destination / 'Telynd.app'


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('archive')
    parser.add_argument('destination')
    parser.add_argument('--tag', required=True)
    parser.add_argument('--revision', required=True)
    args = parser.parse_args()
    try:
        print(validate_and_extract(args.archive, args.destination, args.tag, args.revision))
    except (ValueError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        raise SystemExit(f'Release artifact rejected: {error}')
