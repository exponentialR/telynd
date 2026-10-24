#!/bin/bash
# Run on the Linux host as its desktop user; sudo prompts once at installation.
set -eu
desktop_user=$(id -un)
desktop_uid=$(id -u)
case "$desktop_user" in *[!a-zA-Z0-9_-]*|'') echo 'Unsupported account name'; exit 1;; esac
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
cat > "$work/recover" <<EOF
#!/bin/bash
set -eu
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
printf '%s ALL=(root) NOPASSWD: %s\n' "$desktop_user" "$helper" > "$work/sudoers"
# A single administrator authentication installs root-owned files and a narrowly
# scoped permission. Passwords are handled by SSH/sudo, never saved by this app.
sudo bash -s -- "$work" "$helper" "$name" <<'ROOT'
set -eu
work=$1; helper=$2; name=$3
command -v visudo >/dev/null
visudo -cf "$work/sudoers"
install -d -o root -g root -m 755 /usr/local/libexec
install -o root -g root -m 755 "$work/recover" "$helper"
install -o root -g root -m 644 "$work/service" "/etc/systemd/system/$name.service"
install -o root -g root -m 644 "$work/timer" "/etc/systemd/system/$name.timer"
install -o root -g root -m 440 "$work/sudoers" "/etc/sudoers.d/$name"
systemctl daemon-reload
systemctl enable --now "$name.timer"
ROOT
echo 'Automatic recovery installed: every two minutes, only for an enabled, stopped or failed Chrome host.'
echo 'A running service is left alone. Network outages and Google sign-in failures need separate diagnosis.'
