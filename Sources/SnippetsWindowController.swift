/// SnippetsWindowController.swift
/// Poof — system-wide text expander
///
/// The snippet manager window, opened via the menu bar 💨 → Add Snippet… /
/// Manage Snippets…. Analogous to Disco's BrowserWindowController.
///
/// Layout:
///   [ prefix ][ name ] → [ replacement ]        [ Add ]     ← add-a-new-entry form
///   ─────────────────────────────────────────────────────
///   [ prefix ][ name ] → [ replacement ]           [✕]      ← one editable row
///   [ prefix ][ name ] → [ replacement ]           [✕]        per snippet
///   …
///   ─────────────────────────────────────────────────────
///   Open JSON…                              N snippets
///
/// Editing a row's fields commits on end-editing. The prefix shown in each row
/// tracks Preferences.triggerPrefix live, so changing the prefix in Settings
/// updates every badge here.
///
/// Closing hides the window rather than deallocating (windowShouldClose returns
/// false) so state is preserved between opens.

import Cocoa

final class SnippetsWindowController: NSWindowController, NSWindowDelegate {

    private let addPrefixBadge = NSTextField(labelWithString: "/")
    private let addNameField   = NSTextField()
    private let addReplField   = NSTextField()
    private let addButton      = NSButton(title: "Add", target: nil, action: nil)
    private let addStatus      = NSTextField(labelWithString: "")

    private let tableView = NSTableView()
    private let countLabel = NSTextField(labelWithString: "")

    // MARK: - Init

    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask:   [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        win.title   = "Poof — Snippets 💨"
        win.minSize = NSSize(width: 480, height: 360)
        win.setFrameAutosaveName("PoofSnippets")
        if win.frame.origin == .zero { win.center() }

        super.init(window: win)
        win.delegate = self
        buildUI()
        reload()

        NotificationCenter.default.addObserver(self, selector: #selector(reload),
                                               name: Preferences.didChange, object: nil)
        // NB: we deliberately do NOT observe SnippetStore.didChange here. Inline
        // edits call save() (which posts it), and reloading the table mid-edit
        // would rebuild the row and steal focus. Add/delete call reload()
        // explicitly; external JSON edits are picked up on window focus.
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowDidBecomeKey(_ notification: Notification) { reload() }

    // MARK: - UI

    private func buildUI() {
        guard let cv = window?.contentView else { return }

        // ── Add-a-new-entry form ───────────────────────────────────────────────
        let formLabel = NSTextField(labelWithString: "Add a snippet")
        formLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        formLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(formLabel)

        styleBadge(addPrefixBadge)
        cv.addSubview(addPrefixBadge)

        addNameField.placeholderString = "trigger"
        addNameField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        addNameField.target = self
        addNameField.action = #selector(addTapped)   // Return in this field adds
        addNameField.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(addNameField)

        let arrow = NSTextField(labelWithString: "→")
        arrow.textColor = .secondaryLabelColor
        arrow.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(arrow)

        addReplField.placeholderString = "expands to…"
        addReplField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        addReplField.target = self
        addReplField.action = #selector(addTapped)   // Return in this field adds
        addReplField.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(addReplField)

        addButton.bezelStyle    = .rounded
        addButton.target        = self
        addButton.action        = #selector(addTapped)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(addButton)

        addStatus.font      = NSFont.systemFont(ofSize: 10)
        addStatus.textColor = .systemRed
        addStatus.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(addStatus)

        let sep = NSBox(); sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(sep)

        // ── List of existing snippets ──────────────────────────────────────────
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers  = true
        scroll.borderType          = .noBorder
        scroll.drawsBackground     = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(scroll)

        let col = NSTableColumn(identifier: .init("snippet"))
        col.title = ""
        tableView.addTableColumn(col)
        tableView.headerView    = nil
        tableView.rowHeight     = 38
        tableView.focusRingType = .none
        tableView.backgroundColor = .clear
        tableView.dataSource    = self
        tableView.delegate      = self
        scroll.documentView     = tableView

        // ── Footer ─────────────────────────────────────────────────────────────
        let openJSON = NSButton(title: "Open JSON…", target: self, action: #selector(openJSON))
        openJSON.bezelStyle = .rounded
        openJSON.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(openJSON)

        countLabel.font      = NSFont.systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(countLabel)

        NSLayoutConstraint.activate([
            formLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: 14),
            formLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),

            addPrefixBadge.topAnchor.constraint(equalTo: formLabel.bottomAnchor, constant: 8),
            addPrefixBadge.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            addPrefixBadge.widthAnchor.constraint(equalToConstant: 24),
            addPrefixBadge.heightAnchor.constraint(equalToConstant: 22),

            addNameField.centerYAnchor.constraint(equalTo: addPrefixBadge.centerYAnchor),
            addNameField.leadingAnchor.constraint(equalTo: addPrefixBadge.trailingAnchor, constant: 4),
            addNameField.widthAnchor.constraint(equalToConstant: 110),

            arrow.centerYAnchor.constraint(equalTo: addPrefixBadge.centerYAnchor),
            arrow.leadingAnchor.constraint(equalTo: addNameField.trailingAnchor, constant: 8),

            addReplField.centerYAnchor.constraint(equalTo: addPrefixBadge.centerYAnchor),
            addReplField.leadingAnchor.constraint(equalTo: arrow.trailingAnchor, constant: 8),
            addReplField.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -8),

            addButton.centerYAnchor.constraint(equalTo: addPrefixBadge.centerYAnchor),
            addButton.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            addButton.widthAnchor.constraint(equalToConstant: 64),

            addStatus.topAnchor.constraint(equalTo: addNameField.bottomAnchor, constant: 3),
            addStatus.leadingAnchor.constraint(equalTo: addNameField.leadingAnchor),

            sep.topAnchor.constraint(equalTo: addStatus.bottomAnchor, constant: 8),
            sep.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1),

            scroll.topAnchor.constraint(equalTo: sep.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: openJSON.topAnchor, constant: -8),

            openJSON.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            openJSON.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -12),

