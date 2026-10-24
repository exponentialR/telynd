#!/bin/bash
# Run on the Linux host as its desktop user; sudo prompts once at installation.
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
desktop_user=$(id -un)
desktop_uid=$(id -u)
case "$desktop_user" in *[!a-zA-Z0-9_-]*|'') echo 'Unsupported account name'; exit 1;; esac
[ "$desktop_uid" -ne 0 ] || { echo "Run as the desktop account, not root."; exit 1; }
unit="chrome-remote-desktop@${desktop_user}.service"
if [ "$(systemctl show "$unit" -p LoadState --value)" != loaded ]; then
  echo "Cannot find $unit. Nothing installed."; exit 1
fi
systemctl_path=$(command -v systemctl)
flock_path=$(command -v flock)
install_path=$(command -v install)
case "$install_path" in /usr/bin/install|/bin/install) ;; *) echo 'Unexpected install location'; exit 1;; esac
case "$flock_path" in /usr/bin/flock|/bin/flock) ;; *) echo 'Unexpected flock location'; exit 1;; esac
case "$systemctl_path" in /usr/bin/systemctl|/bin/systemctl) ;; *) echo 'Unexpected systemctl location'; exit 1;; esac
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
helper="/usr/local/libexec/remote-desktops-recover-${desktop_uid}"
name="remote-desktops-recovery-${desktop_uid}"
status="/usr/local/libexec/remote-desktops-status-${desktop_uid}"
ledger="/var/lib/telynd/recovery-${desktop_uid}"
cat > "$work/recover" <<EOF
#!/bin/bash
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
[ "\$#" -eq 0 ] || exit 2
# /run is root-owned. A private directory prevents unprivileged users from
# planting a symlink at the lock path used by this root helper.
lock_dir=/run/remote-desktops-recovery-${desktop_uid}
'$install_path' -d -m 700 "\$lock_dir"
exec 9>"\$lock_dir/lock"
'$flock_path' -n 9 || { echo 'A recovery check is already running.'; exit 0; }
unit='$unit'
state=\$('$systemctl_path' show "\$unit" -p ActiveState --value)
case "\$state" in
  active) echo 'Chrome host service is running. No restart needed.' ;;
  inactive|failed)
    if ! '$systemctl_path' is-enabled --quiet "\$unit"; then
      echo 'Chrome host service is disabled. No restart attempted.'; exit 3
    fi
    # start is idempotent if another process has already started the service.
    '$systemctl_path' start "\$unit"
    for attempt in 1 2 3 4 5; do
      if '$systemctl_path' is-active --quiet "\$unit"; then
        echo 'Chrome host service recovered. Check Google Remote Desktop to confirm connection.'; exit 0
      fi
      /bin/sleep 2
    done
    echo 'Service did not become active. Inspect its journal.'; exit 1 ;;
  *) echo "Chrome host is \$state. No restart attempted."; exit 4 ;;
esac
EOF
cat > "$work/service" <<EOF
[Unit]
Description=Recover stopped Chrome Remote Desktop for $desktop_user
After=network-online.target

[Service]
Type=oneshot
ExecStart=$helper
TimeoutStartSec=60
EOF
cat > "$work/timer" <<EOF
[Unit]
Description=Check Chrome Remote Desktop every two minutes for $desktop_user

[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
RandomizedDelaySec=10

[Install]
WantedBy=timers.target
EOF
cat > "$work/status" <<EOF
#!/bin/bash
# No arguments, no writes, and no access to Google account material.
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
[ "\$#" -eq 0 ] || exit 2
ledger='$ledger'
paths=('$helper' '$status' '/etc/systemd/system/$name.service' '/etc/systemd/system/$name.timer' '/etc/sudoers.d/$name')
fail() { echo 'TELYND:installation=partial'; exit 1; }
[ ! -L "\$ledger" ] && [ "\$(stat -c '%u:%a' "\$ledger" 2>/dev/null)" = 0:700 ] || fail
for metadata in marker manifest result; do
  [ -f "\$ledger/\$metadata" ] && [ ! -L "\$ledger/\$metadata" ] && [ "\$(stat -c '%u:%a' "\$ledger/\$metadata")" = 0:600 ] || fail
done
[ "\$(cat "\$ledger/marker")" = 'telynd-v1:$desktop_uid' ] || fail
[ "\$(cat "\$ledger/result")" = installed ] || fail
for i in 0 1 2 3 4; do
  path=\${paths[\$i]}
  case \$i in 0|1) mode=755;; 2|3) mode=644;; 4) mode=440;; esac
  [ -f "\$path" ] && [ ! -L "\$path" ] && [ "\$(stat -c '%u:%a' "\$path")" = "0:\$mode" ] || fail
