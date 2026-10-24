# Disposable viewer lab

This is a feasibility experiment, not a production viewer or a sign-in client.
It uses a temporary WKWebView store, preserves the real browser user agent,
leaves TLS checks intact and cancels navigation to Google Accounts. No Chrome
cookies or credentials are imported. Events contain fixed labels only and are
written beside the temporary app with owner-only permissions.

Build on macOS from the repository root:

```bash
bash experiments/embedded-viewer/build.sh
```

Open the returned app path normally. Close its window to quit. Unregister and
move the temporary app to Trash after testing; do not install it alongside the
canonical Telynd app.

For a controlled window-mode comparison, the temporary Info.plist can contain
`ProbeProfileDirectories`, an array of at most two existing `Default` or
`Profile N` directory names. Re-sign the temporary bundle after editing it.
Those optional buttons open only Google's public device picker in Chrome app
mode; they do not initiate a remote host connection. Do not publish personal
profile metadata or screenshots of account/device lists.

See the [feasibility record](../../docs/session-viewer.md) for observed results
and the distinction between an intentionally stopped authentication route and
an actual provider authentication failure.
