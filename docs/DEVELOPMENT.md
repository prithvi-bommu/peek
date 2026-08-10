# Development Guide

## Prerequisites

- macOS 14+, Xcode 16+
- `brew install xcodegen` (the `.xcodeproj` is generated, not committed)
- A code-signing identity. Development uses the self-signed cert named in `project.yml` (`CODE_SIGN_IDENTITY`); create your own self-signed code-signing cert in Keychain Access and update that field if needed.

## Setting up on a new machine (incl. macOS 26 / Tahoe)

Self-signed certificates live in one Mac's keychain and **do not transfer**. On a fresh machine the build fails with "no identity found", and a Peek.app *copied* from another machine is killed on launch by Gatekeeper (stricter on macOS 26). Do this once per machine:

1. Create a self-signed code-signing cert (Keychain Access → Certificate Assistant → Create a Certificate → name it exactly `Uttr Dev Signing`, type "Code Signing" — reusing the name means `project.yml` needs no edit), or pick your own name and update `CODE_SIGN_IDENTITY`.
2. Build locally with `./scripts/install-local.sh` — never copy a built Peek.app between machines.
3. If you did copy one and it dies instantly: `xattr -d com.apple.quarantine /Applications/Peek.app`, then right-click → Open. Prefer rebuilding.
4. Re-enable the Finder extension in System Settings → Extensions (per-machine setting).

macOS 26 (Tahoe) notes: builds linked against the macOS 26 SDK opt into stricter AppKit layout-reentrancy assertions — the panel's hosting view therefore has `sizingOptions = []` and `safeAreaRegions = []` (do not re-enable content-driven sizing). The Settings window uses `WindowFocus` to avoid opening behind other apps (cooperative-activation quirk of accessory apps).

## Build & install loop

```bash
./scripts/install-local.sh
```

This script: generates the Xcode project → builds → installs to `/Applications` → fixes pluginkit registration → restarts Finder. Run it after every code change you want to test in Finder.

**Why the script matters** (learned the hard way in the de-risking spike): `xcodebuild` registers the *build-directory* copy of the FinderSync appex with pluginkit. If a second copy exists in `/Applications`, extension election silently fails and no menu item appears. The script removes the build products after install and re-registers the `/Applications` copies explicitly.

### First run only

Enable the extension: **System Settings → General → Login Items & Extensions → Extensions → Added Extensions → Peek Finder Extension**.

## Project layout

```
project.yml          xcodegen spec (source of truth; .xcodeproj is generated)
App/                 Parent app (LSUIElement, menu bar item)
  Providers/         AIProvider protocol + Anthropic/OpenAI streaming adapters
  Content/           FileContentLoader — text/PDF/image → PromptContent
  Storage/           KeychainStore (API keys), Preferences (UserDefaults)
  Panel/             ResultPanel (NSPanel) + ResultView (SwiftUI)
  PeekApp.swift      App entry, URL handling, coordinator
FinderExt/           FinderSync extension (menu injection + handoff only)
scripts/             install-local.sh
docs/                PRD, ADRs, this guide
```

## Testing without Finder

The extension handoff is a plain URL — you can exercise the entire pipeline from a terminal:

```bash
open "peek://open?file=/path/to/some/file.md&action=summary"
```

## Debugging tips

- Extension not in the right-click menu? Check `pluginkit -m -v -A | grep -i peek` — the path shown must be `/Applications/Peek.app/...`. If a build-dir path appears, re-run `./scripts/install-local.sh`.
- `pluginkit` and `log show` do not work from sandboxed agent shells; run them in a regular terminal.
- Extension loads but menu missing: `killall Finder` and re-check; confirm the System Settings toggle.
- Streaming issues: set `PEEK_DEBUG=1` (logged via `os_log`, view in Console.app under subsystem `dev.pbommu.peek`).

## Conventions

- No secrets in the repo — keys go in Keychain via the app UI.
- Every non-obvious architectural decision gets an ADR in `docs/adr/`.
- Feature work happens on branches; PRs into `main`.
