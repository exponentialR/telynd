#!/bin/bash
set -euo pipefail
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
[ "$(uname -s)" = Linux ] || { echo "This recovery installer is for Linux." >&2; exit 2; }
# Check ancestors from / downwards, before traversing or writing a child.
# Kept inline because these scripts are sent to Linux as standalone payloads.
telynd_secure_directories() {
  local directory current component mode
  local -a components
  for directory in "$@"; do
    case "$directory" in /*) ;; *) return 1;; esac
    current=/
    IFS=/ read -r -a components <<< "${directory#/}"
    for component in '' "${components[@]}"; do
      case "$component" in .|..) return 1;; '') ;; *) current="${current%/}/$component";; esac
      [ ! -L "$current" ] || return 1
      if [ -e "$current" ]; then
        [ -d "$current" ] && [ "$(stat -c %u "$current")" = 0 ] || return 1
        mode=$(stat -c %a "$current") || return 1
        (( (8#$mode & 8#022) == 0 )) || return 1
      fi
    done
  done
}
mode=${1:-uninstall}
case "$mode" in disable|uninstall) ;; *) exit 2;; esac
uid=$(id -u)
[ "$uid" -ne 0 ] || { echo 'Run as the desktop account.'; exit 1; }
{
  declare -f telynd_secure_directories
  cat <<'ROOT'
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
uid=$1; mode=$2
name="remote-desktops-recovery-$uid"
ledger="/var/lib/telynd/recovery-$uid"
paths=("/usr/local/libexec/remote-desktops-recover-$uid" "/usr/local/libexec/remote-desktops-status-$uid" "/etc/systemd/system/$name.service" "/etc/systemd/system/$name.timer" "/etc/sudoers.d/$name")
fail() { echo "$*" >&2; exit 1; }
telynd_secure_directories /usr/local/libexec /etc/systemd/system /etc/sudoers.d /var/lib/telynd "/run/$name" || fail 'Unsafe recovery directory ancestry. Nothing changed; administrator review required.'
install -d -o root -g root -m 700 "/run/$name"
exec 8>"/run/$name/setup.lock"
flock -n 8 || fail 'Another recovery setup operation is running.'
if [ ! -e "$ledger" ] && [ ! -L "$ledger" ]; then
  for path in "${paths[@]}"; do [ ! -e "$path" ] && [ ! -L "$path" ] || fail 'Unrecognised components found. Nothing removed.'; done
  echo 'No Telynd installation remains.'; exit 0
fi
[ ! -L "$ledger" ] && [ "$(stat -c '%u:%a' "$ledger")" = 0:700 ] || fail 'Unsafe installation record'
for metadata in marker manifest; do
  [ -f "$ledger/$metadata" ] && [ ! -L "$ledger/$metadata" ] && [ "$(stat -c '%u:%a' "$ledger/$metadata")" = 0:600 ] || fail 'Incomplete installation record. Review required before removal.'
done
[ "$(cat "$ledger/marker")" = "telynd-v1:$uid" ] || fail 'Unrecognised installation'
for i in 0 1 2 3 4; do
  path=${paths[$i]}
  case $i in 0|1) permission=755;; 2|3) permission=644;; 4) permission=440;; esac
  [ -f "$path" ] && [ ! -L "$path" ] && [ "$(stat -c '%u:%a' "$path")" = "0:$permission" ] || fail "Modified or missing component: $path. Nothing removed."
done
sha256sum --status -c "$ledger/manifest" || fail 'Components changed. Nothing removed.'
systemctl disable --now "$name.timer"
[ "$(systemctl show "$name.timer" -p ActiveState --value)" = inactive ] || fail 'Timer did not stop'
[ "$(systemctl is-enabled "$name.timer" 2>/dev/null || true)" = disabled ] || fail 'Timer did not disable'
if [ "$mode" = disable ]; then echo 'Timer disabled and checked.'; exit 0; fi
# Stop any running recovery check before removing the exact files in the record.
systemctl stop "$name.service"
for path in "${paths[@]}"; do rm -- "$path"; done
systemctl daemon-reload
# Retain a private outcome if deletion was interrupted; report success only afterwards.
rm -f -- "$ledger/manifest" "$ledger/marker" "$ledger/result" "$ledger/manifest.new"
rmdir -- "$ledger"
for path in "${paths[@]}"; do [ ! -e "$path" ] && [ ! -L "$path" ] || fail 'Removal was incomplete'; done
echo 'Verified Telynd recovery components removed. Chrome and SSH keys preserved.'
ROOT
} | sudo /bin/bash -s -- "$uid" "$mode"