            countLabel.centerYAnchor.constraint(equalTo: openJSON.centerYAnchor),
            countLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
        ])
    }

    private func styleBadge(_ label: NSTextField) {
        label.font            = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        label.alignment       = .center
        label.textColor       = .secondaryLabelColor
        label.drawsBackground = false
        label.isBezeled       = false
        label.isEditable      = false
        label.wantsLayer      = true
        label.layer?.cornerRadius   = 5
        label.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        label.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Data

    @objc private func reload() {
        addPrefixBadge.stringValue = Preferences.shared.triggerPrefix
        tableView.reloadData()
        let n = SnippetStore.shared.count
        countLabel.stringValue = "\(n) snippet\(n == 1 ? "" : "s")"
    }

    /// Makes the new-entry name field first responder (used by the "Add Snippet…"
    /// menu item).
    func focusAddField() {
        window?.makeFirstResponder(addNameField)
    }

    // MARK: - Actions

    @objc private func addTapped() {
        let name = addNameField.stringValue
        let repl = addReplField.stringValue

        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            flash("Enter a trigger"); return
        }
        guard name.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            flash("No spaces in the trigger"); return
        }
        guard !SnippetStore.shared.nameExists(name) else {
            flash("“\(name)” already exists"); return
        }

        SnippetStore.shared.add(name: name, replacement: repl)
        addNameField.stringValue = ""
        addReplField.stringValue = ""
        addStatus.stringValue = ""
        reload()
        focusAddField()
    }

    private func flash(_ message: String) {
        addStatus.stringValue = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.addStatus.stringValue = ""
        }
    }

    @objc private func openJSON() {
        SnippetStore.shared.revealFile()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        window?.orderOut(nil)
        return false
    }
}

// MARK: - Table data / rows

extension SnippetsWindowController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        SnippetStore.shared.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        // Fresh cell every time (no reuse) so each row's callbacks capture a
        // stable index between reloads.
        let snippets = SnippetStore.shared.snippets
        guard snippets.indices.contains(row) else { return nil }
        let snippet = snippets[row]

        let cell = SnippetRowView(prefix: Preferences.shared.triggerPrefix, snippet: snippet)
        cell.onCommit = { name, repl in
            SnippetStore.shared.update(at: row, name: name, replacement: repl)
        }
        cell.onDelete = { [weak self] in
            SnippetStore.shared.remove(at: row)
            self?.reload()
        }
        return cell
    }
}

// MARK: - SnippetRowView

/// One editable row: [prefix][name] → [replacement]  [✕]
final class SnippetRowView: NSView, NSTextFieldDelegate {

    var onCommit: ((String, String) -> Void)?
    var onDelete: (() -> Void)?

    private let nameField = NSTextField()
    private let replField = NSTextField()

    init(prefix: String, snippet: Snippet) {
        super.init(frame: .zero)

        let badge = NSTextField(labelWithString: prefix)
        badge.font            = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        badge.alignment       = .center
        badge.textColor       = .secondaryLabelColor
        badge.drawsBackground = false
        badge.isBezeled       = false
        badge.wantsLayer      = true
        badge.layer?.cornerRadius   = 5
        badge.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)

        nameField.stringValue = snippet.name
        nameField.font        = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        nameField.bezelStyle  = .roundedBezel
        nameField.delegate    = self
        nameField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameField)

        let arrow = NSTextField(labelWithString: "→")
        arrow.textColor = .secondaryLabelColor
        arrow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(arrow)

        replField.stringValue = snippet.replacement
        replField.font        = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        replField.bezelStyle  = .roundedBezel
        replField.delegate    = self
        replField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(replField)

        let delete = NSButton(title: "✕", target: self, action: #selector(deleteTapped))
        delete.bezelStyle = .inline
        delete.isBordered = false
        delete.contentTintColor = .secondaryLabelColor
        delete.translatesAutoresizingMaskIntoConstraints = false
        addSubview(delete)

        NSLayoutConstraint.activate([
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            badge.widthAnchor.constraint(equalToConstant: 24),
            badge.heightAnchor.constraint(equalToConstant: 22),

            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameField.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 4),
            nameField.widthAnchor.constraint(equalToConstant: 110),

            arrow.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrow.leadingAnchor.constraint(equalTo: nameField.trailingAnchor, constant: 8),

            replField.centerYAnchor.constraint(equalTo: centerYAnchor),
            replField.leadingAnchor.constraint(equalTo: arrow.trailingAnchor, constant: 8),
            replField.trailingAnchor.constraint(equalTo: delete.leadingAnchor, constant: -8),

            delete.centerYAnchor.constraint(equalTo: centerYAnchor),
            delete.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            delete.widthAnchor.constraint(equalToConstant: 20),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func deleteTapped() { onDelete?() }

    /// Commit both fields whenever either finishes editing.
    func controlTextDidEndEditing(_ obj: Notification) {
        onCommit?(nameField.stringValue, replField.stringValue)
    }
}
