# Releasing

`Scripts/package-app.sh` builds both `arm64` and `x86_64` executables, combines
them into a Universal 2 app, signs the bundle, creates a local dSYM, and writes a
SHA-256 checksum for the distributable ZIP.

## Local Test Build

```sh
./Scripts/package-app.sh
```

With no environment variables the app receives an ad-hoc signature. This is useful
for local testing but is not a suitable public GitHub download: Gatekeeper cannot
establish a trusted developer identity and the archive is not notarized.

## Public Release

Create a Developer ID Application certificate in the Apple Developer account and
install it in the login Keychain. Store notarization credentials once:

```sh
xcrun notarytool store-credentials readrevs-notary
```

Then package a signed and notarized build:

```sh
READREVS_SIGNING_IDENTITY="Developer ID Application: Example Name (TEAMID)" \
READREVS_NOTARY_PROFILE="readrevs-notary" \
READREVS_VERSION="0.1.0" \
READREVS_BUILD_NUMBER="1" \
./Scripts/package-app.sh
```

The script submits the signed ZIP to Apple, waits for the result, staples the
notarization ticket to the app, recreates the archive, and emits:

- `dist/ReadRevs-v<version>-universal.zip`
- `dist/ReadRevs-v<version>-universal.zip.sha256`

Verify before uploading:

```sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' AppBundle/Info.plist)
codesign --verify --deep --strict --verbose=2 "dist/ReadRevs.app"
spctl --assess --type execute --verbose=4 "dist/ReadRevs.app"
(cd dist && shasum -a 256 -c "ReadRevs-v${VERSION}-universal.zip.sha256")
lipo -archs "dist/ReadRevs.app/Contents/MacOS/ReadRevsApp"
```

Expected architectures are `x86_64 arm64`. Upload the universal ZIP and its
`.sha256` file to the matching GitHub release. Keep
`dist/ReadRevs.app.dSYM` locally for crash diagnosis. Do not upload the dSYM:
Swift debug information can contain absolute source and build paths from the
machine that created it.
