# Security Policy

## Reporting a Vulnerability

Do not include Apple Ads credentials, private keys, access tokens, exported review
datasets, or other sensitive data in a public issue.

Use GitHub's private vulnerability reporting or a private Security Advisory for
this repository. Include the affected version, reproduction steps, impact, and a
minimal proof of concept with secrets removed. Please allow time for triage before
public disclosure.

## Credential Handling

ReadRevs generates the Apple Ads private key locally and stores it in macOS
Keychain as `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. The app does not ask
for an Apple ID password and contains no campaign mutation calls.

If credentials may have been exposed:

1. Revoke or replace the API public key in Apple Ads.
2. Remove local credentials in ReadRevs Settings.
3. Generate and register a new key pair.

Never commit `.p8`, `.p12`, `.pem`, `.key`, `.cer`, `.env`, or signing profile
files. These patterns are excluded by the repository's `.gitignore`, but the
person creating a commit remains responsible for reviewing its contents.
