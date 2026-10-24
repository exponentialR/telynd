#!/bin/bash
# Disposable Linux only. Real key tools, shell execution, permissions and locks;
# only SSH transport and macOS Keychain are replaced by local fixture adapters.
set -euo pipefail
[ "${TELYND_DISPOSABLE_LINUX:-}" = 1 ] && [ "$(id -u)" = 0 ] || exit 2
cd "$(dirname "$0")/.."
source_root=$PWD
account=telynd-auth-ci
! id "$account" >/dev/null 2>&1 || { echo 'Refusing to reuse a test account.'; exit 2; }
useradd -m -s /bin/bash "$account"
fixture=$(mktemp -d /run/telynd-authorisation.XXXXXXXX)
cleanup() { userdel -r "$account" >/dev/null 2>&1 || true; rm -rf -- "$fixture"; }
trap cleanup EXIT
chmod 755 "$fixture"
desktop_home=$(getent passwd "$account" | cut -d: -f6)
owner=$(id -u "$account")
cp "$source_root/scripts/authorise-remote.sh" "$fixture/authorise-remote.sh"
remote() { runuser -u "$account" -- /bin/sh -c 'cd; exec /bin/sh "$1"' _ "$fixture/authorise-remote.sh"; }
ssh-keygen -q -t ed25519 -N '' -C fixture@example.test -f "$fixture/seed"
ssh-keygen -q -t ed25519 -N '' -C second@example.test -f "$fixture/second"
key=$(awk '{ print $1 " " $2 }' "$fixture/seed.pub")
second=$(awk '{ print $1 " " $2 }' "$fixture/second.pub")
# Validate before touching .ssh, including attempts to supply options or commands.
for invalid in 'command="bad" ssh-ed25519 AAAA' 'ssh-ed25519 bad;command' 'unsupported AAAA'; do
  if printf '%s\n' "$invalid" | remote; then echo 'Invalid input accepted'; exit 1; fi
done
if printf '%s\n%s\n' "$key" "$second" | remote; then echo 'Multiple keys accepted'; exit 1; fi
[ ! -e "$desktop_home/.ssh" ]
printf '%s %s\n' "$key" '$(touch TELYND_COMMENT_EXECUTED) ; `touch TELYND_COMMENT_EXECUTED`' | remote
authorised="$desktop_home/.ssh/authorized_keys"
[ "$(cat "$authorised")" = "$key" ]
[ ! -e "$desktop_home/TELYND_COMMENT_EXECUTED" ]
[ "$(stat -c '%u:%a' "$desktop_home/.ssh")" = "$owner:700" ]
[ "$(stat -c '%u:%a' "$authorised")" = "$owner:600" ]
# Reauthorising must preserve an existing restricted entry byte for byte.
printf '# Existing configuration\ncommand="echo restricted",no-port-forwarding %s existing comment\n' "$key" > "$authorised"
cp "$authorised" "$fixture/expected"
printf '%s\n' "$key" | remote
cmp "$authorised" "$fixture/expected"
# A real read-permission failure must preserve content and permissions.
chmod 200 "$authorised"
if printf '%s\n' "$key" | remote; then echo 'Unreadable key file accepted'; exit 1; fi
cmp "$authorised" "$fixture/expected"
[ "$(stat -c %a "$authorised")" = 200 ]; chmod 600 "$authorised"
# Exercise the unchanged installer logic with an isolated fixture command path.
# Only the fixed PATH is substituted; no production fault-injection flags exist.
fault_index=0
for fault in missing-awk awk-error awk-error-with-output awk-empty awk-unexpected tail-error; do
  fault_index=$((fault_index + 1))
  commands="$fixture/fault-$fault_index"; mkdir "$commands"
  for tool in uname flock stat awk tail id mkdir chmod; do ln -s "$(command -v "$tool")" "$commands/$tool"; done
  case "$fault" in
    missing-awk) rm "$commands/awk";;
    awk-error) rm "$commands/awk"; printf '#!/bin/sh\nexit 2\n' > "$commands/awk";;
    awk-error-with-output) rm "$commands/awk"; printf '#!/bin/sh\necho absent\nexit 2\n' > "$commands/awk";;
    awk-empty) rm "$commands/awk"; printf '#!/bin/sh\nexit 0\n' > "$commands/awk";;
    awk-unexpected) rm "$commands/awk"; printf '#!/bin/sh\necho unexpected\n' > "$commands/awk";;
    tail-error) rm "$commands/tail"; printf '#!/bin/sh\nexit 2\n' > "$commands/tail";;
  esac
  # chmod the new adapters only; never follow the executable symlinks.
  for adapter in "$commands/awk" "$commands/tail"; do [ -L "$adapter" ] || [ ! -e "$adapter" ] || chmod 755 "$adapter"; done
  fault_script="$fixture/fault-$fault_index.sh"
  sed "s|^PATH=/usr/bin:/bin$|PATH=$commands|" "$source_root/scripts/authorise-remote.sh" > "$fault_script"
  candidate=$key
  if [ "$fault" = tail-error ]; then
    printf '# Preserve this unterminated line' > "$authorised"
    candidate=$second
  else
    printf 'command="echo restricted",no-port-forwarding %s existing comment\n' "$key" > "$authorised"
  fi
  cp "$authorised" "$fixture/expected"
  if printf '%s\n' "$candidate" | runuser -u "$account" -- /bin/sh "$fault_script"; then echo "Lookup/read fault accepted: $fault"; exit 1; fi
  cmp "$authorised" "$fixture/expected"
