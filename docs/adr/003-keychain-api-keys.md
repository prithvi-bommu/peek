# ADR-003: API Keys in macOS Keychain

**Status**: Accepted · **Date**: 2026-08-07

## Context

Peek calls Anthropic/OpenAI with user-supplied API keys. The obvious-but-wrong option is a plaintext JSON config file (a pattern that created known security debt in a sibling project). Peek is intended for public distribution, raising the bar.

## Decision

Store API keys in the **macOS Keychain** (`kSecClassGenericPassword`, service `dev.pbommu.peek`, account = provider id) from v1. Non-secret preferences (provider choice, action defaults, popup/silent mode) live in `UserDefaults`. The optional OpenAI `baseURL` override is a non-secret and lives in UserDefaults as well.

## Rationale

- Keys never touch disk in plaintext; survives backup/sync safely.
- Keychain access from a signed app is silent for the creating app — no UX cost.
- Doing it in v1 avoids a painful migration and a public-facing security hole.

## Consequences

- A `KeychainStore` wrapper (~60 lines, Security framework) is part of core scaffolding.
- Re-signing with a different identity can invalidate silent Keychain access during development (macOS prompts once); acceptable for dev, moot after Developer ID.