done
sha256sum --status -c "\$ledger/manifest" || fail
echo 'TELYND:installation=verified'
printf 'TELYND:timer=%s\n' "\$(systemctl show '$name.timer' -p ActiveState --value)"
printf 'TELYND:timer_enabled=%s\n' "\$(systemctl is-enabled '$name.timer' 2>/dev/null || true)"
printf 'TELYND:service=%s\n' "\$(systemctl show '$unit' -p ActiveState --value)"
EOF
# The empty argument strings are significant: sudoers permits no arguments.
printf '%s ALL=(root) NOPASSWD: %s "", %s ""\n' "$desktop_user" "$helper" "$status" > "$work/sudoers"
sudo /bin/bash -s -- "$work" "$helper" "$status" "$name" "$ledger" "$desktop_uid" <<'ROOT'
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
umask 077
work=$1; helper=$2; status=$3; name=$4; ledger=$5; desktop_uid=$6
paths=("$helper" "$status" "/etc/systemd/system/$name.service" "/etc/systemd/system/$name.timer" "/etc/sudoers.d/$name")
fail() { echo "$*" >&2; exit 1; }
install -d -o root -g root -m 700 "/run/$name"
exec 8>"/run/$name/setup.lock"
flock -n 8 || fail 'Another recovery setup operation is running.'
# Refuse unknown files and symlinked state. Never claim ownership of an old install.
for directory in /usr/local/libexec /var/lib/telynd; do
  [ ! -L "$directory" ] || fail "Unexpected symlink: $directory"
  if [ -e "$directory" ]; then
    [ "$(stat -c %u "$directory")" = 0 ] && [ -z "$(find "$directory" -maxdepth 0 -perm /022 -print)" ] || fail "Unsafe directory: $directory"
  fi
done
if [ -e "$ledger" ] || [ -L "$ledger" ]; then
  [ ! -L "$ledger" ] && [ "$(stat -c '%u:%a' "$ledger")" = 0:700 ] || fail 'Unsafe installation record'
  [ -f "$ledger/marker" ] && [ ! -L "$ledger/marker" ] && [ "$(stat -c '%u:%a' "$ledger/marker")" = 0:600 ] && [ "$(cat "$ledger/marker")" = "telynd-v1:$desktop_uid" ] || fail 'Unrecognised installation record'
  if [ -e "$ledger/manifest" ]; then
    [ ! -L "$ledger/manifest" ] && [ "$(stat -c '%u:%a' "$ledger/manifest")" = 0:600 ] || fail 'Unsafe manifest'
    # Missing owned files can follow an interrupted copy/removal. Verify every
    # surviving component before converging on this version's complete set.
    [ "$(wc -l < "$ledger/manifest")" -eq 5 ] || fail 'Incomplete manifest'
    sources=(recover status service timer sudoers)
    for i in 0 1 2 3 4; do
      path=${paths[$i]}
      expected=$(grep -F "  $path" "$ledger/manifest") || fail 'Manifest path mismatch'
      if [ -e "$path" ] || [ -L "$path" ]; then
                [ -f "$path" ] && [ ! -L "$path" ] || fail 'Unexpected installed file type'
        actual=$(sha256sum "$path")
        incoming=$(sha256sum "$work/${sources[$i]}"); incoming=${incoming%% *}
        [ "$actual" = "$expected" ] || [ "${actual%% *}" = "$incoming" ] || fail 'Installed files differ. Review before replacing them.'
      fi
    done
  fi
else
  for path in "${paths[@]}"; do [ ! -e "$path" ] && [ ! -L "$path" ] || fail "Unrecognised component: $path. Nothing replaced."; done
fi
for path in "${paths[@]}"; do [ ! -L "$path" ] || fail "Unexpected symlink: $path"; done
printf 'TELYND:phase=preflight\n'
command -v visudo >/dev/null
visudo -cf "$work/sudoers"
install -d -o root -g root -m 755 /usr/local/libexec /var/lib/telynd
install -d -o root -g root -m 700 "$ledger"
printf 'telynd-v1:%s\n' "$desktop_uid" > "$ledger/marker"
chmod 600 "$ledger/marker"
# Durable outcome survives an interrupted SSH session; retry is safe after review.
trap 'code=$?; if [ "$code" -ne 0 ]; then printf "failed\n" > "$ledger/result"; fi' EXIT
printf 'in_progress\n' > "$ledger/result"
chmod 600 "$ledger/result"
printf 'TELYND:phase=installing\n'
install -o root -g root -m 755 "$work/recover" "$helper"
install -o root -g root -m 755 "$work/status" "$status"
install -o root -g root -m 644 "$work/service" "${paths[2]}"
install -o root -g root -m 644 "$work/timer" "${paths[3]}"
install -o root -g root -m 440 "$work/sudoers" "${paths[4]}"
# Publish a complete manifest atomically; an interrupted copy never looks verified.
sha256sum "${paths[@]}" > "$ledger/manifest.new"
chmod 600 "$ledger/manifest.new"
mv -f "$ledger/manifest.new" "$ledger/manifest"
printf 'TELYND:phase=timer\n'
systemctl daemon-reload
systemctl enable --now "$name.timer"
systemctl is-active --quiet "$name.timer"
systemctl is-enabled --quiet "$name.timer"
printf 'installed\n' > "$ledger/result"
"$status"
printf 'TELYND:phase=complete\n'
ROOT
echo 'Recovery installed and read back: the timer checks every two minutes.'
echo 'Only an enabled, stopped or failed Chrome host is started. Google availability remains unknown.'
