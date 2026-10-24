# Chrome Remote Desktop device import

Decision: retain Google's device picker with explicit capture of its selected
computer's tab address, plus manual-link fallback (#4).
Telynd does not retrieve a Google device inventory or infer a Google device from
an SSH hostname. Duplicate display names cannot establish that mapping.

Research checked on 24 October 2026:

- [Google's consumer access guide](https://support.google.com/chrome/answer/1649523)
  describes connecting through the website and choosing a computer, with Google
  handling account access and PIN authentication. It provides the supported
  user journey used by Telynd.
- [Chromium's directory client](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/remoting/base/directory_service_client.cc)
  implements an OAuth-authenticated host-list operation for Chrome Remote
  Desktop. Its traffic annotation identifies the user's Chrome Remote Desktop
  credentials. Source availability establishes an implementation detail; it
  does not establish a supported third-party API or permission to reuse
  Chrome's OAuth client identity.
- [Chromium's host configuration definitions](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/remoting/host/host_config.h)
  include host identifiers alongside refresh tokens, private keys and PIN
  material. Those host files are inappropriate inventory inputs for this app.

This investigation did not establish a documented public device-list API with
supported third-party OAuth registration, scopes, consent and maintenance
terms. This is a scoped finding, not proof that no such API could exist. No
private endpoint was called, and no cookies, tokens, host configuration or
browser session contents were read to test discovery.

The selected route works without that uncertainty: open the device picker in
an explicitly selected Chrome profile, or paste a Google HTTPS
`/access/session/UUID` link after identifying the computer in Google's UI.
Telynd validates the scheme, exact hostname and supported path. Account
selection is separate from computer selection, and SSH recovery remains
optional. Imported names and identifiers would still require explicit
confirmation before being associated with an SSH destination.

Reconsider import only if Google documents a supported third-party flow. That
work would need its own OAuth/consent design, minimal device metadata, token
storage and revocation policy, duplicate-name handling, failure tests and
provider validation. Do not implement it by scraping an authenticated page or
borrowing Chrome's tokens or client credentials.

The later UI refinement on the same date adds **Use open computer**. After
opening a computer in Google's UI, the user explicitly requests a fixed Apple
event that reads only the URL of Chrome's front active tab. macOS Automation
consent is required; the app validates the exact Google HTTPS session path
before filling a draft. The user reviews and saves it. This does not retrieve
an inventory, infer a Google identity from SSH, read page content or change
the selected Chrome profile. The macOS permission itself permits automation;
the application code limits its request to the one address. Denial leaves
manual entry available.
