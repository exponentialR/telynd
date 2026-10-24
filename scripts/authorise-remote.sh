#!/bin/sh
# Fixed Linux-side command. Read a public key as data; never evaluate its text.
set -eu
PATH=/usr/bin:/bin
export PATH
umask 077
fail() { printf '%s\n' "$*" >&2; exit 1; }
[ "$(uname -s)" = Linux ] || fail 'SSH authorisation installation supports Linux hosts.'
public_key=''; extra=''
IFS= read -r public_key || [ -n "$public_key" ] || fail 'No public key received.'
[ "${#public_key}" -le 16384 ] || fail 'Public key is too large.'
if IFS= read -r extra || [ -n "$extra" ]; then fail 'Supply exactly one public key.'; fi
# Discard comments. Options such as command= are deliberately not accepted.
IFS=' 	' read -r algorithm material comment <<EOF
$public_key
EOF
case "$algorithm" in
  ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com) ;;
  *) fail 'Unsupported public-key type or authorised_keys options.';;
esac
case "$material" in ''|*[!A-Za-z0-9+/=]*) fail 'Invalid public-key material.';; esac
for tool in flock stat awk tail id mkdir chmod; do
  command -v "$tool" >/dev/null || fail "Missing SSH authorisation tool: $tool"
done
cd
owner=$(id -u)
[ ! -L .ssh ] || fail 'Refusing a symlinked .ssh directory.'
if [ ! -e .ssh ]; then mkdir -m 700 .ssh; fi
[ -d .ssh ] && [ "$(stat -c %u .ssh)" = "$owner" ] || fail 'Unsafe .ssh directory.'
chmod 700 .ssh
safe_file() {
  [ ! -L "$1" ] && [ -f "$1" ] && [ "$(stat -c %u "$1")" = "$owner" ] && [ "$(stat -c %h "$1")" = 1 ]
}
lock=.ssh/.telynd-authorise.lock
if [ -e "$lock" ] || [ -L "$lock" ]; then safe_file "$lock" || fail 'Unsafe authorisation lock.'; fi
exec 9>>"$lock"
safe_file "$lock" || fail 'Unsafe authorisation lock.'
chmod 600 "$lock"
flock -w 10 9 || fail 'Another SSH authorisation is running. Retry later.'
authorised=.ssh/authorized_keys
lookup=absent
separator=no
if [ -e "$authorised" ] || [ -L "$authorised" ]; then
  safe_file "$authorised" || fail 'Refusing an unsafe authorized_keys file.'
  # Match identity even on restricted entries. Successful absence is explicit;
  # an execution/read error must never become permission to append a key.
  lookup=$(awk -v algorithm="$algorithm" -v material="$material" '
  /^[ \t]*#/ { next }
  { for (i = 1; i < NF; i++) if ($i == algorithm && $(i + 1) == material) found = 1 }
  END { print found ? "present" : "absent" }
  ' "$authorised") || fail 'Could not check existing authorised keys. Nothing appended.'
  case "$lookup" in present|absent) ;; *) fail 'Unexpected key lookup result. Nothing appended.';; esac
  if [ "$lookup" = absent ] && [ -s "$authorised" ]; then
    last_byte=$(tail -c 1 "$authorised") || fail 'Could not read the final key-file byte. Nothing appended.'
    [ -z "$last_byte" ] || separator=yes
  fi
fi
if [ "$lookup" = present ]; then
  chmod 600 "$authorised"
  echo 'Public key already present; existing restrictions preserved.'
else
  if [ ! -e "$authorised" ]; then (set -C; : > "$authorised"); fi
  chmod 600 "$authorised"
  [ "$separator" = no ] || printf '\n' >> "$authorised"
  printf '%s %s\n' "$algorithm" "$material" >> "$authorised"
  echo 'Public key added.'
fi
