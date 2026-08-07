# Peek — Product Requirements Document

> Amended 2026-08-07 after design review and the FinderSync/Quick Action de-risking spike.
> Changes from the original draft are marked **[AMENDED]**.

## 1. Overview

**Peek** is a lightweight macOS utility that adds AI-powered file understanding directly into Finder's right-click menu. Select any file — text document, image, or screenshot — right-click, choose Peek, and get an instant summary, explanation, or key-insights breakdown from the AI provider of your choice (Anthropic or OpenAI). The result appears in a polished floating panel.

**Core promise:** Right-click → understand → done. No app to open, no window to manage, no copy-pasting into a chat interface.

## 2. Problem Statement

Understanding the contents of a file — a dense PDF, a screenshot of an error, a photo of a whiteboard, a text export — usually requires opening a separate AI tool, uploading or pasting the content, waiting, then copying the result back to wherever you actually need it. Existing solutions solve adjacent problems but not this one:

- **Apple Intelligence / Writing Tools** only acts on text already selected inside an app — not on files sitting in Finder.
- **Elephas and similar AI assistants** are heavier, hotkey-driven tools built around an ongoing knowledge base ("brain"), not a single instant action on a single file.
- **Finder utilities (SaneClick, PowerClick)** add real right-click actions but are rule-based utilities (rename, convert, extract) — none perform AI understanding.

Peek fills the specific gap: **arbitrary files, right-click, AI understanding — with minimal setup and no persistent app window.**

## 3. Goals

- Reduce "what does this file say/mean" to a single right-click.
- Support the three file categories people most often need explained: text documents, images, and screenshots.
- Let the user choose which AI provider answers (Anthropic or OpenAI), respecting their existing subscription or API preference.
- Present results in an interface attractive enough to be a selling point on its own, not just a functional necessity.
- Feel completely native to macOS — no Electron bloat, no jarring UI, no unnecessary windows.

## 4. Non-Goals (v1)

- No in-app chat / conversation threads (may be a v2 "follow-up question" feature).
- No persistent knowledge base or file indexing across sessions.
- No batch/multi-file processing in v1 (single file per action).
- No Windows or cross-platform support.
- No first-class local/offline model support in v1. **[AMENDED]** However, the OpenAI provider accepts an optional `baseURL` override in its advanced config (not surfaced in primary UI), which makes any OpenAI-compatible endpoint (Ollama, gateways) usable at zero UI cost.
- No text-selection-within-app integration (Apple already owns that surface).

## 5. Target User

Knowledge workers, developers, students, and researchers on macOS who frequently need a fast read on a file's contents without breaking their workflow to open a separate AI tool.

## 6. Core Functionality

### 6.1 Finder Integration

- Implemented as a **Finder Sync Extension**, injecting a "Peek" item into the right-click context menu.
- **[AMENDED — spike findings 2026-08-07]**:
  - The extension monitors `/` (the standard "appear everywhere" approach for FinderSync).
  - The user must enable the extension once in System Settings → Extensions; a **first-run onboarding screen** guides this step.
  - Registration is path-sensitive: the app must be installed in `/Applications` and registered with pluginkit. The install script and DMG handle this.
  - A **Quick Action (Action Extension)** implementation was validated as a working fallback and remains a documented alternative if FinderSync regresses in a future macOS release.
- Supported file types at launch: plain text (.txt, .md, .csv, .rtf), PDF, common image formats (.png, .jpg, .jpeg, .heic), and screenshots (treated as images).
- Menu item is contextually hidden/disabled for unsupported file types.
- v1 supports a single selected file.

### 6.2 Provider Selection

- User sets a **default AI provider** — Anthropic or OpenAI — in app preferences.
- User supplies their own API key for the chosen provider.
- **[AMENDED]** Keys are stored in the **macOS Keychain from v1** — never in plaintext files.
- Preference is persisted and used silently on every run — no per-action prompt.
- Stretch goal (v1.1): per-action provider override via modifier key or secondary menu item.

