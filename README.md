<div align="center">

<img src="tools/Magpie-1024.png" width="140" alt="Magpie" />

# Magpie

**The AI file organizer that respects your wallet, your privacy, and your trash button.**

Open-source · BYO API key · See every cent · Reversible

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform: macOS 13+](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey.svg)](https://www.apple.com/macos/)
[![Swift: 5.9](https://img.shields.io/badge/swift-5.9-orange.svg)](https://swift.org)
[![Status: v0.3](https://img.shields.io/badge/status-v0.3%20preview-yellow.svg)](https://github.com/hsen-hash/magpie/releases)

</div>

---

## What is this

Your `~/Downloads` folder has 200 files in it. Some are screenshots from three months ago. Some are PDFs you renamed twice and lost. One of them is a 4 GB `.dmg` you forgot to delete.

**Magpie** lives in your menu bar and quietly files every new download into a folder called `AI Library/<Category>/`. It uses an LLM you provide (Gemini Flash, or **Ollama for fully local categorization** with no network call — Claude coming next) and **always shows you the price tag**. Every move is reversible. Duplicates are flagged. Rules let you bypass the AI for filenames you already know.

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
| 📂 **Open straight from Recent moves** | Just filed something and need it now? Open it in its default app or reveal it in Finder right from the menu-bar popover — double-click the row, or use the ↗ / 🔍 buttons. |
| 🗓️ **Daily clutter digest** | Once a day (or on demand) Magpie scans your folders and writes a plain-language summary: what got filed, what's piling up in `Recents/`, how much space duplicates are wasting — plus concrete tips to stay tidy. Local heuristics always; an AI narrative on top via your configured provider ($0 on Ollama). Pings you with a notification. |

---

## 📸 Screenshots

> _Coming as part of v0.1. PRs welcome._

`screenshots/popover.png` · `screenshots/dashboard-activity.png` · `screenshots/dashboard-duplicates.png` · `screenshots/dashboard-api-usage.png`

---

## 🚀 Install

### Option A — download the DMG (recommended)

> ⚠️ macOS will throw **two** Gatekeeper dialogs the first time you open Magpie. Both are normal for unsigned open-source apps — they don't mean anything is wrong. Notarization (the thing that suppresses these) requires a $99/year Apple Developer account, which Magpie doesn't have. You'll click past each once; after that Magpie launches normally forever.

1. Download **`Magpie-0.3.dmg`** from the **[latest release](https://github.com/hsen-hash/magpie/releases/latest)**.
2. Open the DMG, drag `Magpie.app` to `Applications`, and eject the disk image.
3. In Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Magpie.app
   ```
   That removes the "downloaded from internet" flag that triggers the first dialog ("Magpie is damaged").
4. Double-click `Magpie.app`. You'll see a second dialog: **"Magpie.app" Not Opened — Apple could not verify…**. Click **Done**.
5. Open **System Settings → Privacy & Security**, scroll to the **Security** section. You'll see:
   > _"Magpie.app" was blocked from use because it is not from an identified developer._

   Click **Open Anyway**, authenticate, then click **Open** in the final confirmation.

The bird appears in your menu bar. Subsequent launches are silent — macOS only asks once per install.

<details>
<summary>Terminal-only bypass for both dialogs</summary>

If you'd rather skip the System Settings dance:

```bash
xattr -dr com.apple.quarantine /Applications/Magpie.app
nohup /Applications/Magpie.app/Contents/MacOS/Magpie > /dev/null 2>&1 &
disown
```

This runs the binary directly, which bypasses the `.app` launch path Gatekeeper inspects. Magpie keeps running after you close Terminal. Future double-clicks of `Magpie.app` from Finder also work after this.

</details>

<details>
<summary>Why does this happen?</summary>

macOS Gatekeeper has three trust tiers:

1. **App Store** — Apple notarized + reviewed. No warnings.
2. **Developer ID notarized** — signed with a paid Developer ID + submitted to Apple's notary service. No warnings.
3. **Everything else** — including all unsigned and ad-hoc-signed apps. Two dialogs the first time; once approved, runs silently.

Magpie is tier 3. It ad-hoc-signs the bundle (signature is real, just self-issued) which prevents the strictest "is damaged" verdict, but Gatekeeper still wants the user to acknowledge that it's not from a known developer. This is a one-time consent per install, not a recurring hassle.

When Magpie has a sustaining audience and reason to spend $99/year, we'll move to tier 2. Until then, the two-click consent is the trade-off for not charging users.

</details>

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
./tools/make_dmg.sh      # writes Magpie-0.3.dmg
```

---

## 🔑 Configure your provider

On first launch Magpie creates `~/.config/magpie/config.json` (mode `600`):

```json
{
  "provider": "gemini",

  "geminiApiKey": "PASTE_YOUR_KEY_HERE",
  "geminiModel": "gemini-2.5-flash",

  "ollamaHost": "http://localhost:11434",
  "ollamaModel": "llama3.2",
  "ollamaKeepAlive": "10m"
}
```

The `provider` field picks which backend Magpie uses. Switch it, save, and relaunch.

### Option 1 — Gemini (cloud, ~$0.0001 / file)

1. Get a Gemini API key from <https://aistudio.google.com/apikey>
2. Paste it into `geminiApiKey`, save

**Security guarantees:**
- File mode is `600` — only you can read it
- Key is sent to Google as an `x-goog-api-key` **header**, never in a URL query string
- URLSession errors are scrubbed before logging, so a stale key can't leak into `/tmp/magpie.log`
- Magpie has no telemetry; the only network call it makes is to Google's Gemini endpoint

### Option 2 — Ollama (fully local, $0, no network call)

Magpie hands every batch of filenames to an Ollama server running on your machine. No data ever leaves the laptop. The Dashboard's API Usage tab marks every local call as `$0` and badges it with a green **Ollama** tag.

1. Install Ollama: <https://ollama.com> (Homebrew: `brew install ollama`)
2. Start the server (the GUI app starts it automatically; otherwise `ollama serve` in a terminal)
3. Pull a small instruction-tuned model — anything in the 3B–7B range is plenty for filename categorization:
   ```bash
   ollama pull llama3.2          # ~2 GB, default
   # or
   ollama pull qwen2.5:3b        # ~2 GB, slightly faster on M-series
   # or
   ollama pull mistral           # ~4 GB, higher quality for messy filenames
   ```
4. Set `"provider": "ollama"` in `~/.config/magpie/config.json`, set `ollamaModel` to whatever you pulled, and save

**What you trade off:** the first batch after a cold start takes a few seconds while Ollama loads the model into RAM. `ollamaKeepAlive` (default `10m`) controls how long it stays resident — bump it to `1h` if you want every batch to be instant.

**Custom endpoint:** if you're running Ollama on a Linux box on your LAN, point `ollamaHost` at it (e.g. `"http://10.0.0.42:11434"`). Magpie treats LAN-only traffic the same as `localhost` — still flagged as local, still $0.

---

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
- **Recent moves** — Last 30 filings; ↗ opens the file, 🔍 reveals it in Finder, ↶ reverts the move (double-click a row to open it)
- **Launch at login** — Switch at the bottom
- **🗓️** — Open the Daily Digest tab
- **🔑** — Edit your API key in your default editor
- **📊** — Open the Dashboard window

### The Dashboard (📊)

Five tabs:

- **Activity** — Full SQLite move journal. Filter by filename, hide reverted, Reveal in Finder, revert, or 🪄 turn any AI decision into a Rule
- **Digest** — Your latest daily summary: stat cards (filed / stuck in Recents / duplicate sets), an AI narrative, declutter tips, new-files-by-category bars, and your largest new files. **Scan now** runs one on demand
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

### Workflow: a daily nudge to stay tidy

Once every 24 hours Magpie quietly takes stock and posts a notification. Tap it (or hit 🗓️ in the popover) to open the **Digest** tab:

- **What got added** — count, total size, a breakdown by category, and your largest new files
- **What's piling up** — files stranded uncategorized in `Recents/`, plus how many duplicate sets exist and how much space they're wasting
- **How to avoid clutter** — always-on local heuristics (clear Recents, dedupe, delete that 4 GB installer, add a rule for a category you keep getting), and — if a provider is configured — a short AI-written summary on top

The schedule runs in the background; the heuristic tips never need the network, so the digest is useful even with no key set. On Ollama the AI narrative is free and fully local. Every model call still shows up in **API Usage** so there are no surprises. Want one right now? Open the tab and click **Scan now**.

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
| Local-only mode | ✅ (Ollama) | ❌ | ✅ | ✅ |
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
- [x] **Ollama provider** — fully local categorization, no network call
- [x] Open / reveal filed documents straight from Recent moves
- [x] **Daily clutter digest** — scheduled + on-demand summary with heuristic + AI declutter advice
- [ ] **Anthropic provider** — Claude Haiku as a drop-in option
- [ ] **Perceptual image hashing** — find near-duplicate photos
- [ ] **CLI** — `magpie sort`, `magpie undo last`, `magpie stats`
- [ ] **Plugin hooks** — `post-categorize` shell hook for power users
- [ ] **Notarization** — when there's an Apple Developer account behind the project

---

## 🏗️ Architecture (one paragraph)

Swift Package Manager `executableTarget` bundled into a `.app` via `build.sh` (no Xcode project, no signing). `FolderWatcher` opens an `O_EVTONLY` file descriptor per watched folder, gets FSEvents through a `DispatchSource`, and debounces by 2 s. `CategorizationCoordinator` batches new filenames into chunks of 40, hands them to a `Categorizer` protocol (Gemini over HTTPS or Ollama over `http://localhost:11434`), retries once on failure, and re-enqueues hard failures so files never get silently orphaned. `MoveCoordinator` handles the actual filesystem moves with collision-safe renaming and writes one origin-to-final SQLite row per file, enabling revert. `RulesStore` short-circuits the LLM when a glob or regex matches. The `Dashboard` is a separate `NSWindow` with five SwiftUI tabs; the API Usage tab marks every Ollama call as `$0` against a per-provider pricing table. `DigestService` runs on a daily timer (with an at-launch catch-up), pulls stats from the move journal + filesystem + the dedup scanner, derives local heuristic tips, and optionally augments them with an AI narrative through a `TextCompleter` protocol that both categorizer actors conform to — so the digest reuses whatever provider is already configured and logs its tokens like any other call. Everything runs on the `MainActor` except the categorizers (`actor` for HTTP) and the dedup scanner (`actor` for the hash loop).

---

## 🤝 Contributing

PRs welcome — especially for:
- A third provider (Anthropic Claude or OpenAI) — drop a new `Categorizer`-conforming actor next to `OllamaCategorizer.swift` and wire it into `CategorizationCoordinator`
- Screenshots in `screenshots/`
- A `magpie sort` CLI binary that shares the categorizer

The whole project is around 4 000 lines of Swift, no external dependencies, no Xcode project to wrangle. Open `Package.swift` and you're in.

---

## 📄 License

[MIT](LICENSE) — do whatever, no warranty.

The three-folder UX (`Recents` / `AI Library` / `Manual Library`) is borrowed from Sparkle's product design. Implementation, code, and feature set are entirely original.
