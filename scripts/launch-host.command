#!/bin/bash
set -eu
target=${1:?SSH target required}
if ! [[ "$target" =~ ^[A-Za-z_][A-Za-z0-9_-]*@[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; then
  echo 'Use an SSH target in the form user@hostname.'; exit 1
fi
mode=${2:-connect}
resources=$(cd "$(dirname "$0")" && pwd)
if [ "$mode" = setup ]; then
  exec /bin/bash "$resources/setup-mac.command" "$target"
fi
echo "Checking Chrome Remote Desktop on $target…"
if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=8 -o ServerAliveInterval=10 -o ServerAliveCountMax=2 -o UseKeychain=yes -o AddKeysToAgent=yes -i "$HOME/.ssh/id_ed25519" "$target" 'bash -s -- recover' < "$resources/remote-check.sh"; then
  echo 'Automatic recovery could not be confirmed. Use the app setup button if authentication is required.'
fi
exec ssh -o ConnectTimeout=10 -o UseKeychain=yes -o AddKeysToAgent=yes -i "$HOME/.ssh/id_ed25519" "$target"
