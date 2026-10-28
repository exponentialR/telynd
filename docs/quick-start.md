# Connect your first computer

Telynd opens your existing Google Chrome Remote Desktop connections and can
optionally recover a stopped Linux host service. Google still provides the
remote screen and handles sign-in and the connection PIN.

## Install the preview

[Download the Apple silicon preview ZIP](https://github.com/exponentialR/telynd/releases/download/v0.2.0-preview.1/Telynd-v0.2.0-preview.1-macos-arm64.zip),
extract it and read `READ_ME_FIRST.txt`. Quit any existing Telynd copy and drag
`Telynd.app` into Applications. Replacing the app preserves saved settings.
You do not need Xcode, Swift or Python on the Mac.

This preview is **not notarised by Apple**. Try opening Telynd normally. If
macOS blocks it and you trust this official download, go to **System Settings
→ Privacy & Security**, scroll to **Security**, and choose **Open Anyway**
beside the Telynd message. Complete any Mac login prompt yourself and confirm
**Open**. This approves the specific app. Do not disable Gatekeeper or remove
quarantine metadata; stop if macOS reports malware or damage. If no approval
appears, report the opening problem instead of weakening security settings.

This package supports Apple silicon only. Runtime validation covers macOS 26;
macOS 13–25 remain untested. See the [release notes and checksums](https://github.com/exponentialR/telynd/releases/tag/v0.2.0-preview.1)
for the exact source and the tested opening journey. Apple signing and
notarisation remain separate work in [release preparation](releasing.md).

## Add your first computer

1. Install Google Chrome and sign into the Chrome profile you use for remote
   access. For separate personal and work accounts, use a Chrome profile for
   each. If the remote computer is not configured, follow
   [Google's setup guide](https://support.google.com/chrome/answer/1649523) first.
2. Choose **Add computer** or follow Telynd's setup guide. Name the computer and
   choose its **Browser account** once. With only one signed-in Chrome profile,
   new computers use it automatically. With several profiles, choose the one
   for this computer. **Refresh accounts** updates the local list; **Open Chrome
   to sign in…** opens Chrome. The list reflects Chrome metadata, not a fresh
   Google authentication check.
3. Choose **Choose computer in Chrome** and allow macOS Automation access if
   prompted. Telynd opens Google's list in a new window using the chosen profile.
   Select the intended computer there. Telynd detects its link automatically in
   that setup tab, including while Chrome is in the background. Return to Telynd,
   choose **Use this computer**, review the browser account and **Continue to recovery**. No
   copying or second capture click is needed. Detection ends after five minutes,
   cancellation, closing setup or changing the draft. Keep the setup tab in its
   original window. The address does not identify the Google account active in
   the tab; several Google web accounts within one Chrome profile still share
   browsing state. Google handles any sign-in and PIN prompts.
4. The **Recovery (optional)** step is visible during Add computer. Choose the
   remote operating system. For Linux, **Save & set up recovery…** saves the computer
   and opens guided pairing with a small setup helper for the Linux PC.
   The helper supplies its login, candidate addresses and public identity;
   Telynd finds a matching route without asking you to choose an IP address. Mac and Windows
   open their host-local recovery-kit setup. **Save connection only** finishes
   adding the computer without configuring recovery; you can add it later.
5. Choose **Connect** on the computer's row. Telynd opens its direct link using
   its saved Chrome profile in a separate session window, without browser tabs
   or a global account switch. This is a Chrome window; the remote screen is
   not embedded inside Telynd. Use **… → Open in Chrome tab** for the tab view. Complete Google's
   connection prompts, including its PIN if requested. Telynd records the
   launch; only you can confirm that the remote session connected.

The setup guide also offers recovery after the first Chrome launch. Add more
computers with their own browser accounts. Editing an existing computer retains
its saved SSH settings; **Save** does not disable or uninstall recovery.

Saved computers and their browser accounts survive relaunch. Search by computer
name or account. The row's **…** menu offers **Edit computer…**, **Details &
recovery** and **Recovery settings…**. Details contain service checks and launch
history; they do not establish that Google can connect. **Setup guide** is in
the toolbar's help menu. You can close setup and resume its saved progress.

## Open an SSH terminal

Choose **Start SSH** on a computer’s row. Telynd opens a native terminal window
using that computer’s saved SSH address and private key. If no address is saved,
enter the username, hostname or IP address and key path first. Use **… → SSH
settings…** to edit them later. SSH settings also supply the Linux recovery route.

SSH must already be enabled and reachable on the remote computer. A Chrome
connection or recovery installation is not required. Password, key-passphrase
and first-use host-trust prompts appear in the embedded terminal. Compare a new
host fingerprint with a trusted record before accepting it. Custom ports can be
configured for the hostname in `~/.ssh/config`; the address field accepts a
hostname or IPv4 address without a port.

The terminal supports normal keyboard input, selection, Copy and Paste,
scrollback and resizing. **Disconnect** ends the SSH connection; **Reconnect**
starts another. Clicking **Start SSH** again brings the existing terminal forward.
Closing its window disconnects SSH. Quitting Telynd ends its SSH sessions. Terminal
output remains in memory and is not saved as a transcript. Recovery approval and
installation continue to use macOS Terminal.

To remove an entry, choose **… → Remove from Telynd…**. The confirmation explains
that Google registration, SSH keys and host recovery remain in place. Use
**Undo** immediately, or **Help → Recently removed computers… → Restore** later,
even after reopening Telynd. Removed entries have no automatic expiry. In that
same screen, **Delete permanently…** deletes an entry after confirmation; it
can no longer be restored. This removes the saved entry only: Google
registration, SSH keys, Terminal launchers/receipts and host recovery stay in
place. To stop host recovery, disable or uninstall it in
Recovery settings before removing the saved entry. A Terminal setup already in
progress continues independently.

For Linux recovery, follow the [guided pairing steps](pairing.md). The desktop
helper currently supports Ubuntu/Debian with a graphical desktop and IPv4.
Copy its download link, open a browser inside the Linux remote desktop and
download/install it there. Existing SSH is not needed. It can enable SSH after
local administrator approval. You bring its setup card
back to this Mac, confirm the PC and choose **Check this computer**. Telynd tests
only the card's listed addresses and compares public host keys; it does not
log in or accept trust. **Use this computer** fills the connection details.
Then **Approve this Mac…** handles key creation and authorisation through
Terminal. You approve first trust and any login/passphrase prompts; automatic
recovery has a separate administrator approval. **Advanced: enter connection
details** remains available for existing SSH users. Both devices still need a
shared reachable network or an existing VPN. Mac and Windows host kits do not
require inbound SSH.

Existing computers inherit their previous global Chrome choice once when this
build first opens. Later computers and unfinished drafts do not inherit that
obsolete preference. Changing a computer's account or connection link clears
its previous launch and user-confirmed connection timestamps.

Older entries that saved Google's general device-list link are preserved.
They show **Set connection** until you save the individual computer's
address. New entries require that address before saving. Choose the remote
operating system under **Optional recovery**, or when setting up recovery later.

If Chrome access is denied, you can enable it under **System Settings → Privacy
& Security → Automation → Telynd**, or expand **Other ways to add a link** and paste
the individual computer's `https://remotedesktop.google.com/access/session/…`
address. Reading the device-list page or an unrelated tab does not save a
connection. Capturing an address never starts SSH or changes a remote host.

If a profile was removed, signed out or switched to a different account, the
row offers **Choose account**. Edit that computer and explicitly select its
current profile again. Telynd does not silently choose another
account. Sign-in failures, unavailable computers and PIN problems inside Chrome
are handled through Google, separately from Linux service checks.

For Mac/Windows developer recovery kits, see [platform recovery](platform-recovery.md).

See the [advanced guide](recovery.md) only if you want SSH access or automatic
Linux recovery. You can use Telynd without either.
