Telynd 0.3.0 adds **Start SSH** beside each computer's Connect action. It opens
an interactive terminal within Telynd using the saved login and private key,
with disconnect, reconnect, resizing and window-close cleanup. **SSH settings…**
edits connection details independently of Chrome or recovery setup.

Linux setup now distinguishes **Copy browser download link** from **Copy Terminal
install command**. The URL is still pinned to the verified helper 0.2.2. The
Terminal command downloads the package, checks SHA256, asks for administrator
installation and opens Telynd Setup. Download or checksum failures stop before
installation. Existing SSH approval and recovery installation remain separate.

The app bundle version is 0.3.0 (build 3). SwiftTerm is pinned and its release
resources are checked against committed reference copies. Preview packaging
includes source metadata, installation instructions, checksums and explicit
ad-hoc-signing and notarisation status. The signed release pipeline remains
separate and still requires its original Apple and repository prerequisites.

Google Chrome Remote Desktop continues to provide the screen connection and
handle account sign-in and PIN authentication. Linux service status is shown
separately from Google availability.

The package targets Apple silicon and macOS 13 or later. Runtime checks
currently cover macOS 26 on Apple silicon; earlier macOS versions remain
untested. Settings and the existing app identifier are preserved when updating.

Local validation passed 86 Swift tests, including actual local PTY behaviour
and download-command success, checksum-failure and download-failure paths.
The Python suite and release-resource tampering tests are also required.
Live remote SSH login, password and host-trust prompts, and full-screen remote
terminal programs remain untested. These checks do not establish a Google session.

This developer-preview candidate requires green CI for its final source and
the documented quarantined browser-download smoke test before publication.
See BUILD_INFO.txt and SOURCE_REVISION.txt for build metadata and verify the ZIP
against SHA256SUMS. No Developer ID or Apple notarisation is claimed.
