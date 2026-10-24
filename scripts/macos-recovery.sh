#!/bin/bash
# Run locally on the remote Mac as its signed-in desktop user. Never run as root.
# No SSH listener, root daemon, Google configuration changes or privacy bypasses.
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
umask 077
fail() { echo "$*" >&2; exit 1; }
[ "$(uname -s)" = Darwin ] || fail 'This recovery kit is for macOS.'
uid=$(id -u)
[ "$uid" -ne 0 ] || fail 'Run as the signed-in desktop account, without sudo.'
mode=${1:-check}; desktop_id=${2:-}
case "$mode" in check|install|recover|tick|disable|uninstall) ;; *) fail 'Unknown action.';; esac
[[ "$desktop_id" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || fail 'Expected the computer ID from its Telynd recovery kit.'
case "$HOME" in /*) ;; *) fail 'Invalid home directory.';; esac
case "$HOME" in *$'\n'*|*$'\r'*|*'&'*|*'<'*|*'>'*|*'"'*|*"'"*) fail 'This home path cannot be represented safely in the launch agent.';; esac
label=com.telynd.recovery
domain="gui/$uid"
folder="$HOME/Library/Application Support/TelyndRecovery"
helper="$folder/macos-recovery.sh"
agent="$HOME/Library/LaunchAgents/$label.plist"
google_plist=/Library/LaunchAgents/org.chromium.chromoting.plist
google_app=/Library/PrivilegedHelperTools/ChromeRemoteDesktopHost.app
google_binary="$google_app/Contents/MacOS/remoting_me2me_host_service"
enabled_marker=/Library/PrivilegedHelperTools/org.chromium.chromoting.me2me_enabled
target="$domain/org.chromium.chromoting"
outcome=checked
lock_owned=false

# An ordinary user agent executes only as that user; still refuse links,
# hardlinks, unsafe ancestors and foreign files instead of repairing them.
safe_tree() {
  local path=$1 current=/ part owner permissions acl
  local -a parts
  IFS=/ read -r -a parts <<< "${path#/}"
  for part in '' "${parts[@]}"; do
    case "$part" in .|..) return 1;; '') ;; *) current="${current%/}/$part";; esac
    [ ! -L "$current" ] || return 1
    if [ -e "$current" ]; then
      [ -d "$current" ] || return 1
      owner=$(stat -f %u "$current"); permissions=$(stat -f %Lp "$current")
      [ "$owner" = 0 ] || [ "$owner" = "$uid" ] || return 1
      (( (8#$permissions & 8#022) == 0 )) || return 1
      # Explicit ACL entries can grant writes beyond the POSIX mode.
      acl=$(ls -lde "$current") || return 1
      ! printf '%s\n' "$acl" | tail -n +2 | grep -q ' allow ' || return 1
    fi
  done
}
safe_file() {
  [ ! -L "$1" ] && [ -f "$1" ] && [ "$(stat -f %u "$1")" = "$uid" ] && [ "$(stat -f %l "$1")" = 1 ] &&
    [ "$(stat -f %Lp "$1")" = "$2" ]
}
safe_tree "$HOME/Library/Application Support" && safe_tree "$HOME/Library/LaunchAgents" || fail 'Unsafe home directory ancestry. Nothing changed.'
if [ -e "$folder" ] || [ -L "$folder" ]; then
  safe_tree "$folder" && [ "$(stat -f %u "$folder")" = "$uid" ] && [ "$(stat -f %Lp "$folder")" = 700 ] || fail 'Unsafe recovery directory.'
fi
owned() {
  safe_file "$folder/manifest" 600 && safe_file "$helper" 700 && safe_file "$agent" 600 &&
    (cd "$folder" && shasum -a 256 -c manifest >/dev/null 2>&1)
}
loaded_ours() {
  local state line
  state=$(launchctl print "$domain/$label" 2>/dev/null) || return 1
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    [ "$line" != "path = $agent" ] || return 0
  done <<< "$state"
  return 1
}
root_tree() {
  local path=$1 acl
  while :; do
    [ ! -L "$path" ] && [ "$(stat -f %u "$path")" = 0 ] || return 1
    local permissions; permissions=$(stat -f %Lp "$path")
    (( (8#$permissions & 8#022) == 0 )) || return 1
    acl=$(ls -lde "$path") || return 1
    ! printf '%s\n' "$acl" | tail -n +2 | grep -q ' allow ' || return 1
    [ "$path" != / ] || break
    path=$(dirname "$path")
  done
}
inspect_google() {
  service=missing; enablement=unknown; recovery=unavailable
  [ -f "$google_plist" ] && [ -d "$google_app" ] || return 0
  root_tree "$google_plist" && root_tree "$google_binary" || fail 'Untrusted Chrome host paths.'
  codesign --verify --deep --strict -R '=anchor apple generic and certificate leaf[subject.OU] = "EQHXZ8M8AV"' "$google_app" 2>/dev/null || fail 'Chrome host signature could not be verified.'
  [ "$(/usr/libexec/PlistBuddy -c 'Print :Label' "$google_plist")" = org.chromium.chromoting ] &&
    [ "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$google_plist")" = "$google_binary" ] &&
    [ "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:1' "$google_plist")" = --run-from-launchd ] || fail 'Unrecognised Chrome launch service.'
  enablement=disabled
  if [ -f "$enabled_marker" ]; then
    root_tree "$enabled_marker" || fail 'Unsafe Chrome enablement marker.'
    local disabled
    disabled=$(launchctl print-disabled "$domain") || fail 'Sign in to the Mac desktop before checking recovery.'
    local plist_disabled
    plist_disabled=$(/usr/libexec/PlistBuddy -c 'Print :Disabled' "$google_plist" 2>/dev/null || true)
    # Do not override either Google's explicit marker or launchd disablement.
    # Newer launchctl prints enabled/disabled; older releases print false/true.
    # An unrecognised explicit value must not be interpreted as enabled.
    if [ "$plist_disabled" != true ]; then
      if ! printf '%s\n' "$disabled" | grep -E '"org[.]chromium[.]chromoting"[[:space:]]*=>' >/dev/null ||
         printf '%s\n' "$disabled" | grep -E '^[[:space:]]*"org[.]chromium[.]chromoting"[[:space:]]*=>[[:space:]]*(false|enabled)[[:space:]]*$' >/dev/null; then enablement=enabled; fi
    fi
  fi
  local state
  if state=$(launchctl print "$target" 2>/dev/null); then
    service=unknown; recovery=stopped-service
    if printf '%s\n' "$state" | grep -Eq '^[[:space:]]*state = (not running|exited|stopped)$'; then service=stopped; fi
    if printf '%s\n' "$state" | grep -Eq '^[[:space:]]*state = running$'; then service=running; fi
    if printf '%s\n' "$state" | grep -Eq '^[[:space:]]*state = (spawning|spawn scheduled|throttled)$'; then service=transitioning; fi
  else service=unknown; fi
}
read_attempts() {
  now=$(date +%s); count=0; start=$now
  if [ -e "$folder/attempts" ] || [ -L "$folder/attempts" ]; then
    safe_file "$folder/attempts" 600 || return 1
    local extra
    read -r start count extra < "$folder/attempts" || return 1
    [[ "$start" =~ ^[1-9][0-9]{0,11}$ && "$count" =~ ^[0-3]$ && -z "$extra" ]] || return 1
    (( start <= now )) || return 1
    if (( now - start >= 1800 )); then start=$now; count=0; fi
  fi
}
report() {
  local installation=missing
  if [ -e "$folder/manifest" ]; then
    installation=drift
    if owned; then
      installation=disabled
      if loaded_ours; then installation=verified
      elif launchctl print "$domain/$label" >/dev/null 2>&1; then installation=drift; fi
    fi
  elif [ -e "$helper" ] || [ -e "$agent" ]; then installation=partial; fi
  # A check must not call recovery ready while a mutation holds the lock, or
  # while an old kit's interrupted directory lock still needs manual review.
  if [ -e "$folder/lock" ] || [ -L "$folder/lock" ]; then installation=partial; fi
  if [ "$lock_owned" = false ] && { [ -e "$folder/operation.lock" ] || [ -L "$folder/operation.lock" ]; }; then
    safe_file "$folder/operation.lock" 600 || fail 'Unsafe recovery lock.'
    if ! (exec 9< "$folder/operation.lock"; lockf -s -t 0 9); then installation=partial; fi
  fi
  if ! read_attempts; then installation=partial; fi
  local version architecture
  version=$(sw_vers -productVersion); architecture=$(uname -m)
  [[ "$version" =~ ^[0-9.]+$ && "$architecture" =~ ^[A-Za-z0-9_]+$ ]] || fail 'Unexpected system version.'
  printf '{"schemaVersion":1,"desktopID":"%s","platform":"macos","osVersion":"%s","architecture":"%s","checkedAt":%s,"service":"%s","enablement":"%s","installation":"%s","recovery":"%s","permissions":"unknown","outcome":"%s"}\n' "$desktop_id" "$version" "$architecture" "$(date +%s)" "$service" "$enablement" "$installation" "$recovery" "$outcome"
}
if [ "$mode" = check ]; then inspect_google; report; exit 0; fi
# Keep one inode for every invocation. The kernel releases the descriptor's
# lock after exit, SIGKILL or reboot; never unlink it while another action runs.
mkdir -p "$folder"; chmod 700 "$folder"
[ ! -e "$folder/lock" ] && [ ! -L "$folder/lock" ] || fail 'A previous kit left a directory lock. Review it before upgrading.'
if [ -e "$folder/operation.lock" ] || [ -L "$folder/operation.lock" ]; then
  safe_file "$folder/operation.lock" 600 || fail 'Unsafe recovery lock.'
fi
exec 9>> "$folder/operation.lock"
lock_status=0
lockf -s -t 0 9 2>/dev/null || lock_status=$?
case "$lock_status" in
  0) ;;
  75) fail 'Another recovery action is running.';;
  *) fail 'This Mac lacks the required native descriptor locking support. Recovery was not installed or changed.';;
esac
lock_owned=true
for file in "$folder/attempts"; do
  if [ -e "$file" ] || [ -L "$file" ]; then safe_file "$file" 600 || fail 'Unsafe recovery state.'; fi
done
if [ "$mode" = install ]; then
  if launchctl print "$domain/$label" >/dev/null 2>&1 && ! loaded_ours; then fail 'The recovery launch label belongs to another job. Nothing replaced.'; fi
  inspect_google
  [ "$enablement" = enabled ] && [ "$recovery" = stopped-service ] || fail 'Enable and register Chrome Remote Desktop, sign in, and check its permissions first.'
  if [ -e "$helper" ] || [ -L "$helper" ] || [ -e "$agent" ] || [ -L "$agent" ] || [ -e "$folder/manifest" ] || [ -L "$folder/manifest" ]; then
    owned || fail 'Existing recovery components differ or setup was interrupted. Review before replacing them.'
    # Upgrades are deliberately explicit: remove the verified old kit first.
    cmp -s "$0" "$helper" || fail 'Uninstall the verified old recovery kit before installing this revision.'
  else
    mkdir -p "$HOME/Library/LaunchAgents"
    cp "$0" "$helper"; chmod 700 "$helper"
    cat > "$agent" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$label</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$helper</string><string>tick</string><string>$desktop_id</string></array>
<key>StartInterval</key><integer>120</integer>
<key>LimitLoadToSessionType</key><string>Aqua</string>
<key>ProcessType</key><string>Background</string>
<key>StandardOutPath</key><string>/dev/null</string>
<key>StandardErrorPath</key><string>/dev/null</string>
</dict></plist>
PLIST
    chmod 600 "$agent"
    shasum -a 256 "$helper" "$agent" > "$folder/manifest"; chmod 600 "$folder/manifest"
  fi
  # enable is explicit on (re)installation. disable must survive a new login.
  launchctl enable "$domain/$label"
  if ! launchctl print "$domain/$label" >/dev/null 2>&1; then launchctl bootstrap "$domain" "$agent"; fi
  owned && loaded_ours || fail 'Installation read-back failed.'
  outcome=installed
elif [ "$mode" = disable ] || [ "$mode" = uninstall ]; then
  owned || fail 'Unrecognised or modified recovery components. Nothing removed.'
  if launchctl print "$domain/$label" >/dev/null 2>&1 && ! loaded_ours; then fail 'The launch label no longer matches this recovery installation.'; fi
  launchctl disable "$domain/$label"
  if launchctl print "$domain/$label" >/dev/null 2>&1; then launchctl bootout "$domain/$label"; fi
  ! launchctl print "$domain/$label" >/dev/null 2>&1 || fail 'Recovery agent is still loaded.'
  outcome=disabled
  if [ "$mode" = uninstall ]; then
    rm "$helper" "$agent" "$folder/manifest"
    [ ! -e "$folder/attempts" ] || rm "$folder/attempts"
    outcome=uninstalled
  fi
else
  owned || fail 'Recovery installation does not match its manifest.'
  inspect_google
  outcome=unchanged
  if [ "$service" = stopped ] && [ "$enablement" = enabled ] && [ "$recovery" = stopped-service ]; then
    read_attempts || fail 'Invalid retry state. Review it before recovery.'
    if (( count >= 3 )); then outcome=retry-limit
    else
      retry_temp=$(mktemp "$folder/attempts.XXXXXXXX")
      if ! printf '%s %s\n' "$start" "$((count + 1))" > "$retry_temp"; then
        rm "$retry_temp"; fail 'Could not write retry state.'
      fi
      mv -f "$retry_temp" "$folder/attempts"
      # No -k: kickstart must not kill an already running host/session.
      launchctl kickstart "$target"
      outcome=started
    fi
  fi
fi
# Removal does not depend on Google's installation remaining healthy. Do not
# turn a completed removal into an apparent failure during an unrelated check.
case "$mode" in
  disable|uninstall) service=unknown; enablement=unknown; recovery=unavailable;;
  *) inspect_google;;
esac
report
