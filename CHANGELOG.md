# Changelog

All notable changes to Poof are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Added
- **Live autocomplete popup.** As you type a trigger, a floating popup appears
  near the caret listing snippets whose names prefix-match what you've typed,
  each with a preview of its replacement (`PreviewWindowController`). `↑`/`↓`
  navigate, `Tab`/`Return` accept-and-expand the highlighted entry, `Escape`
  dismisses. Modeled on Disco's non-activating `NSPanel` picker; caret located
  via the Accessibility API, same as Disco.

### Notes
- The popup only appears once there's at least one character after the prefix,
  so a bare `/` typed in paths/URLs/dates never surfaces it.
- Accepting from the popup expands with no trailing delimiter; the classic
  "type the full trigger + space/tab/return" commit still works unchanged.
- Interaction is keyboard-only: the event tap treats any click as "caret moved"
  and dismisses the popup, so hover/click selection is intentionally omitted.
- Fixed a compile error in `AppDelegate` where a block-based `NotificationCenter`
  observer returned `()?` instead of `Void`; replaced with a selector observer.

---

## [1.0.0] — 2026-07-07

### Added
- Initial release.
- System-wide text expansion: type `prefix + name` (e.g. `/shrug`) followed by a
  space, tab, or return in any app and it expands in place.
- Configurable **trigger prefix** (default `/`) with live conflict warning.
  Snippets are stored prefix-free, so changing the prefix re-triggers every
  entry instantly.
- **Snippet manager** window with an add-a-new-entry form plus inline edit and
  delete for existing entries.
- JSON persistence at `~/Library/Application Support/Poof/snippets.json`, with an
  **Open JSON…** shortcut for power-editing.
- Unicode-safe insertion via `CGEvent.keyboardSetUnicodeString` — emoji and
  multibyte glyphs work, and the clipboard is never touched.
- Master **Enable expansion** toggle (menu bar + Settings).
- Launch at login toggle (macOS 13+).
- Menu bar icon (💨) with Add, Manage, Settings, About, and Quit.
- One-command build script producing both `.app` and `.dmg`.

### Notes
- Re-entrancy is handled by tagging synthetic events in `eventSourceUserData`
  and ignoring tagged events, so a replacement can't recursively re-expand.
- Return is treated as a delimiter and re-emitted after expansion, mirroring
  native macOS Text Replacement (so `/trigger` + Enter in a chat box expands and
  sends). This is a one-line change if undesired — see README → Customising.
