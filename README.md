# Magpie

**Open-source, privacy-respecting AI file organizer for macOS. Bring your own model. See every API call, to the cent.**

<p align="center">
  <img src="tools/Magpie-1024.png" width="160" alt="Magpie icon" />
</p>

Magpie lives in your menu bar and quietly sorts your `~/Downloads` (or any folder you point it at) into AI-categorized subfolders. It's inspired by closed-source tools like Sparkle, but built with three things they don't give you:

1. **Your key, your provider** — drop a Gemini, Claude, or local Ollama API key into a config file. No vendor lock-in.
2. **Full transparency** — a Dashboard shows every API call: tokens in / out, estimated cost, HTTP status. No surprise bills.
3. **Reversibility** — every move is logged to SQLite. One click reverts a file to where it came from.

Plus: a built-in **duplicate scanner** (SHA-256, with smart exclusions for `node_modules` and friends), **backlog processing** for files that landed before you installed it, and a **rescue** button for orphaned files in case anything ever goes wrong.

## How it works

```
new file in ~/Downloads
   │
   ▼ FSEvents watcher (2 s debounce, ignores .crdownload / .part)
   │
~/Downloads/Recents/             ← brief staging spot
   │
   ▼ batch of filenames → Gemini Flash → {filename: category} JSON
   │
~/Downloads/AI Library/<Category>/   ← final home
```

Each watched folder gets three managed children: `Recents/`, `AI Library/`, and `Manual Library/`. Magpie never touches files inside `Manual Library/`.

## Install (from source)

Requires macOS 13+ and the Xcode command-line tools.

```bash
git clone https://github.com/YOU/magpie.git ~/Documents/Magpie
cd ~/Documents/Magpie

# generate the .app bundle
./build.sh

# (optional) regenerate the icon from the procedural script
./tools/make_icon.sh

# launch
open build/Magpie.app
```

The bird icon will appear in your menu bar.

## Configure your API key

On first launch, Magpie creates `~/.config/magpie/config.json`:

```json
{
  "provider": "gemini",
  "geminiApiKey": "PASTE_YOUR_KEY_HERE",
  "geminiModel": "gemini-2.5-flash"
}
```

Get a key from <https://aistudio.google.com/apikey> (or paste any provider you've wired up). The file is created with mode 600 — only you can read it. **The key is never logged**, sent to a server, or embedded in any URL — it goes out in an `x-goog-api-key` header so it can't leak via `URLSession` error descriptions either.

## Dashboard

Click the bird in your menu bar, then the bar-chart icon. Three tabs:

- **Activity** — Every move ever made. Filter, reveal in Finder, revert.
- **Duplicates** — SHA-256-based dedup scanner. Skips `node_modules`, `.git`, `.cache`, `dist`, `build`, `target`, `Pods`, `.venv`, and other dev junk. Per-file "Reveal in Finder" and "Move to Trash" (safe — uses macOS Trash, recoverable).
- **API Usage** — Real prompt/output token counts pulled from the Gemini `usageMetadata` field. Today / 30 days / all-time cards. Edit pricing inline (defaults to Gemini 2.5 Flash: $0.30 / $2.50 per 1 M tokens).

## What makes Magpie different

| | Magpie | Typical commercial alternative |
|---|---|---|
| Source available | ✓ | × |
| Bring your own model | ✓ | × (vendor-bundled) |
| Per-call cost transparency | ✓ | × |
| Duplicate detection | ✓ | × (or paywalled) |
| Revert any move | ✓ | Limited |
| Backlog processing | ✓ | × |
| Sandbox-bypass for full disk access | ✓ | × (App Store restricted) |
| Local-only / Ollama mode | Coming | × |
| Rules engine | Coming | × |

## Roadmap

- [ ] **Rules engine** — user-editable overrides (`*.dmg → Software`) that skip the LLM entirely
- [ ] **"Why this category?"** — store one-sentence justification per move
- [ ] **Privacy mode** — Ollama provider for fully local categorization
- [ ] **Live cost ticker** in the menu-bar tooltip
- [ ] **Perceptual image hashing** (pHash) for duplicate photo dumps
- [ ] **CLI** — `magpie sort`, `magpie undo last`, `magpie stats`
- [ ] **Launch at login** via `SMAppService`

## Architecture (one paragraph)

Swift Package Manager `executableTarget` bundled into a `.app` via `build.sh` (no Xcode project, no signing). `FolderWatcher` opens an `O_EVTONLY` file descriptor per watched folder, gets FSEvents through a `DispatchSource`, and debounces by 2 s. `CategorizationCoordinator` batches new filenames into chunks of 40, calls the Gemini API, retries once on failure, and re-enqueues hard failures so files never get silently orphaned. `MoveCoordinator` handles the actual filesystem moves with collision-safe renaming and writes one origin-to-final SQLite row per file, enabling revert. The `Dashboard` is a separate `NSWindow` with three SwiftUI tabs. Everything runs on the `MainActor` except the categorizer (`actor` for HTTP) and the dedup scanner (`actor` for the hash loop).

## License

MIT.

## Acknowledgments

The three-folder model (`Recents` / `AI Library` / `Manual Library`) is borrowed from Sparkle's product UX. The implementation, code, and feature set are entirely original.
