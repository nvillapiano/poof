/// PreviewWindowController.swift
/// Poof — system-wide text expander
///
/// The live autocomplete popup that appears near the caret as you type a
/// trigger. Mirrors Disco's AutocompleteWindowController: a borderless,
/// non-activating NSPanel floating at `.popUpMenu` level so it never steals
/// keyboard focus from whatever app you're typing in.
///
/// Unlike Disco's emoji grid, this is a short vertical list of matching
/// snippets — each row shows the full trigger (prefix + name) and a one-line
/// preview of its replacement. Selection is keyboard-driven from AppDelegate:
///   - Up / Down move the highlight
///   - Tab / Return / Enter accept `currentSelection`
///   - Escape (handled in AppDelegate) hides it
///
/// There is intentionally no mouse interaction: the event tap treats any click
/// as "the caret moved", which dismisses the popup — so hover/click selection
/// would fight that. Keyboard-only keeps the interaction model clean.

import Cocoa

final class PreviewWindowController: NSWindowController {

    // MARK: Layout constants
    private let rowHeight: CGFloat    = 26
    private let panelWidth: CGFloat   = 320
    private let pad: CGFloat          = 6
    private let nameColWidth: CGFloat = 110
    private let maxRows               = 8

    private var matches: [Snippet] = []
    private var prefix = "/"
    private(set) var selectedIndex = 0
    private var rowViews: [RowView] = []

    /// Persistent blur backdrop — kept across keystrokes (only its row subviews
    /// are rebuilt) so retyping doesn't flicker the whole panel.
    private let blur = NSVisualEffectView()

    /// The snippet currently highlighted, or nil if the list is empty.
    var currentSelection: Snippet? {
        matches.indices.contains(selectedIndex) ? matches[selectedIndex] : nil
    }

    init() {
        // .nonactivatingPanel keeps keyboard focus in the host app; .borderless +
        // .fullSizeContentView strips all window chrome.
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level              = .popUpMenu   // float above regular windows
        panel.isOpaque           = false
        panel.backgroundColor    = .clear
        panel.hasShadow          = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        super.init(window: panel)

        blur.material         = .menu           // system menu/popover look
        blur.blendingMode     = .behindWindow
        blur.state            = .active
        blur.wantsLayer       = true
        blur.layer?.cornerRadius  = 10
        blur.layer?.masksToBounds = true
        panel.contentView?.addSubview(blur)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Show / Hide

    /// Updates the list and shows it near `point` (screen coords, bottom-left
    /// origin). Called on every keystroke while a trigger is being typed.
    func show(matches newMatches: [Snippet], prefix newPrefix: String, near point: NSPoint) {
        matches       = Array(newMatches.prefix(maxRows))
        prefix        = newPrefix
        selectedIndex = 0
        rebuildRows()
        positionWindow(near: point)
        if !(window?.isVisible ?? false) { window?.orderFront(nil) }
    }

    func hide() { window?.orderOut(nil) }

    // MARK: - Selection

    func moveDown() { moveTo(min(selectedIndex + 1, matches.count - 1)) }
    func moveUp()   { moveTo(max(selectedIndex - 1, 0)) }

    private func moveTo(_ idx: Int) {
        guard idx != selectedIndex, matches.indices.contains(idx) else { return }
        selectedIndex = idx
        for (i, row) in rowViews.enumerated() { row.setSelected(i == selectedIndex) }
    }

    // MARK: - Rendering

    private func rebuildRows() {
        let contentH = CGFloat(matches.count) * rowHeight + pad * 2
        window?.setContentSize(NSSize(width: panelWidth, height: contentH))
        blur.frame = NSRect(x: 0, y: 0, width: panelWidth, height: contentH)

        rowViews.forEach { $0.removeFromSuperview() }
        rowViews.removeAll()

        // NSView origin is bottom-left, so the first match sits at the top.
        for (i, snippet) in matches.enumerated() {
            let y = contentH - pad - CGFloat(i + 1) * rowHeight
            let row = RowView(frame: NSRect(x: pad, y: y,
                                            width: panelWidth - pad * 2, height: rowHeight))
            row.configure(trigger: prefix + snippet.name,
                          value: snippet.replacement,
                          nameColWidth: nameColWidth)
            row.setSelected(i == selectedIndex)
            blur.addSubview(row)
            rowViews.append(row)
        }
    }

    // MARK: - Positioning
    // Mirrors Disco: sit just below the caret; nudge horizontally to stay
    // on-screen and flip above the caret if it would clip the bottom edge.

    private func positionWindow(near point: NSPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main,
              let wf = window?.frame else { return }
        let sf = screen.visibleFrame
        var x = point.x
        var y = point.y - wf.height - 4
        if x + wf.width > sf.maxX { x = sf.maxX - wf.width }
        if x < sf.minX            { x = sf.minX }
        if y < sf.minY            { y = point.y + 20 }   // flip above the caret
        window?.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - RowView

/// A single suggestion row: a monospaced trigger on the left, a truncated
/// replacement preview on the right, with a rounded highlight when selected.
private final class RowView: NSView {
    private let triggerLabel = NSTextField(labelWithString: "")
    private let valueLabel   = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 5

        triggerLabel.font          = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        triggerLabel.textColor     = .labelColor
        triggerLabel.lineBreakMode = .byTruncatingTail
        addSubview(triggerLabel)

        valueLabel.font          = NSFont.systemFont(ofSize: 12)
        valueLabel.textColor     = .secondaryLabelColor
        valueLabel.lineBreakMode = .byTruncatingTail
        addSubview(valueLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(trigger: String, value: String, nameColWidth: CGFloat) {
        triggerLabel.stringValue = trigger
        // Collapse newlines so a multi-line replacement previews on one line.
        valueLabel.stringValue   = value.replacingOccurrences(of: "\n", with: " ")

        let lh: CGFloat = 16
        let ty = (bounds.height - lh) / 2
        triggerLabel.frame = NSRect(x: 8, y: ty, width: nameColWidth, height: lh)
        let vx = 8 + nameColWidth + 8
        valueLabel.frame   = NSRect(x: vx, y: ty, width: max(0, bounds.width - vx - 8), height: lh)
    }

    func setSelected(_ selected: Bool) {
        layer?.backgroundColor = selected
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.85).cgColor
            : NSColor.clear.cgColor
    }
}
