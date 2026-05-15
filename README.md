<div align="center">

<img src="tools/Magpie-1024.png" width="140" alt="Magpie" />

# Magpie

**The AI file organizer that respects your wallet, your privacy, and your trash button.**

Open-source · BYO API key · See every cent · Reversible

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform: macOS 13+](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey.svg)](https://www.apple.com/macos/)
[![Swift: 5.9](https://img.shields.io/badge/swift-5.9-orange.svg)](https://swift.org)
[![Status: v0.1](https://img.shields.io/badge/status-v0.1%20preview-yellow.svg)](https://github.com/hsen-hash/magpie/releases)

</div>

---

## What is this

Your `~/Downloads` folder has 200 files in it. Some are screenshots from three months ago. Some are PDFs you renamed twice and lost. One of them is a 4 GB `.dmg` you forgot to delete.

**Magpie** lives in your menu bar and quietly files every new download into a folder called `AI Library/<Category>/`. It uses an LLM you provide (Gemini Flash today, Claude / Ollama next) and **always shows you the price tag**. Every move is reversible. Duplicates are flagged. Rules let you bypass the AI for filenames you already know.

It's the app most people would have built if Sparkle were open-source.

---

## ✨ Why Magpie

|  | What you get |
|---|---|
| 🔑 **Your key, your provider** | Paste a Gemini API key (or your Anthropic / OpenAI / Ollama setup, soon) into a config file. No vendor lock-in, no subscription, no telemetry. |
| 💰 **Cost transparency to the cent** | Dashboard shows every API call: tokens in / out, HTTP status, estimated cost. Menu-bar tooltip shows running monthly spend. |
| ↶ **Reversible by design** | Every move is logged to SQLite. One click puts a file back where it came from. The watcher is told to ignore the reverse-move so you never loop. |
| 📑 **Duplicate detection that works** | SHA-256 scanner with smart exclusions for `node_modules`, `.git`, build artifacts. Per-file Move-to-Trash that uses macOS Trash (recoverable). |
| ✨ **Rules engine** | `*.dmg → Software`, `Screenshot *.png → Screenshots`, or full regex. First match wins; rule-matched files skip the LLM entirely. |
| 🔮 **"Why this category?"** | Gemini's reasoning is captured per move. Spot a pattern → click 🪄 in Activity to turn that AI decision into a rule. |
| 🛟 **Recover from anything** | "Rescue" button re-feeds orphaned files in `Recents/` back through the pipeline if something ever goes wrong. |

---

## 📸 Screenshots

> _Coming as part of v0.1. PRs welcome._

`screenshots/popover.png` · `screenshots/dashboard-activity.png` · `screenshots/dashboard-duplicates.png` · `screenshots/dashboard-api-usage.png`

---

## 🚀 Install

### Option A — download the DMG (recommended)

1. Grab `Magpie-0.1.dmg` from the **[latest release](https://github.com/hsen-hash/magpie/releases/latest)**
2. Open it, drag `Magpie.app` to `Applications`
3. The first time you open it, macOS will warn that it's from an unidentified developer (Magpie isn't notarized — that costs $99/year and Magpie is free). Two ways past the warning:
   - **Right-click** `Magpie.app` → **Open** → **Open** in the dialog (one-time, per-app)
   - Or: `xattr -dr com.apple.quarantine /Applications/Magpie.app` then double-click

A magpie bird icon appears in your menu bar.

### Option B — build from source

Requires macOS 13+ and the Xcode command-line tools.

```bash
git clone https://github.com/hsen-hash/magpie.git ~/Documents/Magpie
cd ~/Documents/Magpie
./build.sh --run         # builds + launches
```

To regenerate the icon at any time:

```bash
./tools/make_icon.sh     # writes tools/Magpie.icns
```

To produce a redistributable DMG:

```bash
./tools/make_dmg.sh      # writes Magpie-0.1.dmg
```

---

## 🔑 Configure your API key

On first launch Magpie creates `~/.config/magpie/config.json` (mode `600`):

```json
{
  "provider": "gemini",
  "geminiApiKey": "PASTE_YOUR_KEY_HERE",
  "geminiModel": "gemini-2.5-flash"
}
```

Get a Gemini API key from <https://aistudio.google.com/apikey>. Paste it into the file, save.

**Security guarantees:**
- File mode is `600` — only you can read it
- Key is sent to Google as an `x-goog-api-key` **header**, never in a URL query string
- URLSession errors are scrubbed before logging, so a stale key can't leak into `/tmp/magpie.log`
- Magpie has no telemetry; the only network call it makes is to Google's Gemini endpoint

You can edit the file later from the popover (🔑 button) or directly:

```bash
open -a TextEdit ~/.config/magpie/config.json
```

---

## 🎯 Daily use

### What you'll see when a file lands in `~/Downloads`

```
T+0s   File lands at ~/Downloads/invoice-acme-2026-04.pdf
T+2s   File moves to ~/Downloads/Recents/invoice-acme-2026-04.pdf
T+5s   Gemini returns "Invoices"
T+5s   File moves to ~/Downloads/AI Library/Invoices/invoice-acme-2026-04.pdf
```

Total time: about 5 seconds. Cost: about $0.0001.

### The bird menu

Click the menu-bar bird to open the popover:

- **Watched folders** — Add or remove with the `+` / `−` buttons (security-scoped bookmarks; survives restart)
- **Process Backlog** — One-click categorize every pre-existing top-level file in your watched folders
- **Rescue *N* in Recents** — Appears only when there are orphaned files; re-feeds them through the pipeline
- **In progress** — Files being categorized right now (with a tiny spinner)
- **Recent moves** — Last 30 filings; ↶ reverts a move to its original location
- **Launch at login** — Switch at the bottom
- **🔑** — Edit your API key in your default editor
- **📊** — Open the Dashboard window

### The Dashboard (📊)

Four tabs:

- **Activity** — Full SQLite move journal. Filter by filename, hide reverted, Reveal in Finder, revert, or 🪄 turn any AI decision into a Rule
- **Rules** — Add/edit/delete/reorder rules. Each row shows its session hit count
- **Duplicates** — Click **Scan now**. SHA-256s every file 4 KB – 500 MB in your watched folders' trees. Per-file "Reveal in Finder" and "Move to Trash"
- **API Usage** — Today / 30 days / all-time cards with estimated cost. Recent calls table with exact prompt / output tokens. Pricing editable inline

### Workflow: stop paying for filenames you already know

1. Drop a few files. Let Gemini categorize them
2. Open Dashboard → Activity. Look at the **Why** column for AI-source rows
3. Spot a clear pattern in a reason like _"Filename starts with `IMG_` and has a JPEG extension"_
4. Click 🪄 on that row → sheet opens with a suggested glob (`IMG_*.jpeg`) and the category pre-filled
5. Save the rule

From now on, every `IMG_*.jpeg` files for free, in milliseconds.

---

## 🆚 Magpie vs. typical alternatives

|  | Magpie | Sparkle.app | Hazel | Maid |
|---|---|---|---|---|
| Source code | ✅ MIT | ❌ | ❌ | ✅ |
| Bring your own LLM | ✅ | ❌ | ❌ (no AI) | ❌ (no AI) |
| Per-call cost transparency | ✅ | ❌ | n/a | n/a |
| Built-in duplicate scanner | ✅ | ❌ | ❌ | ❌ |
| Reversible moves | ✅ | Partial | ✅ | ❌ |
| Rules engine | ✅ | ❌ | ✅ | ✅ |
| AI-suggested rules | ✅ | ❌ | ❌ | ❌ |
| "Why this category?" | ✅ | ❌ | n/a | n/a |
| Local-only mode | 🛣 | ❌ | ✅ | ✅ |
| Price | Free | $30 | $42 | Free |

---

## 🛠️ How it works

```
new file in ~/Downloads
   │
   ▼ FSEvents watcher (2 s debounce, ignores .crdownload / .part)
   │
   ▼ Check rules first (skip API on match)
   │
~/Downloads/Recents/             ← brief staging spot
   │
   ▼ batch of filenames → Gemini Flash → {filename: {category, why}}
   │
~/Downloads/AI Library/<Category>/   ← final home, journaled to SQLite
```

Each watched folder gets three managed children:

- `Recents/` — transient staging for files in flight
- `AI Library/` — sorted by AI / rule into category subfolders
- `Manual Library/` — Magpie never touches anything inside this folder

---

## 🗺️ Roadmap

- [x] Three-folder model (Recents / AI Library / Manual Library)
- [x] FSEvents watcher with 2 s debounce
- [x] Gemini 2.5 Flash categorizer with structured `why` reasoning
- [x] SQLite move journal + revert
- [x] Duplicate scanner (SHA-256 + smart exclusions)
- [x] Rules engine (glob + regex, first-match-wins)
- [x] Suggest-rule-from-AI-decision wand
- [x] Launch at login (`SMAppService`)
- [x] Live cost ticker in menu-bar tooltip
- [ ] **Ollama provider** — fully local categorization, no network call
- [ ] **Anthropic provider** — Claude Haiku as a drop-in option
- [ ] **Perceptual image hashing** — find near-duplicate photos
- [ ] **CLI** — `magpie sort`, `magpie undo last`, `magpie stats`
- [ ] **Plugin hooks** — `post-categorize` shell hook for power users
- [ ] **Notarization** — when there's an Apple Developer account behind the project

---

## 🏗️ Architecture (one paragraph)

Swift Package Manager `executableTarget` bundled into a `.app` via `build.sh` (no Xcode project, no signing). `FolderWatcher` opens an `O_EVTONLY` file descriptor per watched folder, gets FSEvents through a `DispatchSource`, and debounces by 2 s. `CategorizationCoordinator` batches new filenames into chunks of 40, calls the Gemini API, retries once on failure, and re-enqueues hard failures so files never get silently orphaned. `MoveCoordinator` handles the actual filesystem moves with collision-safe renaming and writes one origin-to-final SQLite row per file, enabling revert. `RulesStore` short-circuits the API when a glob or regex matches. The `Dashboard` is a separate `NSWindow` with four SwiftUI tabs. Everything runs on the `MainActor` except the categorizer (`actor` for HTTP) and the dedup scanner (`actor` for the hash loop).

---

## 🤝 Contributing

PRs welcome — especially for:
- A second provider (Anthropic, OpenAI, or Ollama)
- Screenshots in `screenshots/`
- A `magpie sort` CLI binary that shares the categorizer

The whole project is under 3 000 lines of Swift, no external dependencies, no Xcode project to wrangle. Open `Package.swift` and you're in.

---

## 📄 License

[MIT](LICENSE) — do whatever, no warranty.

The three-folder UX (`Recents` / `AI Library` / `Manual Library`) is borrowed from Sparkle's product design. Implementation, code, and feature set are entirely original.
