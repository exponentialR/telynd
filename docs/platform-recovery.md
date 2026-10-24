# Recovery for a remote Mac or Windows PC

These are developer source kits, pending real Google-host validation and signed
distribution. You can connect to a Mac, Windows or Linux computer through Google
without enabling recovery. The Telynd client still runs on your Mac.

1. Edit the computer and select its operating system. In **Recovery settings**,
   save the operating system before exporting its kit.
2. Choose **Export recovery kit**, select a new folder, and transfer the entire
   folder to the intended remote computer through a route you trust. Read its
   README and source before executing anything. The exported checksums help
   compare copied files; they do not establish publisher authenticity.
3. First confirm Google remote access works on that computer. Open Terminal on
   a Mac or PowerShell on Windows in the kit folder. Follow the README's `check`
   command. For changes on Windows, use an administrator PowerShell. On Mac,
   use the signed-in desktop account without sudo.
4. Run the explicit `install` command if you want recovery. No change happens
   merely by exporting/importing a kit or opening a connection.
5. Transfer `report.json` back to your controlling Mac and choose **Import host
   report** in that computer's recovery settings. Its computer ID and OS must
   match. The report is an imported snapshot, not a live authenticated check.
   Export/import again for newer evidence. Old results become stale after five
   minutes; relaunching Telynd clears observations.

## Mac limits and removal

The Mac agent checks every two minutes during a signed-in desktop session. It
starts Google's existing loaded job only when enabled and stopped, without
killing an active session. It makes at most three start attempts in 30 minutes.
It does not start before login, override a disabled Google host or grant privacy
permissions. Review Google's screen/control permissions in System Settings on
the host. A signature or unsafe-directory error requires investigation, not
weaker verification.

Run the kit's `disable` command to unload Telynd's agent and keep it disabled
across logins, or `uninstall` to remove
verified owned components. Google remains installed. An interrupted bootstrap
can be retried with the same kit. Native file locks release after interruption;
the empty `operation.lock` file stays in place and must not be deleted. The
host needs native `lockf` descriptor support; older implementations are refused
before changing the helper or launch agent. This is tested on macOS 26, not
a claim of compatibility with earlier host releases. A check
during an active operation reports setup needing attention. Modified/partial
files and a legacy directory named `lock` require review before upgrading.
Do not remove a legacy lock during an active operation. To update the helper,
uninstall the verified old revision first, then install the new kit.

## Windows limits and removal

The optional policy uses Windows' built-in service crash recovery. It requests
two restarts with 60- and 120-second delays, then stops retrying until the native
failure-count reset after a quiet day. Google's installer already has recovery
settings; Telynd records them before applying its bounded policy.

**An orderly service stop is not automatically recovered.** An explicit local
`recover` command can start a stopped verified service only when its start mode
is Automatic. Google uses Manual when deliberately stopping a host; Telynd
reports Manual and Disabled modes as disabled and leaves them stopped. Native
failure handling can also cover error exits if Google's existing flag enables
them. No Telynd background service, task or network listener is installed.

`disable` restores the previous policy; it does not disable Chrome itself and
the original policy may still restart Chrome after crashes. `uninstall` restores
the previous policy and removes the ledger. If the service image/policy has
changed outside Telynd, the kit refuses to overwrite it. Review the change;
do not delete the ledger to force an installation. Ordinary users who cannot
read the private policy ledger may need a read-only check from administrator
PowerShell to obtain installation evidence.

Do not bypass PowerShell execution policy or SmartScreen to install this preview.
Standalone Windows signing and an ordinary downloadable installer remain release
prerequisites. No Windows runtime support claim is established by a Mac build.

See [design and sources](host-recovery-design.md), [Linux recovery](recovery.md),
[validation](validation.md), and [release prerequisites](releasing.md).
