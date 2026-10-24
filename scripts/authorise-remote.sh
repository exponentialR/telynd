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
command -v flock >/dev/null || fail 'Linux flock is required for SSH authorisation.'
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
if [ -e "$authorised" ] || [ -L "$authorised" ]; then
  safe_file "$authorised" || fail 'Refusing an unsafe authorized_keys file.'
else
  (set -C; : > "$authorised")
fi
chmod 600 "$authorised"
# Match key identity even when an existing line has a comment or restrictions.
# Never append an unrestricted duplicate of an already restricted key.
if awk -v algorithm="$algorithm" -v material="$material" '
  /^[ \t]*#/ { next }
  { for (i = 1; i < NF; i++) if ($i == algorithm && $(i + 1) == material) found = 1 }
  END { exit !found }
' "$authorised"; then
  echo 'Public key already present; existing restrictions preserved.'
else
  if [ -s "$authorised" ] && [ -n "$(tail -c 1 "$authorised")" ]; then printf '\n' >> "$authorised"; fi
  printf '%s %s\n' "$algorithm" "$material" >> "$authorised"
  echo 'Public key added.'
fi
