# 💨 Poof

System-wide text expander for your Mac. Type a curated trigger — `/shrug`,
`/pid`, whatever you define — in any app, follow it with a space, tab, or
return, and it *poofs* into the full text right where your cursor is.

Think of it as a first-party, curated version of macOS Text Replacement, living
in your menu bar.

No Electron. No subscription. Pure Swift, pure AppKit.

---

## Download

**[→ Download the latest Poof.dmg](https://github.com/nvillapiano/poof/releases/latest)**

1. Open the DMG and drag **Poof.app** to `/Applications`
2. Launch Poof — right-click → **Open** on first run to bypass Gatekeeper
3. Poof appears as 💨 in your menu bar; grant Accessibility when prompted

Prefer to build it yourself? See [Build & Install](#build--install) below.

---

## Features

| | |
|---|---|
| **System-wide expansion** | Works in every app that accepts text input |
| **Curated snippets** | You define every `trigger → replacement` pair |
| **Configurable prefix** | Change `/` to `~`, `;`, or any character in Settings — all snippets follow |
| **Add-a-snippet form** | Add, edit, and delete entries in a simple manager window |
| **Unicode-safe** | Emoji and multibyte glyphs (`¯\_(ツ)_/¯`) inject cleanly |
| **No clipboard clobber** | Text is injected directly — your pasteboard is never touched |
| **Pause switch** | Toggle expansion off without quitting |
| **Launch at login** | Stays running silently in the background (macOS 13+) |
| **Menu bar icon** | 💨 — unobtrusive, always accessible |
| **No Dock icon** | Pure menu bar app |

---

## Requirements

- **macOS 12 Monterey or later**
- **Xcode Command Line Tools:** `xcode-select --install`

---

## Build & Install

```bash
git clone https://github.com/nvillapiano/poof.git
cd poof
npm run build:full     # build + install to /Applications + relaunch
```

Or step by step:

```bash
npm run build          # → Poof.app + Poof.dmg
npm run migrate        # quit running copy, install to /Applications, relaunch
```

### First launch (unsigned app)

Because Poof isn't signed with an Apple Developer certificate, macOS will warn
you the first time:

1. **Right-click** `Poof.app` → **Open** → click **Open** in the dialog
2. macOS remembers the choice and won't ask again

### Accessibility permission

Poof needs Accessibility access to watch keystrokes and replace text
system-wide. On first launch you'll be prompted automatically:

> System Settings → Privacy & Security → Accessibility → enable Poof

The app polls for the grant, so it starts working the moment you flip the switch
— no relaunch needed.

---

## Usage

| Action | Result |
|---|---|
| Start typing a trigger (e.g. `/sh`) | A popup near the caret lists matching snippets and their replacements |
| `↑` / `↓` (popup open) | Move the highlight |
| `Tab` / `Return` (popup open) | Accept the highlighted snippet and expand it |
| `Escape` (popup open) | Dismiss the popup (keystroke is swallowed) |
| Type `/shrug` then space/tab/return | Expands to `¯\_(ツ)_/¯` (works with or without the popup) |
| `Escape` mid-trigger, no popup | Cancels the pending expansion (Escape still reaches the app) |
| Menu bar 💨 → **Add Snippet…** (⌘N) | Opens the manager focused on the add form |
| Menu bar 💨 → **Manage Snippets…** | Add, edit, or delete entries |
| Menu bar 💨 → **Settings…** (⌘,) | Change the prefix, pause, launch-at-login |
| Menu bar 💨 → **Enable Expansion** | Quick pause/resume toggle |

Snippets live at
`~/Library/Application Support/Poof/snippets.json` — click **Open JSON…** in the
manager to power-edit them directly.

---

## Settings

Click 💨 in the menu bar → **Settings…**

- **Trigger prefix** — default `/`. Change to any single character; every snippet
  re-triggers under the new prefix instantly. Avoid letters, numbers, and space
  (they'd conflict with normal typing — the field warns you).
- **Enable expansion** — master on/off.
- **Launch at login** — start Poof automatically when you log in (macOS 13+).

---

## Project Structure

```
Poof/
├── build.sh                          # One-command build → .app + .dmg
├── install.sh                        # Quit running copy, install, relaunch
├── package.json                      # npm run build / migrate / build:full
├── Package.swift                     # Swift Package Manager manifest
├── Sources/
│   ├── main.swift                    # Entry point — boots NSApplication
│   ├── AppDelegate.swift             # Core engine: event tap, token buffer, expansion
│   ├── Preferences.swift             # UserDefaults wrapper (prefix, enable, login)
│   ├── SnippetStore.swift            # Snippet model, JSON persistence, lookup
│   ├── SnippetsWindowController.swift# Add / edit / delete manager window
│   ├── SettingsViewController.swift  # Settings popover (prefix setter, etc.)
│   └── PreviewWindowController.swift # Live autocomplete popup near the caret
└── Resources/
    └── Info.plist                    # App bundle metadata
```

---

## How It Works

### Event interception
Poof registers a system-wide `CGEventTap` via Core Graphics (requires
Accessibility permission), intercepting `keyDown` before it reaches the target
app. A `currentWord` buffer accumulates the token you're typing and resets on
any word boundary, caret move, click, or modifier combo.

### Trigger model
Snippets are stored as **bare names** (`shrug`, `pid`) — never with the prefix.
The effective trigger is `Preferences.triggerPrefix + name`, so changing the
prefix in Settings re-triggers every entry without rewriting the file. Lookups
strip the current prefix before matching.

### Expansion
When a completed token followed by a delimiter (space / tab / return) matches a
snippet, Poof swallows the delimiter (`return nil` from the tap), backspaces out
the trigger, injects the replacement via `CGEvent.keyboardSetUnicodeString`
(clean Unicode, no clipboard), then re-emits the delimiter so typing flow is
preserved.

### Live autocomplete popup
As you type, `PreviewWindowController` shows a borderless, non-activating
`NSPanel` (the same recipe as Disco's picker) near the caret, listing every
snippet whose name prefix-matches what you've typed after the trigger prefix. It
appears only once there's at least one character after the prefix — so a bare
`/` in a path or URL never triggers it. `↑`/`↓` move the highlight; `Tab` or
`Return` accept the highlighted entry and expand it immediately (no delimiter
re-emitted); `Escape` dismisses it. These keys are swallowed while the popup is
open, so they never leak to the host app. The caret is located via the
Accessibility API (`caretScreenPosition()`), falling back to the focused
element's frame, then the mouse. Interaction is keyboard-only by design: the tap
treats any click as "caret moved" and dismisses the popup, so hover/click
selection would fight that.

### Re-entrancy guard
Our own injected keystrokes loop back through the session tap. Each synthetic
event is stamped with a magic value in `eventSourceUserData`; tagged events are
ignored, so a replacement can never accidentally trigger another expansion.

---

## Customising

- **Change the trigger prefix** — Settings (no rebuild needed), or edit
  `com.poof.triggerPrefix` in UserDefaults.
- **Expand on punctuation too** — add the punctuation key codes to the delimiter
  check in `AppDelegate.handleCGEvent`.
- **Stop Return from auto-sending** — Return is treated as a delimiter and
  re-emitted after expanding, so `/shrug` + Enter in a chat box expands *and*
  sends (matching native Text Replacement). Drop `kVK_Return`/`kVK_ANSI_KeypadEnter`
  from the delimiter check and re-emit switch to change that.
- **Change the bundle ID / name** — edit `APP_NAME`/`BUNDLE_ID` in `build.sh`,
  `CFBundleIdentifier` in `Info.plist`, and `name` in `Package.swift`.

---

## Contributing & Releasing

Poof follows the [git-for-ai](https://github.com/nvillapiano/git-for-ai)
workflow: branch off `main` (`type/slug`), use [Conventional
Commits](https://www.conventionalcommits.org/), and open one PR per logical
change. Squash-merge only.

```bash
# 1. Bump version in package.json
# 2. Update CHANGELOG.md
# 3. Commit and push on a branch, open PR
# 4. Squash-merge with feat: prefix → auto-tag fires → GitHub Actions builds and publishes Poof.dmg
```

Merging a `feat:` commit to `main` bumps the minor version (`feat!:` bumps
major), tags it, and the release workflow builds and attaches `Poof.dmg` to the
GitHub release automatically. `fix:`/`docs:`/`chore:` commits don't trigger a
release.

For critical patch releases: merge the `fix:` PR, then run `npm run release:patch`.

---

## License

MIT — do whatever you want with it.
