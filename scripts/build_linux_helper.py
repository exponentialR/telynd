#!/usr/bin/env python3
"""Build a reproducible architecture-independent Debian desktop package."""
import argparse
import gzip
import io
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    'usr/lib/telynd-setup/telynd_setup.py': ('linux-helper/telynd_setup.py', 0o644),
    'usr/lib/telynd-setup/prepare-ssh': ('linux-helper/prepare_ssh.py', 0o755),
    'usr/share/polkit-1/actions/org.telynd.setup.policy': ('linux-helper/org.telynd.setup.policy', 0o644),
    'usr/share/icons/hicolor/256x256/apps/telynd.png': ('assets/branding/telynd-app-icon.png', 0o644),
    'usr/share/doc/telynd-setup/copyright': ('LICENSE', 0o644),
}
CONTROL = b'''Package: telynd-setup
Version: 0.2.1
Section: net
Priority: optional
Architecture: all
Maintainer: Telynd contributors <exponentialR@users.noreply.github.com>
Depends: python3, python3-tk, iproute2, pkexec
Homepage: https://github.com/exponentialR/telynd
Description: Prepare a Linux PC for optional Telynd recovery
 A desktop helper that exports public setup details. Enabling SSH is a
 separate administrator-approved action. No Mac is authorised by installing
 this package, and no recovery timer or firewall rule is installed.
'''
LAUNCHER = b'#!/bin/sh\nexec /usr/bin/python3 -I /usr/lib/telynd-setup/telynd_setup.py\n'
DESKTOP = b'''[Desktop Entry]
Type=Application
Name=Telynd Setup
Comment=Prepare this PC for optional remote desktop recovery
Exec=/usr/bin/telynd-setup
Icon=telynd
Terminal=false
Categories=Network;RemoteAccess;
'''


def archive(files):
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode='w', format=tarfile.USTAR_FORMAT) as bundle:
        directories = sorted({str(p) for name in files for p in Path(name).parents if str(p) != '.'})
        for name in directories:
            item = tarfile.TarInfo('./' + name)
            item.type = tarfile.DIRTYPE; item.mode = 0o755; bundle.addfile(item)
        for name, (data, mode) in sorted(files.items()):
            item = tarfile.TarInfo('./' + name)
            item.mode = mode; item.size = len(data)
            bundle.addfile(item, io.BytesIO(data))
    compressed = io.BytesIO()
    with gzip.GzipFile(filename='', fileobj=compressed, mode='wb', mtime=0) as output:
        output.write(stream.getvalue())
    return compressed.getvalue()


def package():
    files = {name: ((ROOT / source).read_bytes(), mode) for name, (source, mode) in SOURCES.items()}
    files['usr/bin/telynd-setup'] = (LAUNCHER, 0o755)
    files['usr/share/applications/telynd-setup.desktop'] = (DESKTOP, 0o644)
    result = bytearray(b'!<arch>\n')
    for name, data in [('debian-binary', b'2.0\n'), ('control.tar.gz', archive({'control': (CONTROL, 0o644)})), ('data.tar.gz', archive(files))]:
        header = f'{name:<16}{0:<12}{0:<6}{0:<6}{0o100644:<8o}{len(data):<10}`\n'.encode('ascii')
        assert len(header) == 60
        result.extend(header); result.extend(data)
        if len(data) % 2: result.extend(b'\n')
    return bytes(result)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.write_bytes(package())
