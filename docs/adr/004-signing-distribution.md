# ADR-004: Signing & Distribution — Developer ID + Direct DMG

**Status**: Accepted · **Date**: 2026-08-07

## Context

App extensions are far less tolerant of ad-hoc/self-signed signing than plain apps, and Gatekeeper blocks unsigned/unnotarized downloads for end users. The App Store is the other distribution path, but FinderSync + App Sandbox + "read any file the user right-clicked" is a hostile entitlement combination.

## Decision

- **Development**: self-signed certificate ("Uttr Dev Signing", already trusted in the login keychain) — spike-validated to work for FinderSync locally.
- **Distribution**: **Developer ID + notarization**, shipped as a direct-download DMG. Required from day one of any external release; not deferred.
- **App Store**: out of scope for v1.

## Rationale

- The spike proved self-signed suffices for the local dev loop, so the $99/yr Developer ID purchase does not block development — only release.
- Direct DMG keeps the sandbox story simple: the extension is sandboxed (required), the parent app is not (it must read arbitrary user files handed to it by path).

## Consequences

- `scripts/release-dmg.sh` (future) auto-detects a Developer ID identity and falls back to the dev cert with a loud warning.
- Notarization workflow (`notarytool`) is added at first release milestone.
- The parent app being unsandboxed is a deliberate tradeoff, documented in the privacy section of the README.
