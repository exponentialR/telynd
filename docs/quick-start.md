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
3. Name your computer. Keep the default Google device-picker link, or paste
   its own `https://remotedesktop.google.com/access/session/…` address from
   Chrome. Select Mac, Windows or Linux (or leave it unselected). No SSH address is needed.
4. Choose **Open remote desktop**. Complete the connection in Chrome, including
   Google's PIN prompt if requested. Telynd records the launch; only you can
   confirm that the remote session connected.
5. Finish with **connection-only access**, or start optional recovery for the selected operating system.
   More computers can be added from **Add computer**.

You can close the guide and resume its completed steps later. Saved computers
and the selected profile survive relaunch. **Setup guide** reopens the guide;
**Edit** changes a computer's name, connection link or optional SSH address.
Recovery details are available from the computer's card at any time.

If a profile was removed, signed out or switched to a different account, select
its current signed-in profile again. Telynd does not silently choose another
account. Sign-in failures, unavailable computers and PIN problems inside Chrome
are handled through Google, separately from Linux service checks.

For Mac/Windows developer recovery kits, see [platform recovery](platform-recovery.md).

See the [advanced guide](recovery.md) only if you want SSH access or automatic
Linux recovery. You can use Telynd without either.
