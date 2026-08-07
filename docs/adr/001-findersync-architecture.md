# ADR-001: FinderSync Extension for Finder Integration

**Status**: Accepted · **Date**: 2026-08-07

## Context

Peek's core promise is a right-click menu item in Finder. macOS offers several surfaces: FinderSync extensions (top-level context-menu items), Quick Actions / Action extensions (a submenu), the legacy Services menu, and global-hotkey approaches. FinderSync has known sharp edges: it requires declaring "monitored directories" (apps monitor `/` to appear everywhere), a manual one-time enable in System Settings, and registration is sensitive to install path and code signing.

## Decision

Build v1 on a **FinderSync extension** monitoring `/`, with handoff to the parent app. A Quick Action implementation is kept as a documented, spike-validated fallback.

## Rationale

A de-risking spike (2026-08-07, macOS 15.7, Xcode 16.4) validated end-to-end:

- The FinderSync menu item renders top-level in the context menu (directly below Quick Actions) — better discoverability than the Quick Actions submenu.
- Works with a self-signed certificate for local development.
- Click → file URL capture → URL-scheme handoff to the parent app all function.

Spike gotchas that shaped the tooling:

- `xcodebuild` registers the *build directory* copy of the appex with pluginkit; a duplicate in `/Applications` then fails to elect. The install script (`scripts/install-local.sh`) removes stale registrations and registers the `/Applications` copy explicitly.
- The user must enable the extension once in System Settings → General → Login Items & Extensions → Extensions.

## Consequences

- First-run onboarding must guide the System Settings enable step.
- Distribution requires Developer ID + notarization (see ADR-004).
- If a future macOS release degrades FinderSync, the Quick Action fallback (validated in the spike repo) is the escape hatch.
