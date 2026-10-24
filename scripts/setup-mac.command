#!/bin/bash
# Passwords and passphrases are handled by SSH, ssh-keygen, Keychain and sudo.
set -eu
umask 077
target=${1:-}
mode=${2:-authorise}
key=${3:-"$HOME/.ssh/id_ed25519"}
receipt=${4:-}
case "$mode" in authorise|install|disable|uninstall|generate-key) ;; *) echo 'Unknown setup action'; exit 2;; esac
result=failed
write_receipt() {
  [ -n "$receipt" ] || return 0
  local temporary
  temporary=$(mktemp "${receipt}.XXXXXXXX")
  printf 'TELYND:action=%s\nTELYND:result=%s\nTELYND:target=%s\nTELYND:identity=%s\n' "$mode" "$result" "$target" "$key" > "$temporary"
  chmod 600 "$temporary"
  mv -f "$temporary" "$receipt"
}
trap 'code=$?; case $code in 130|143) result=cancelled;; esac; write_receipt' EXIT
trap 'result=cancelled; exit 130' INT TERM HUP
result=in_progress; write_receipt; result=failed
case "$key" in /*) ;; *) echo 'Choose an absolute SSH key path.'; exit 2;; esac
case "$key" in *$'\n'*|*$'\r'*) exit 2;; esac
if [ "$mode" = generate-key ]; then
  if [ -e "$key" ] || [ -L "$key" ] || [ -e "$key.pub" ] || [ -L "$key.pub" ]; then
    echo 'A key file already exists at this path. Nothing overwritten.'; exit 1
  fi
  mkdir -p "$(dirname "$key")"
  echo 'Choose a passphrase in the standard SSH prompt. Telynd does not save it.'
  ssh-keygen -t ed25519 -f "$key" -C telynd
  result=key_created; exit 0
fi
if ! [[ "$target" =~ ^[A-Za-z_][A-Za-z0-9_-]*@[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; then
  echo 'Use an SSH target in the form user@hostname.'; exit 2
fi
[ -f "$key" ] && [ -f "$key.pub" ] || { echo 'Choose an existing private key and matching .pub file, or create a key first.'; exit 1; }
resources=$(cd "$(dirname "$0")" && pwd)
ssh_options=(-o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 -o UseKeychain=yes -o AddKeysToAgent=yes -o IdentitiesOnly=yes -i "$key")
if [ "$mode" = authorise ]; then
  echo 'Verify any new host fingerprint against a trusted record before accepting it.'
  echo 'Enter your Linux login password directly in SSH. This step does not install recovery.'
  ssh-add --apple-use-keychain "$key"
  result=authentication_failed
  ssh-copy-id -i "$key.pub" -o "IdentityFile=$key" -o IdentitiesOnly=yes -o ConnectTimeout=10 "$target"
  result=verification_unavailable
  ssh "${ssh_options[@]}" -o BatchMode=yes -o StrictHostKeyChecking=yes "$target" true
  result=ssh_ready
else
  ssh "${ssh_options[@]}" -o BatchMode=yes -o StrictHostKeyChecking=yes "$target" true
  remote_setup=$(ssh "${ssh_options[@]}" -o BatchMode=yes -o StrictHostKeyChecking=yes "$target" 'umask 077; mktemp /tmp/telynd-setup.XXXXXXXX')
  if ! [[ "$remote_setup" =~ ^/tmp/telynd-setup\.[A-Za-z0-9]{8}$ ]]; then echo 'Unexpected remote temporary path'; exit 1; fi
  script=setup-remote.sh
  [ "$mode" = install ] || script=uninstall-remote.sh
  scp -q -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -i "$key" "$resources/$script" "$target:$remote_setup"
  ssh -t "${ssh_options[@]}" -o BatchMode=yes -o StrictHostKeyChecking=yes "$target" "bash '$remote_setup' '$mode'; code=\$?; rm -f '$remote_setup'; exit \$code"
  case "$mode" in install) result=installed;; disable) result=disabled;; uninstall) result=uninstalled;; esac
fi
echo 'Finished. Return to Telynd and recheck readiness for the current state.'
write_receipt
if [ -t 0 ]; then read -r -p 'Press Return to close. ' _ || true; fi
