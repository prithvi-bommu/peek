# ADR-005: Local Command-Line Tool Provider

**Status**: Accepted · **Date**: 2026-08-07

## Context

Some users have local AI CLIs (e.g. `llm`, `ollama run` wrappers, private/corporate CLI tools) and no API key, or want responses without any network egress from Peek itself. A prior project validated this pattern: a generic "run a local executable" backend keeps proprietary tooling entirely out of the repo — users point Peek at any script on their machine.

## Decision

Add a third provider, **"Local command-line tool"** (`ProviderID.cli`): Peek runs a user-configured executable, writes the prompt (system prompt + file text) to stdin, and streams stdout into the panel.

## Constraints & lessons encoded

- **Absolute path required**: GUI apps launch with a minimal `PATH`; bare command names don't resolve. The provider validates this up front with a clear error (lesson learned debugging the sibling project).
- **Text-only**: stdin/stdout tools can't take images; image files and scanned-PDF rasters produce an explicit in-panel error pointing at the API providers.
- **Latency**: CLI cold-start can add 5–10 s; noted in the Settings UI so users aren't surprised.
- The command string is not a secret → stored in UserDefaults, not Keychain.

## Consequences

- `needsAPIKey` distinction added to `ProviderID`; Settings shows a command field instead of a key field for this provider.
- stderr is captured and surfaced (truncated) when the tool exits non-zero — never silent failures.
