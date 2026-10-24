#!/bin/bash
set -eu
target=${1:?SSH target required}
if ! [[ "$target" =~ ^[A-Za-z_][A-Za-z0-9_-]*@[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; then
  echo 'Use an SSH target in the form user@hostname.'; exit 1
fi
resources=$(cd "$(dirname "$0")" && pwd)
key="$HOME/.ssh/id_ed25519"
if [ ! -f "$key.pub" ]; then
  echo 'Create an SSH key first with ssh-keygen -t ed25519, then run setup again.'
  exit 1
fi
echo 'ONE-TIME SETUP'
echo '1. Unlock your existing SSH key if it has a passphrase.'
echo '2. Enter the Linux login password to authorise this Mac key.'
echo '3. Enter the Linux sudo password to install the recovery timer.'
echo 'Passwords stay in SSH, the macOS keychain and sudo. The app does not save them.'
echo
ssh-add --apple-use-keychain "$key"
/usr/bin/ssh-copy-id -i "$key.pub" -o ConnectTimeout=10 "$target"
remote_setup=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=yes "$target" 'umask 077; mktemp /tmp/remote-desktops-setup.XXXXXXXX')
if ! [[ "$remote_setup" =~ ^/tmp/remote-desktops-setup\.[A-Za-z0-9]{8}$ ]]; then
  echo 'Unexpected remote temporary path'; exit 1
fi
scp -q "$resources/setup-remote.sh" "$target:$remote_setup"
ssh -t -o StrictHostKeyChecking=yes "$target" "bash '$remote_setup'; result=\$?; rm -f '$remote_setup'; exit \$result"
echo
echo 'Setup complete. Return to Telynd and choose Check status.'
read -r -p 'Press Return to close. ' _
