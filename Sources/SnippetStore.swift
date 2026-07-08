/// SnippetStore.swift
/// Poof — system-wide text expander
///
/// The snippet database. Analogous to Disco's EmojiDatabase, but user-editable
/// and persisted to disk as JSON.
///
/// Storage model:
/// Snippets are stored as BARE names (e.g. "shrug", "pid") — never with the
/// prefix. The effective trigger is `Preferences.triggerPrefix + name`, so
/// changing the prefix in Settings instantly re-triggers every entry without
/// rewriting the file. Lookups go through `replacement(forTypedToken:)`, which
/// strips the current prefix before matching.
///
/// Persistence: ~/Library/Application Support/Poof/snippets.json
/// Access via the singleton `SnippetStore.shared`.

import Foundation
import AppKit

/// One expansion. `name` is the bare trigger (no prefix); `replacement` is the
/// text that gets typed in its place.
struct Snippet: Codable, Equatable {
    var name: String
    var replacement: String
}

final class SnippetStore {
    static let shared = SnippetStore()
    static let didChange = Notification.Name("com.poof.snippetsDidChange")

    private(set) var snippets: [Snippet] = [] {
        didSet { rebuildIndex() }
    }

    /// name -> replacement, for O(1) lookups in the event tap.
    private var index: [String: String] = [:]

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Poof", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("snippets.json")
    }()

    private init() {}

    // MARK: - Load / Save

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Snippet].self, from: data),
              !decoded.isEmpty else {
            snippets = Self.defaults
            save()
            return
        }
        snippets = decoded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(snippets) {
            try? data.write(to: fileURL, options: .atomic)
        }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    private func rebuildIndex() {
        index = Dictionary(snippets.map { ($0.name, $0.replacement) },
                           uniquingKeysWith: { _, last in last })
    }

    // MARK: - Lookup (event tap)

    /// Given a fully typed token (prefix included, e.g. "/shrug"), returns the
    /// replacement if it matches a snippet under the current prefix.
    func replacement(forTypedToken token: String) -> String? {
        let prefix = Preferences.shared.triggerPrefix
        guard token.hasPrefix(prefix) else { return nil }
        let name = String(token.dropFirst(prefix.count))
        return index[name]
    }

    var isEmpty: Bool { snippets.isEmpty }
    var count: Int { snippets.count }

    // MARK: - CRUD (snippet manager)

    /// True if a snippet with this bare name already exists.
    func nameExists(_ name: String) -> Bool { index[name] != nil }

    /// Adds a new snippet. Returns false if the name is empty, contains
    /// whitespace, or already exists.
    @discardableResult
    func add(name: String, replacement: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              clean.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !nameExists(clean) else { return false }
        snippets.append(Snippet(name: clean, replacement: replacement))
        save()
        return true
    }

    func update(at index: Int, name: String, replacement: String) {
        guard snippets.indices.contains(index) else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        snippets[index] = Snippet(name: clean, replacement: replacement)
        save()
    }

    func remove(at index: Int) {
        guard snippets.indices.contains(index) else { return }
        snippets.remove(at: index)
        save()
    }

    /// Opens the underlying JSON file in Finder for power-editing.
    func revealFile() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    // MARK: - Defaults

    static let defaults: [Snippet] = [
        Snippet(name: "shrug", replacement: "¯\\_(ツ)_/¯"),
        Snippet(name: "pid",   replacement: "P3390381")
    ]
}
