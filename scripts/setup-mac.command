#!/bin/bash
# Passwords and passphrases are handled by SSH, ssh-keygen, Keychain and sudo.
set -euo pipefail
umask 077
target=${1:-}
mode=${2:-authorise}
key=${3:-"$HOME/.ssh/id_ed25519"}
receipt=${4:-}
case "$mode" in setup-access|authorise|install|disable|uninstall|generate-key) ;; *) echo 'Unknown setup action'; exit 2;; esac
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
if [ "$mode" = setup-access ]; then
  echo 'Telynd guided SSH setup. The remote computer must already have SSH enabled.'
  if [ ! -e "$key" ] && [ ! -L "$key" ] && [ ! -e "$key.pub" ] && [ ! -L "$key.pub" ]; then
    echo 'Step 1 of 2: create this Mac’s key. Choose a passphrase when asked.'
    /bin/bash "$0" "$target" generate-key "$key"
  else
    echo 'Step 1 of 2: use the existing key pair. Existing files will not be overwritten.'
  fi
  echo 'Step 2 of 2: approve this Mac on the remote computer.'
fi
[ -f "$key" ] && [ -f "$key.pub" ] || {
  echo 'The selected key pair is incomplete. Existing files have not been overwritten.'
  echo 'In Telynd’s Advanced settings, choose a different unused key path and try Set up SSH access again.'
  result=key_validation_failed; exit 1
}
resources=$(cd "$(dirname "$0")" && pwd)
. "$resources/ssh-policy.sh"
telynd_ssh_policy yes "$key"
if [ "$mode" = authorise ] || [ "$mode" = setup-access ]; then
  result=key_validation_failed
  [ "$(wc -c < "$key.pub")" -le 16384 ] || { echo 'Public key is too large.'; exit 1; }
  public_key=$(cat < "$key.pub")
  case "$public_key" in ''|*$'\n'*|*$'\r'*) echo 'Choose a file containing one SSH public key.'; exit 1;; esac
  printf '%s\n' "$public_key" | ssh-keygen -l -f /dev/stdin >/dev/null
  echo 'Checking that the public key matches the selected private key.'
  echo 'Enter the key passphrase if requested. Keychain setup follows this check.'
  derived_public=$(ssh-keygen -y -f "$key")
  IFS=$' \t' read -r public_type public_material public_comment <<< "$public_key"
  IFS=$' \t' read -r derived_type derived_material derived_comment <<< "$derived_public"
  if [ "$public_type" != "$derived_type" ] || [ "$public_material" != "$derived_material" ]; then
    result=key_pair_mismatch
    echo 'The .pub file does not match the selected private key. Nothing sent to the host.'
    exit 1
  fi
  echo 'Verify any new host fingerprint against a trusted record before accepting it.'
  echo 'Enter your Linux login password directly in SSH. This step does not install recovery.'
  ssh-add --apple-use-keychain "$key"
  result=authentication_failed
  telynd_ssh_policy ask "$key"
  # Only fixed product code is a remote command. Key text travels on stdin;
  # no filename or key content is ever parsed as a shell command.
  remote_command="exec /bin/sh -c '$(sed "s/'/'\\\\''/g" "$resources/authorise-remote.sh")'"
  if printf '%s\n' "$public_key" | ssh -T "${telynd_ssh_options[@]}" "$target" "$remote_command"; then
    :
  else
    code=$?
    if [ "$code" = 23 ]; then result=permissions_need_attention; fi
    exit "$code"
  fi
  telynd_ssh_policy yes "$key"
  result=verification_unavailable
  ssh "${telynd_ssh_options[@]}" -o BatchMode=yes -o StrictHostKeyChecking=yes "$target" true
  result=ssh_ready
  echo 'SSH account access verified using your SSH configuration. Other configured keys may have been used.'
else
  ssh "${telynd_ssh_options[@]}" -o BatchMode=yes -o StrictHostKeyChecking=yes "$target" true
  remote_setup=$(ssh "${telynd_ssh_options[@]}" -o BatchMode=yes -o StrictHostKeyChecking=yes "$target" 'umask 077; mktemp /tmp/telynd-setup.XXXXXXXX')
  if ! [[ "$remote_setup" =~ ^/tmp/telynd-setup\.[A-Za-z0-9]{8}$ ]]; then echo 'Unexpected remote temporary path'; exit 1; fi
  script=setup-remote.sh
  [ "$mode" = install ] || script=uninstall-remote.sh
  scp -q -o BatchMode=yes "${telynd_ssh_options[@]}" "$resources/$script" "$target:$remote_setup"
  ssh -t "${telynd_ssh_options[@]}" -o BatchMode=yes -o StrictHostKeyChecking=yes "$target" "bash '$remote_setup' '$mode'; code=\$?; rm -f '$remote_setup'; exit \$code"
  case "$mode" in install) result=installed;; disable) result=disabled;; uninstall) result=uninstalled;; esac
fi
echo 'Finished. Return to Telynd and recheck readiness for the current state.'
write_receipt
# Completion has been recorded. Closing the finished Terminal must not refresh
# an old result's timestamp or turn a completed setup into a cancellation.
trap - EXIT INT TERM HUP
if [ -t 0 ]; then read -r -p 'Press Return to close. ' _ || true; fi
