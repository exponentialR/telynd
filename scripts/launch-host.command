#!/bin/bash
set -eu
target=${1:-}
mode=${2:-connect}
key=${3:-"$HOME/.ssh/id_ed25519"}
receipt=${4:-}
resources=$(cd "$(dirname "$0")" && pwd)
case "$mode" in
  authorise|install|disable|uninstall|generate-key) exec /bin/bash "$resources/setup-mac.command" "$target" "$mode" "$key" "$receipt" ;;
  connect) ;;
  *) echo 'Unknown action'; exit 2;;
esac
if ! [[ "$target" =~ ^[A-Za-z_][A-Za-z0-9_-]*@[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; then echo 'Use user@hostname.'; exit 2; fi
. "$resources/ssh-policy.sh"
telynd_ssh_policy ask "$key"
exec ssh "${telynd_ssh_options[@]}" "$target"
