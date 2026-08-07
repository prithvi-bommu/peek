# Peek 👁️

**Right-click → understand → done.**

Peek is a lightweight macOS utility that adds AI-powered file understanding directly into Finder's right-click menu. Select any file — text document, PDF, image, or screenshot — right-click, choose **Peek**, and get an instant summary, explanation, or key-insights breakdown in a polished floating panel.

No app to open. No window to manage. No copy-pasting into a chat interface.

## How it works

1. Right-click a supported file in Finder → **Peek**
2. The file is read locally (text extracted, or image encoded) and sent to *your* AI provider (Anthropic or OpenAI, your API key)
3. The response streams into a floating frosted-glass panel near your cursor
4. Press `Esc` or click away to dismiss — or use **Silent mode** for clipboard-only, zero-UI operation

## Supported files (v1)

| Category | Types | Handling |
|---|---|---|
| Text | `.txt` `.md` `.csv` `.rtf` | Read directly |
| PDF | `.pdf` | Text extraction; scanned PDFs fall back to page images (vision) |
| Images | `.png` `.jpg` `.jpeg` `.heic` | Sent to a vision-capable model |

## Requirements

- macOS 14 (Sonoma) or later
- One of:
  - An [Anthropic](https://console.anthropic.com/) or [OpenAI](https://platform.openai.com/) API key (stored in the macOS Keychain, never on disk)
  - Any local command-line AI tool that reads a prompt on stdin and writes to stdout (text files only)

## Install (development)

```bash
brew install xcodegen
git clone git@github.com:prithvi-bommu/peek.git && cd peek
./scripts/install-local.sh
```

Then enable the extension: **System Settings → General → Login Items & Extensions → Extensions → Added Extensions → Peek Finder Extension**.

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for the full development guide, and [docs/PRD.md](docs/PRD.md) for the product requirements.

## Architecture (high level)

```
Finder right-click
      │  FinderSync extension (sandboxed, menu injection only)
      ▼  peek:// URL handoff
Peek.app (LSUIElement background app)
      ├─ FileContentLoader   — text extraction / PDF hybrid / image encoding
      ├─ AIProvider          — Anthropic | OpenAI (streaming, pluggable)
      ├─ KeychainStore       — API keys, never on disk
      └─ ResultPanel         — floating NSPanel, streamed response
```

Design decisions are documented as ADRs in [docs/adr/](docs/adr/).

## Privacy

- File contents are sent **only** to the provider you configure, using **your** key
- API keys live in the macOS Keychain
- No telemetry, no accounts, no server of ours in the middle

## License

MIT
