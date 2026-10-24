# Connect your first computer

Telynd opens your existing Google Chrome Remote Desktop connections and can
optionally recover a stopped Linux host service. Google still provides the
remote screen and handles sign-in and the connection PIN.

There is currently **no signed public download**. Developer builds require the
Mac Swift toolchain; [release preparation](releasing.md) records what remains
before normal download-and-open distribution.

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
   choose **Use this computer**, review the browser account and **Save**. No
   copying or second capture click is needed. Detection ends after five minutes,
   cancellation, closing setup or changing the draft. Keep the setup tab in its
   original window. The address does not identify the Google account active in
   the tab; several Google web accounts within one Chrome profile still share
   browsing state. Google handles any sign-in and PIN prompts.
4. Choose **Connect** on the computer's row. Telynd opens its direct link using
   its saved Chrome profile, without a global account switch. Complete Google's
   connection prompts, including its PIN if requested. Telynd records the
   launch; only you can confirm that the remote session connected.
5. Finish with **connection-only access**, or start optional recovery for the
   selected operating system. Add more computers with their own browser accounts.

Saved computers and their browser accounts survive relaunch. Search by computer
name or account. The row's **…** menu offers **Edit computer…**, **Details &
recovery** and **Recovery settings…**. Details contain service checks and launch
history; they do not establish that Google can connect. **Setup guide** is in
the toolbar's help menu. You can close setup and resume its saved progress.

To remove an entry, choose **… → Remove from Telynd…**. The confirmation explains
that Google registration, SSH keys and host recovery remain in place. Use
**Undo** immediately, or **Help → Recently removed computers… → Restore** later,
even after reopening Telynd. To stop host recovery, disable or uninstall it in
Recovery settings before removing the saved entry. A Terminal setup already in
progress continues independently.

Linux recovery now offers a guided **Set up SSH access…** action. You provide or
paste the Linux login/address once; Telynd handles key creation if needed and
authorisation, then checks access after Terminal finishes. **Advanced settings &
diagnostics** holds key paths and maintenance actions. The remote PC still needs
SSH enabled and reachable, and you approve first trust and passwords yourself.
Mac and Windows host kits do not require inbound SSH.

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
