#!/bin/bash
# ONLY on a disposable Linux VM/CI runner: creates a synthetic account and unit.
set -euo pipefail
[ "${TELYND_DISPOSABLE_LINUX:-}" = 1 ] && [ "$(id -u)" = 0 ] || { echo 'Requires root in an explicitly disposable Linux environment.'; exit 2; }
cd "$(dirname "$0")/.."
source_root=$PWD
sandbox=
account=telynd-ci-check
! id "$account" >/dev/null 2>&1 || { echo 'Test account already exists; refusing to reuse it.'; exit 2; }
useradd -m -s /bin/bash "$account"
uid=$(id -u "$account")
unit="chrome-remote-desktop@$account.service"
name="remote-desktops-recovery-$uid"
helper="/usr/local/libexec/remote-desktops-recover-$uid"
status="/usr/local/libexec/remote-desktops-status-$uid"
ledger="/var/lib/telynd/recovery-$uid"
admin=/etc/sudoers.d/telynd-disposable-validation
for path in "$helper" "$status" "$ledger" "$admin" "/etc/systemd/system/$unit" "/etc/systemd/system/$name.service" "/etc/systemd/system/$name.timer" "/etc/sudoers.d/$name"; do
  [ ! -e "$path" ] && [ ! -L "$path" ] || { echo 'An integration target already exists. Stopping.'; userdel -r "$account"; exit 2; }