done
# Preserve a final unterminated line when adding another key.
printf '# Keep this line' > "$authorised"
printf '%s' "$second" | remote
printf '# Keep this line\n%s\n' "$second" > "$fixture/expected"
cmp "$authorised" "$fixture/expected"
# Concurrent retries append only one entry.
: > "$authorised"
pids=()
for attempt in 1 2 3 4 5 6; do printf '%s\n' "$key" | remote & pids+=("$!"); done
for pid in "${pids[@]}"; do wait "$pid"; done
[ "$(grep -Fxc "$key" "$authorised")" = 1 ]
printf 'preserve\n' > "$desktop_home/preserved"
chown "$owner" "$desktop_home/preserved"
chmod 600 "$desktop_home/preserved"
rm "$authorised"
ln -s "$desktop_home/preserved" "$authorised"
if printf '%s\n' "$key" | remote; then echo 'Symlink accepted'; exit 1; fi
[ "$(cat "$desktop_home/preserved")" = preserve ]; rm "$authorised"
ln "$desktop_home/preserved" "$authorised"
if printf '%s\n' "$key" | remote; then echo 'Hardlink accepted'; exit 1; fi
[ "$(cat "$desktop_home/preserved")" = preserve ]; rm "$authorised"
rm "$desktop_home/.ssh/.telynd-authorise.lock"
ln -s "$desktop_home/preserved" "$desktop_home/.ssh/.telynd-authorise.lock"
if printf '%s\n' "$key" | remote; then echo 'Symlinked lock accepted'; exit 1; fi
[ "$(cat "$desktop_home/preserved")" = preserve ]; rm "$desktop_home/.ssh/.telynd-authorise.lock"
mv "$desktop_home/.ssh" "$desktop_home/saved-ssh"
ln -s "$desktop_home/saved-ssh" "$desktop_home/.ssh"
if printf '%s\n' "$key" | remote; then echo 'Symlinked directory accepted'; exit 1; fi
rm "$desktop_home/.ssh"; mv "$desktop_home/saved-ssh" "$desktop_home/.ssh"
# Run the actual Mac wrapper through the fixed remote command into this account.
mkdir "$fixture/commands"
cat > "$fixture/commands/ssh" <<'ADAPTER'
#!/bin/bash
set -eu
command=${!#}
[ "$command" != true ] || exit 0
exec /usr/sbin/runuser -u "$TELYND_TEST_ACCOUNT" -- /bin/sh -c "$command"
ADAPTER
printf '#!/bin/sh\nexit 0\n' > "$fixture/commands/ssh-add"
printf '#!/bin/sh\necho Unsafe-helper-invoked >&2\nexit 99\n' > "$fixture/commands/ssh-copy-id"
chmod 755 "$fixture/commands/"*
for name in 'key"quoted' 'key$(touch TELYND_PATH_EXECUTED)' 'key`touch TELYND_PATH_EXECUTED`'; do
  cp "$fixture/seed" "$fixture/$name"; cp "$fixture/seed.pub" "$fixture/$name.pub"
  (cd "$fixture"; PATH="$fixture/commands:$PATH" TELYND_TEST_ACCOUNT="$account" bash "$source_root/scripts/setup-mac.command" reader@fixture.example authorise "$fixture/$name" "$fixture/receipt")
  grep -q '^TELYND:result=ssh_ready$' "$fixture/receipt"
  [ ! -e "$fixture/TELYND_PATH_EXECUTED" ] && [ ! -e "$desktop_home/TELYND_PATH_EXECUTED" ]
done
[ "$(grep -Fxc "$key" "$authorised")" = 1 ]
echo 'PASS: public-key data boundary, restricted entries, retries, permissions, unsafe paths and actual wrapper command'
