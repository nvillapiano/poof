# Changelog

All notable changes to Poof are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

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