done
cleanup() {
  systemctl disable --now "$name.timer" "$unit" >/dev/null 2>&1 || true
  systemctl stop "$name.service" >/dev/null 2>&1 || true
  rm -f -- "$helper" "$status" "$admin" "/etc/systemd/system/$unit" "/etc/systemd/system/$name.service" "/etc/systemd/system/$name.timer" "/etc/sudoers.d/$name"
  rm -rf -- "$ledger" "/run/$name"
  systemctl daemon-reload
  userdel -r "$account" >/dev/null 2>&1 || true
  [ -z "$sandbox" ] || rm -rf -- "$sandbox"
}
trap cleanup EXIT
# Hosted-runner home folders may be private. Give only fixture scripts to the
# synthetic account; do not relax permissions on the source checkout.
sandbox=$(mktemp -d /tmp/telynd-integration.XXXXXXXX)
chmod 755 "$sandbox"
mkdir -m 755 "$sandbox/scripts"
cp "$source_root/scripts/setup-remote.sh" "$source_root/scripts/uninstall-remote.sh" "$source_root/scripts/remote-check.sh" "$sandbox/scripts/"
chmod 644 "$sandbox/scripts/"*
root=$sandbox
admin_on() { printf '%s ALL=(root) NOPASSWD: ALL\n' "$account" > "$admin"; chmod 440 "$admin"; }
as_user() { runuser -u "$account" -- bash "$@"; }
check() { as_user "$root/scripts/remote-check.sh" check; }
cat > "/etc/systemd/system/$unit" <<'UNIT'
[Unit]
Description=Synthetic Telynd validation host, no Google registration
[Service]
ExecStart=/bin/sleep infinity
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
admin_on
# A clean runner need not have this directory until its first installation.
mkdir -p /usr/local/libexec
# Unknown files must never be claimed or replaced.
printf 'foreign\n' > "$helper"
if as_user "$root/scripts/setup-remote.sh"; then echo 'Foreign file accepted'; exit 1; fi
[ "$(cat "$helper")" = foreign ]; rm "$helper"
# Simulate interruption between copies using a modified test copy, not a product flag.
partial=$(mktemp /tmp/telynd-partial.XXXXXXXX)
sed '/install -o root -g root -m 755 "\$work\/status"/i false # injected test interruption' "$root/scripts/setup-remote.sh" > "$partial"
chmod 644 "$partial"
if as_user "$partial"; then echo 'Injected failure accepted'; exit 1; fi
rm "$partial"
[ "$(cat "$ledger/result")" = failed ]
check | grep 'TELYND:installation=partial'
as_user "$root/scripts/setup-remote.sh"
# An installed timer must preserve disabled Chrome host enablement and state.
[ "$(systemctl is-enabled "$unit" || true)" = disabled ]
[ "$(systemctl show "$unit" -p ActiveState --value)" = inactive ]
if as_user -c "sudo -n '$helper'"; then echo 'Disabled host accepted'; exit 1; fi
# Remove temporary administrator rights: only the actual product sudoers applies.
rm "$admin"
check | grep 'TELYND:installation=verified'
as_user -c "sudo -n '$status'" | grep 'TELYND:installation=verified'
if as_user -c "sudo -n '$helper' forbidden"; then echo 'Sudoers accepted arguments'; exit 1; fi
if as_user -c 'sudo -n /bin/true'; then echo 'Sudoers granted unrelated access'; exit 1; fi
systemctl enable "$unit"
as_user "$root/scripts/remote-check.sh" recover | grep 'TELYND:recovery=completed'
pid=$(systemctl show "$unit" -p MainPID --value)
check >/dev/null
as_user "$root/scripts/remote-check.sh" recover >/dev/null
[ "$(systemctl show "$unit" -p MainPID --value)" = "$pid" ]
# Permission drift is detected and uninstall refuses to remove changed files.
chmod 777 "$helper"
check | grep 'TELYND:installation=unverified'
admin_on
if as_user "$root/scripts/uninstall-remote.sh" uninstall; then echo 'Unsafe uninstall accepted'; exit 1; fi
[ -f "$helper" ]; chmod 755 "$helper"
as_user "$root/scripts/setup-remote.sh"
# Changed content is never silently replaced or removed.
original=$(mktemp /tmp/telynd-original.XXXXXXXX)
cp "$helper" "$original"
printf '# unexpected drift\n' >> "$helper"
if as_user "$root/scripts/setup-remote.sh"; then echo 'Content drift accepted'; exit 1; fi
if as_user "$root/scripts/uninstall-remote.sh" uninstall; then echo 'Content drift removed'; exit 1; fi
cp "$original" "$helper"; chmod 755 "$helper"; rm "$original"
# Interrupt an upgrade after a new helper has replaced a manifest-recorded file.
upgrade=$(mktemp /tmp/telynd-upgrade.XXXXXXXX)
sed '/^# \/run is root-owned/a # Synthetic upgraded revision' "$root/scripts/setup-remote.sh" > "$upgrade"
chmod 644 "$upgrade"
partial=$(mktemp /tmp/telynd-partial.XXXXXXXX)
sed '/install -o root -g root -m 755 "\$work\/status"/i false # injected upgrade interruption' "$upgrade" > "$partial"
chmod 644 "$partial"
if as_user "$partial"; then echo 'Upgrade interruption accepted'; exit 1; fi
as_user "$upgrade"
rm "$partial" "$upgrade"
# A missing owned component is a retryable partial install.
rm "/etc/systemd/system/$name.timer"
as_user "$root/scripts/setup-remote.sh"
check | grep 'TELYND:installation=verified'
as_user "$root/scripts/uninstall-remote.sh" disable
[ "$(systemctl show "$name.timer" -p ActiveState --value)" = inactive ]
[ "$(systemctl is-enabled "$name.timer" || true)" = disabled ]
as_user "$root/scripts/uninstall-remote.sh" uninstall
as_user "$root/scripts/uninstall-remote.sh" uninstall
[ -f "/etc/systemd/system/$unit" ]
[ "$(systemctl show "$unit" -p MainPID --value)" = "$pid" ]
[ ! -e "$ledger" ] && [ ! -e "$helper" ] && [ ! -e "$status" ]
check | grep 'TELYND:installation=missing'
echo 'PASS: disposable Linux installation, interruption/retry, scope, drift, disable and uninstall'
