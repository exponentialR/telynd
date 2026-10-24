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
3. Choose **Choose computer in Chrome**, which opens Google's list in that
   computer's selected profile. Open the intended computer, return to Telynd
   and choose **Use open computer**. macOS requests permission to interact with
   Chrome; the action reads the front tab's address. Review the account and save
   the computer. The captured address does not identify its Google account or
   change the selected profile. No copying or SSH address is needed.
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

Existing computers inherit their previous global Chrome choice once when this
build first opens. Later computers and unfinished drafts do not inherit that
obsolete preference. Changing a computer's account or connection link clears
its previous launch and user-confirmed connection timestamps.

Older entries that saved Google's general device-list link are preserved.
They show **Set connection** until you save the individual computer's
address. New entries require that address before saving. Choose the remote
operating system under **Optional recovery**, or when setting up recovery later.

If Chrome access is denied, you can enable it under **System Settings → Privacy
& Security → Automation → Telynd**, or expand **Enter link manually** and paste
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
