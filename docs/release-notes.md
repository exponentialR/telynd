Telynd 0.2.0 introduces a connection-first setup guide, Chrome profile selection,
connection-only computers, and optional Linux recovery with separate SSH
instructions, verified installation, retry, disable and uninstall actions.

Google Chrome Remote Desktop continues to provide the screen connection and
handle account sign-in and PIN authentication. Linux service status is shown
separately from Google availability.

The first package targets Apple silicon and macOS 13 or later. Runtime checks
currently cover macOS 26 on Apple silicon; earlier macOS versions remain
untested. Settings and the existing app identifier are preserved when updating.

This draft requires the documented quarantined browser-download smoke test
before publication. See BUILD_INFO.txt and SOURCE_REVISION.txt for its build
metadata, and verify the ZIP against SHA256SUMS.
