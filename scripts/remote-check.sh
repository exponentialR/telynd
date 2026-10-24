#!/bin/bash
set -eu
unit="chrome-remote-desktop@$(id -un).service"
if ! command -v systemctl >/dev/null; then
  echo 'This host does not use systemd. No changes made.'; exit 2
fi
load=$(systemctl show "$unit" -p LoadState --value)
if [ "$load" != loaded ]; then
  echo 'Chrome Remote Desktop service was not found for this account.'; exit 2
fi
state=$(systemctl show "$unit" -p ActiveState --value)
case "$state" in
  active) echo 'Chrome host service is running. Google connection status is not verified.' ;;
  inactive|failed)
    if [ "${1:-check}" = recover ]; then
      helper="/usr/local/libexec/remote-desktops-recover-$(id -u)"
      if [ ! -x "$helper" ]; then echo 'Recovery needs one-time setup in the Mac app.'; exit 3; fi
      sudo -n "$helper"
    else
      echo "Chrome host service is $state. Recovery is available after setup."
      exit 4
    fi ;;
  *) echo "Chrome host is $state. No restart attempted."; exit 5 ;;
esac
