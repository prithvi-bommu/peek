# ADR-002: URL-Scheme Handoff from Extension to Parent App

**Status**: Accepted · **Date**: 2026-08-07

## Context

The FinderSync extension is sandboxed and short-lived; it cannot call APIs or render panels. It must hand the selected file's URL to the parent app. Candidate channels: custom URL scheme (`peek://`), XPC via an embedded XPC service, App Group + Darwin notifications, or NSDistributedNotificationCenter.

## Decision

Use a **custom URL scheme** (`peek://open?file=<path>&action=<summary|explain|insights>`) via `NSWorkspace.open`.

## Rationale

- Validated in the spike: simplest possible channel, launches the parent app if not running (a hard requirement — the LSUIElement app may not be alive when the user right-clicks).
- Payload is tiny (a file path + action name); we never ship file *contents* across the channel, the parent reads the file itself.
- XPC adds real complexity (service lifecycle, protocols) for no v1 benefit.

## Consequences

- File paths appear in the URL; paths are percent-encoded and never logged.
- The parent app must validate that the incoming path exists and is a supported type before acting (defends against arbitrary `peek://` invocations from other apps).
- If v2 needs richer payloads (multi-file, inline context), revisit with an App Group container or XPC.
