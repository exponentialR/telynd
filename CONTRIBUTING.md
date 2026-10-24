# Contributing to Telynd

Telynd is an early macOS launcher for Chrome Remote Desktop, SSH access and
Linux service recovery. Keep changes focused and preserve the distinction
between a running service and a working Google remote connection.

Build and check changes from the repository root:

```sh
swift test
bash build.sh
python3 -m unittest discover -s tests -v
for script in scripts/*.sh scripts/*.command tests/*.sh build.sh; do bash -n "$script"; done
```

Changes to the privileged recovery helper need tests for the relevant failure
path. Running, disabled and transitioning services must remain undisturbed.
The helper must keep a fixed per-account target and reject all arguments.
Never add broad password-free sudo permissions or disable SSH host-key checks.
Validate every directory ancestor before privileged access. Automated SSH must
disable forwarding and connection reuse, regardless of the user's defaults.

Use fictitious hostnames and accounts in fixtures, screenshots and issue
reports. Keep local configuration, credentials and private host details out of
commits. The app's settings live in Application Support, outside the checkout.

Logo sources and regeneration instructions are in
[`assets/branding/README.md`](assets/branding/README.md). Normal app builds use
the committed branding exports and do not need the font or image tools.

Describe what changed and how it was checked in each pull request. State live
Linux, Google connection or hardware checks separately from mock tests and CI.

Run `tests/linux-integration.sh` only as root on an explicitly disposable Linux
VM or CI runner, with `TELYND_DISPOSABLE_LINUX=1`. It creates a synthetic account,
a synthetic Chrome service and temporary administrator permissions for that
test account. It never validates a Google session. Do not run it on a personal
or production host. See [validation](docs/validation.md) and
[release preparation](docs/releasing.md) for evidence boundaries.

In the same disposable environment, run
`sudo env TELYND_DISPOSABLE_LINUX=1 bash tests/linux-path-security.sh` to test
ancestor guards against writable, non-root-owned and symlinked paths. macOS CI
also validates the real ad-hoc app's signing transport without Apple secrets.
Keep build execution out of the credentialed signing job.

Run `sudo env TELYND_DISPOSABLE_LINUX=1 bash tests/linux-authorisation.sh` only
on the same kind of disposable Linux environment. It creates/removes its own
test account and exercises the actual public-key installer, including its
command/data boundary, permissions, concurrent updates and restricted entries.
Its transport and Keychain adapters do not establish live SSH authentication.

The Ubuntu/Debian desktop helper is built from `linux-helper/`. Regenerate its
bundled package after every helper or packager change:

```sh
python3 scripts/build_linux_helper.py assets/telynd-setup_0.2.0_all.deb
python3 -m unittest discover -s tests -p test_linux_helper.py -v
```

The package has no install-time SSH action. Its fixed administrator action may
install and start OpenSSH, so exercise it only on a disposable Linux machine.
CI installs the package and tests its Tk interface under Xvfb. Pairing cards
contain private network metadata even though their SSH keys are public; use
only synthetic cards in tests and screenshots. Keep pairing probes bounded,
explicit and separate from host trust and login.
