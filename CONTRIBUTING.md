# Contributing to Telynd

Telynd is an early macOS launcher for Chrome Remote Desktop, SSH access and
Linux service recovery. Keep changes focused and preserve the distinction
between a running service and a working Google remote connection.

Build and check changes from the repository root:

```sh
bash build.sh
python3 -m unittest discover -s tests -v
for script in scripts/*.sh scripts/*.command build.sh; do bash -n "$script"; done
```

Changes to the privileged recovery helper need tests for the relevant failure
path. Running, disabled and transitioning services must remain undisturbed.
The helper must keep a fixed per-account target and reject all arguments.
Never add broad password-free sudo permissions or disable SSH host-key checks.

Use fictitious hostnames and accounts in fixtures, screenshots and issue
reports. Keep local configuration, credentials and private host details out of
commits. The app's settings live in Application Support, outside the checkout.

Logo sources and regeneration instructions are in
[`assets/branding/README.md`](assets/branding/README.md). Normal app builds use
the committed branding exports and do not need the font or image tools.

Describe what changed and how it was checked in each pull request. State live
Linux, Google connection or hardware checks separately from mock tests and CI.
