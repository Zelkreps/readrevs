# Privacy

ReadRevs is a local macOS application. It has no analytics, advertising,
telemetry, or project-operated backend.

## Data Stored on This Mac

- App library, keyword research, synced reviews, and Codex research history are
  stored in `~/Library/Application Support/ReadRevs`.
- Apple Ads OAuth identifiers, selected account metadata, eligible Research App,
  and the generated private key are stored as one device-only Keychain item. The
  item is available only while the Mac is unlocked and does not migrate to another
  device.
- Apple OAuth access tokens are cached only in memory and are not persisted.
- Codex model and prompt preferences use the application's standard macOS
  preferences container.

Removing Apple Ads credentials in Settings deletes the local Keychain item. It
does not modify the Apple Ads account or remove the public key registered there.

## Network Requests

The application contacts Apple-operated services only for its built-in research
features:

- `appleid.apple.com` for Apple Ads OAuth tokens.
- `api.ads.apple.com` for Apple Ads Platform API v1 research data.
- `api.searchads.apple.com` to search eligible apps owned by the connected Apple
  Ads organization.
- `itunes.apple.com` for public app metadata, search results, and written-review
  feeds.
- `*.mzstatic.com` and other artwork URLs returned by Apple's App Store APIs to
  display app icons.
- `search.itunes.apple.com` for best-effort localized search hints from an
  undocumented Apple-hosted endpoint.

Requests contain only the identifiers and terms needed for the selected action.
Apple processes these requests under its own terms and privacy policies.

## Optional Codex Analysis

Codex analysis runs only after the user explicitly chooses Analyze. ReadRevs
creates a local bundle containing the selected app's public review data and starts
the locally installed Codex CLI with a read-only sandbox and approvals disabled.
Nothing is sent automatically when the analysis window opens. The Codex CLI and
the account signed into it are governed by their own configuration and terms.

Review text is treated as untrusted input. Generated workspace instructions tell
Codex not to follow links or commands found in reviews, not to use the network,
and not to modify files.

## ReadRevs Migration

On launch, the app checks the local `com.zelkreps.ReadRevs` preferences domain for
apps saved by the original ReadRevs build. It also checks the pre-release
`com.zelkreps.asoresearch` preferences domain and
`~/Library/Application Support/ASO Research` for newer workspace data. Missing
apps, projects, Codex preferences, and completed research history are merged into
ReadRevs. Current ReadRevs values are not replaced, and source files and
preferences are not deleted.

## Deleting Local Data

Remove Apple Ads credentials from Settings before deleting the app if the
Keychain item should also be removed. Other local data can be deleted by removing
`~/Library/Application Support/ReadRevs` after quitting the application.
