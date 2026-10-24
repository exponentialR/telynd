# Connect your first computer

Telynd opens your existing Google Chrome Remote Desktop connections and can
optionally recover a stopped Linux host service. Google still provides the
remote screen and handles sign-in and the connection PIN.

There is currently **no signed public download**. Developer builds require the
Mac Swift toolchain; [release preparation](releasing.md) records what remains
before normal download-and-open distribution.

1. Install Google Chrome and sign into the Chrome profile you use for remote
   access. If the remote computer is not configured, follow
   [Google's setup guide](https://support.google.com/chrome/answer/1649523) first.
2. Open Telynd. In its setup guide, choose your existing Chrome profile from the
   list. If it is missing, open Chrome to sign in and choose **Refresh profiles**.
   The list reflects local Chrome metadata, not a fresh Google authentication
   check.
3. Name your computer. Choose **Choose computer in Chrome** and open the
   intended computer in Google's list. Return to Telynd and choose **Use open
   computer**. macOS asks once for permission for Telynd to interact with Chrome;
   Telynd reads only the front tab's address on this action. Review and save
   the computer. **Connect** then opens it directly. No copying or SSH address
   is needed. Connections use the Chrome profile selected in Telynd.
4. Choose **Connect**. Complete the connection in Chrome, including
   Google's PIN prompt if requested. Telynd records the launch; only you can
   confirm that the remote session connected.
5. Finish with **connection-only access**, or start optional recovery for the selected operating system.
   More computers can be added from **Add computer**.

You can close the guide and resume its completed steps later. Saved computers
and the selected profile survive relaunch. **Setup guide** reopens the guide;
**Edit** changes a computer's name, connection link or optional SSH address.
Expand **Details & recovery** on a card for service checks, launch history
and recovery settings. The home screen shows a compact recovery summary;
it does not claim the computer is online or that Google has connected.

Older entries that saved Google's general device-list link are preserved.
They show **Set connection link** until you save the individual computer's
address. New entries require that address before saving. Choose the remote
operating system under **Optional recovery**, or when setting up recovery later.

If Chrome access is denied, you can enable it under **System Settings → Privacy
& Security → Automation → Telynd**, or expand **Enter link manually** and paste
the individual computer's `https://remotedesktop.google.com/access/session/…`
address. Reading the device-list page or an unrelated tab does not save a
connection. Capturing an address never starts SSH or changes a remote host.

If a profile was removed, signed out or switched to a different account, select
its current signed-in profile again. Telynd does not silently choose another
account. Sign-in failures, unavailable computers and PIN problems inside Chrome
are handled through Google, separately from Linux service checks.

For Mac/Windows developer recovery kits, see [platform recovery](platform-recovery.md).

See the [advanced guide](recovery.md) only if you want SSH access or automatic
Linux recovery. You can use Telynd without either.
