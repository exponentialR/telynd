#!/bin/bash
# Run only on a disposable Linux runner; touches only its own /run fixture.
set -euo pipefail
[ "${TELYND_DISPOSABLE_LINUX:-}" = 1 ] && [ "$(id -u)" = 0 ] || exit 2
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /run/telynd-path-security.XXXXXXXX)
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/parent/libexec"
chmod 755 "$fixture/parent" "$fixture/parent/libexec"
reject() { if telynd_secure_directories "$1"; then echo "Unsafe path accepted: $1" >&2; exit 1; fi; }
for script in scripts/setup-remote.sh scripts/uninstall-remote.sh scripts/remote-check.sh; do
  # Exercise the actual inline guard, without running any script's main body.
  source <(sed -n '/^telynd_secure_directories() {/,/^}/p' "$script")
  telynd_secure_directories "$fixture/parent/libexec" "$fixture/missing/child"
  chmod g+w "$fixture/parent"
  reject "$fixture/parent/libexec"
  chmod 755 "$fixture/parent"
  chown 65534 "$fixture/parent"
  reject "$fixture/parent/libexec"
  chown 0 "$fixture/parent"
  ln -s "$fixture/parent" "$fixture/link"
  reject "$fixture/link/libexec"
  rm "$fixture/link"
  ln -s "$fixture/absent" "$fixture/dangling"
  reject "$fixture/dangling/child"
  rm "$fixture/dangling"
  reject "$fixture/parent/../parent/libexec"
  reject relative/path
  touch "$fixture/file"
  reject "$fixture/file"
  rm "$fixture/file"
done
echo 'PASS: all Linux guards reject writable/non-root/symlink ancestors and unsafe path forms'
