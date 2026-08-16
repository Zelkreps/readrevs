# Contributing

## Development Setup

Requirements are macOS 14 or newer and Xcode 26 / Swift 6.2 or newer. The package
uses Apple frameworks and has no third-party package dependencies.

```sh
git clone https://github.com/Zelkreps/readrevs.git
cd readrevs
swift test --disable-sandbox --scratch-path /private/tmp/readrevs-tests
./Scripts/build-app.sh debug
```

## Changes

- Keep Apple Ads access read-only. Do not add campaign create, update, or delete
  operations without an explicit project decision and security review.
- Keep credentials in Keychain and secrets out of fixtures, logs, and screenshots.
- Add focused tests for behavior changes and run the full suite before opening a
  pull request.
- Distinguish Apple-provided metrics from local estimates in code and UI copy.
- Treat review text and external API responses as untrusted data.

Run these checks before submitting a change:

```sh
swift test --disable-sandbox --scratch-path /private/tmp/readrevs-tests
git diff --check
```