### 6.3 Processing Flow

1. User right-clicks a supported file → selects "Peek."
2. Finder Sync Extension passes the file URL to the parent background app (`LSUIElement`, no Dock icon) via the `peek://` URL scheme.
3. Parent app reads/encodes the file (text extraction for documents; base64 image encoding for images/screenshots; PDF hybrid — see §9).
4. Parent app calls the selected provider's API with the content and a task-appropriate prompt (summary / explanation / key insights).
5. Response streams back token by token into the panel.
6. **[AMENDED]** Clipboard behavior:
   - **Popup mode (default): the clipboard is never touched automatically.** A **Copy** button in the panel copies on demand.
   - **Silent mode: auto-copy is the output channel** (no UI); a system notification confirms "Result copied."

### 6.4 Result Presentation

- A floating, non-activating panel (`NSPanel`, `.floating` level) appears near the cursor.
- Visual style: frosted-glass background (`NSVisualEffectView`, HUD material), ~16pt rounded corners, subtle border, soft shadow — native macOS aesthetic.
- Content streams in as it's generated.
- A small provider badge indicates which model produced the result.
- Hover actions: **Copy**, **Regenerate**, **Ask follow-up** (v1.1).
- Dismiss via `Esc`, click-outside, or a close control; quick fade on dismissal.
- **[AMENDED]** Error states render **in the panel** (compact message + **Retry** button). In silent mode, errors surface as a system notification. Failures are never silent.

### 6.5 Preferences

- Default AI provider (Anthropic / OpenAI) and API key (Keychain-backed).
- Default action type (Summary / Explanation / Key Insights), globally or per file category, with an "always ask" option.
- Toggle: **Popup mode** (default) vs. **Silent mode** (clipboard only, no UI).
- Launch-at-login toggle for the background helper app.

## 7. Design Requirements

- Must look and feel like a first-party Apple utility: correct materials, spacing, typography (SF Pro / SF Pro Rounded), subtle fast motion.
- The floating panel is a core differentiator and is treated as a primary design surface.
- Menu bar icon (no Dock icon) for quick access to preferences and provider switching.

## 8. Technical Architecture (High Level)

| Component | Responsibility |
|---|---|
| Finder Sync Extension | Injects right-click menu item; captures selected file URL; hands off via `peek://` URL scheme. Sandboxed, no UI. |
| Parent background app (`LSUIElement`) | Owns API calls, provider preference, Keychain credential storage, renders the floating result panel. |
| Result Panel (`NSPanel` + `NSVisualEffectView`) | Displays streamed AI response; hosts hover actions and error/retry states. |
| Preferences window | Provider, API key, action defaults, popup/silent toggle, launch-at-login. |
| Clipboard writer (`NSPasteboard`) | Writes response text on Copy click (popup mode) or on completion (silent mode only). |

## 9. Resolved Questions **[AMENDED — was "Open Questions"]**

| Question | Decision |
|---|---|
| API key management | User-supplied keys only for v1, stored in Keychain. Managed backend deferred indefinitely. |
| PDF handling | Hybrid: extract text via PDFKit; if extracted text is suspiciously short relative to page count (scanned PDF), rasterize pages and send as images to a vision model. |
| Error/rate-limit surfacing | In-panel error state with Retry; system notification in silent mode. Never fail silently. |
| Distribution | Direct-download DMG with **Developer ID + notarization** (required from day one for reliable extension loading on end-user machines). App Store deferred — sandbox + FinderSync + arbitrary-file-read is a hostile combination. Self-signed works for local development only. |
| Multi-file batch | Deferred (v2 candidate). |

## 10. Success Criteria (v1)

- Right-click-to-result under ~3 seconds perceived latency (via streaming) for typical files.
- Works reliably across all supported file types without crashes or silent failures.
- Popup look-and-feel distinctive enough to be screenshot-worthy for marketing.
- Silent mode delivers the "no interface" experience for power users.
