#!/bin/bash
# Readiness is read-only. Recovery is an explicit, separate mode.
set -eu
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
mode=${1:-check}
case "$mode" in check|recover) ;; *) exit 2;; esac
emit() { printf 'TELYND:%s=%s\n' "$1" "$2"; }
emit ssh ready
if [ "$(uname -s)" != Linux ]; then emit os other; emit systemd unavailable; emit check complete; exit 0; fi
emit os linux
if ! command -v systemctl >/dev/null || ! systemctl show -p Version --value >/dev/null 2>&1; then
  emit systemd unavailable; emit check complete; exit 0
fi
emit systemd available
uid=$(id -u)
unit="chrome-remote-desktop@$(id -un).service"
name="remote-desktops-recovery-$uid"
helper="/usr/local/libexec/remote-desktops-recover-$uid"
status="/usr/local/libexec/remote-desktops-status-$uid"
emit service_loaded "$(systemctl show "$unit" -p LoadState --value)"
emit service "$(systemctl show "$unit" -p ActiveState --value)"
emit chrome_enabled "$(systemctl is-enabled "$unit" 2>/dev/null || true)"
emit timer "$(systemctl show "$name.timer" -p ActiveState --value)"
emit timer_enabled "$(systemctl is-enabled "$name.timer" 2>/dev/null || true)"
missing=''
for tool in flock install sudo sha256sum stat; do command -v "$tool" >/dev/null || missing="$missing $tool"; done
if ! command -v visudo >/dev/null && [ ! -x /usr/sbin/visudo ]; then missing="$missing visudo"; fi
emit missing_tools "${missing# }"
verified=no
if [ "$uid" = 0 ]; then
  emit installation unsupported_root
elif ! telynd_secure_directories /usr/local/libexec /etc/systemd/system /etc/sudoers.d /var/lib/telynd; then
  emit installation unsafe
elif [ -e "$status" ] || [ -L "$status" ]; then
  if [ ! -L "$status" ] && [ "$(stat -c '%u:%a' "$status")" = 0:755 ]; then
    # The root-owned no-argument status helper only reads its installation manifest.
    if output=$(sudo -n "$status" 2>/dev/null); then printf '%s\n' "$output"; verified=yes
    else printf '%s\n' "$output"; emit installation unverified; fi
  else emit installation unsafe; fi
elif [ -e "$helper" ] || [ -L "$helper" ]; then emit installation partial
else emit installation missing
fi
emit check complete
if [ "$mode" = recover ]; then
  [ "$verified" = yes ] || { emit recovery unavailable; exit 3; }
  if sudo -n "$helper"; then emit recovery completed; sudo -n "$status"
  else emit recovery failed; exit 4; fi
fi
