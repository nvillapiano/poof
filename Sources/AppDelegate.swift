/// AppDelegate.swift
/// Poof — system-wide text expander
///
/// The central nervous system. It owns:
///   - The menu bar status item and menu
///   - The CGEventTap that intercepts system-wide keystrokes
///   - The "current word" buffer that accumulates the token being typed
///   - Trigger detection and text replacement via Unicode event injection
///
/// Architecture note:
/// Poof is a pure menu bar app (LSUIElement = true, .accessory activation policy).
/// There is no main window and no Dock icon; all UI is driven from the status item.
///
/// How expansion works:
/// Unlike Disco (which shows a live popup as you type), Poof watches for a
/// completed token followed by a delimiter (space / tab / return). When the
/// token — prefix + name, e.g. "/shrug" — matches a snippet, Poof swallows the
/// delimiter, backspaces out the trigger, injects the replacement, then re-emits
/// the delimiter so typing flow is preserved.
///
/// Re-entrancy: our own injected keystrokes loop back through the session tap.
/// We tag them with `magic` in the event's user-data field and ignore tagged
/// events, so a replacement can't accidentally trigger another expansion.

import Cocoa
import Carbon.HIToolbox  // kVK_* virtual key constants

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapActive = false

    private var snippetsWindowController: SnippetsWindowController?
    private var settingsPopover: NSPopover?
    private var settingsVC: SettingsViewController?

    /// The token currently being typed since the last delimiter/reset. Includes
    /// the prefix once typed (e.g. "/shr"). Capped so it can't grow unbounded.
    private var currentWord = ""

    /// Tag stamped into our own synthetic events so we can ignore them when they
    /// loop back through the tap (otherwise a replacement could re-trigger).
    private static let magic: Int64 = 0x50_4F_4F_46  // "POOF"

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // hide from Dock and Cmd-Tab
        SnippetStore.shared.load()
        setupMenuBar()
        checkAccessibilityAndStartTap()

        // Refresh the menu whenever prefs or snippets change.
        let refresh = { [weak self] (_: Notification) in self?.attachMenu() }
        NotificationCenter.default.addObserver(forName: Preferences.didChange,
                                               object: nil, queue: .main, using: refresh)
        NotificationCenter.default.addObserver(forName: SnippetStore.didChange,
                                               object: nil, queue: .main, using: refresh)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopEventTap()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            statusItem.button?.title   = "💨"
            statusItem.button?.toolTip = "Poof"
        }
        attachMenu()
    }

    /// Rebuilds and re-attaches the dropdown menu without touching the status item.
    private func attachMenu() {
        let axLine  = NSMenuItem(title: axStatusTitle(),  action: nil, keyEquivalent: ""); axLine.isEnabled  = false
        let tapLine = NSMenuItem(title: tapStatusTitle(), action: nil, keyEquivalent: ""); tapLine.isEnabled = false

        let enabled = NSMenuItem(title: "Enable Expansion", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        enabled.state  = Preferences.shared.isEnabled ? .on : .off

        let add     = NSMenuItem(title: "Add Snippet…",     action: #selector(addSnippet),     keyEquivalent: "n"); add.target = self
        let manage  = NSMenuItem(title: "Manage Snippets…", action: #selector(manageSnippets),  keyEquivalent: ""); manage.target = self
        let settings = NSMenuItem(title: "Settings…",       action: #selector(openSettings),   keyEquivalent: ","); settings.target = self
        let about   = NSMenuItem(title: "About Poof",       action: #selector(showAbout),      keyEquivalent: ""); about.target = self
        let quit    = NSMenuItem(title: "Quit Poof",        action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")

        let menu = NSMenu()
        menu.addItem(axLine)
        menu.addItem(tapLine)
        menu.addItem(.separator())
        menu.addItem(enabled)
        menu.addItem(.separator())
        menu.addItem(add)
        menu.addItem(manage)
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(about)
        menu.addItem(quit)
        statusItem.menu = menu
    }

    // MARK: - Accessibility & Event Tap

    private func checkAccessibilityAndStartTap() {
        if AXIsProcessTrusted() {
            startEventTap()
        } else {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
            pollForAccessibility()
        }
    }

    private func pollForAccessibility() {
        if AXIsProcessTrusted() {
            startEventTap()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.pollForAccessibility()
            }
        }
    }

    private func startEventTap() {
        // keyDown for typing; mouse-down so a click that moves the caret abandons
        // the in-progress word.
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let me = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                return me.handleCGEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Poof: failed to create event tap — will retry")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.startEventTap()
            }
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        tapActive = true
        attachMenu()
    }

    private func stopEventTap() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
    }

    // MARK: - Key Event Handling

    private func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Pass-through returns a fresh +1-retained reference each time; the nil
        // (swallow) paths must NOT create one, or we leak an event per expansion.
        func passThrough() -> Unmanaged<CGEvent>? { Unmanaged.passRetained(event) }

        // The OS can disable the tap under load; re-enable and move on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return passThrough()
        }

        // Ignore events we posted ourselves.
        if event.getIntegerValueField(.eventSourceUserData) == Self.magic { return passThrough() }

        guard Preferences.shared.isEnabled else { return passThrough() }

        // A click moves the caret — abandon the in-progress word.
        if type == .leftMouseDown || type == .rightMouseDown {
            currentWord = ""
            return passThrough()
        }

        guard type == .keyDown else { return passThrough() }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags   = event.flags

        // Modifier combos are shortcuts, not typing.
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            currentWord = ""
            return passThrough()
        }

        // Backspace trims the buffer so a corrected trigger still matches.
        if keyCode == kVK_Delete {
            if !currentWord.isEmpty { currentWord.removeLast() }
            return passThrough()
        }

        // Escape cancels a pending expansion: clear the in-progress trigger so
        // it can't fire. We pass Escape THROUGH to the host app rather than
        // swallow it — Poof shows no popup, so there's no visible capture mode
        // that would justify eating the keystroke. (To get Disco-style
        // swallow-while-active instead, gate on currentWord.hasPrefix(prefix)
        // and return nil here.)
        if keyCode == kVK_Escape {
            currentWord = ""
            return passThrough()
        }

        // Caret-moving keys abandon the word (the cursor is no longer at the
        // end of what we've been tracking).
        if resetKeyCodes.contains(keyCode) {
            currentWord = ""
            return passThrough()
        }

        // Delimiters complete a token.
        if keyCode == kVK_Space || keyCode == kVK_Tab ||
           keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter {
            if let replacement = SnippetStore.shared.replacement(forTypedToken: currentWord) {
                let triggerLength = currentWord.count
                currentWord = ""
                expand(triggerLength: triggerLength, replacement: replacement, delimiterKeyCode: keyCode)
                return nil   // swallow the delimiter; we re-emit it after expanding
            }
            currentWord = ""
            return passThrough()
        }

        // Ordinary printable character.
        if let char = event.character {
            currentWord += char
            if currentWord.count > 64 { currentWord = String(currentWord.suffix(64)) }
        }
        return passThrough()
    }

    /// Arrows, home/end, page up/down, forward-delete — anything that moves the
    /// caret away from the end of what we're tracking. (Escape is handled
    /// separately as an explicit cancel.)
    private let resetKeyCodes: Set<Int> = [
        kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
        kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
        kVK_ForwardDelete
    ]

    // MARK: - Expansion (posting synthetic events)

    private func expand(triggerLength: Int, replacement: String, delimiterKeyCode: Int) {
        // Post on the main queue so we return from the tap callback immediately.
        DispatchQueue.main.async {
            let src = CGEventSource(stateID: .hidSystemState)

            // 1. Delete the trigger the user typed.
            for _ in 0..<triggerLength { self.postKey(CGKeyCode(kVK_Delete), source: src) }

            // 2. A short beat lets the host app process the deletes before we type
            //    (mirrors Disco's staggered injection).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                self.postString(replacement, source: src)

                // 3. Re-emit whatever delimiter the user pressed.
                switch delimiterKeyCode {
                case kVK_Space:  self.postString(" ", source: src)
                case kVK_Tab:    self.postString("\t", source: src)
                case kVK_Return, kVK_ANSI_KeypadEnter:
                    self.postKey(CGKeyCode(kVK_Return), source: src)
                default: break
                }
            }
        }
    }

    private func postKey(_ keyCode: CGKeyCode, source: CGEventSource?) {
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.setIntegerValueField(.eventSourceUserData, value: Self.magic)
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.setIntegerValueField(.eventSourceUserData, value: Self.magic)
        up?.post(tap: .cghidEventTap)
    }

    /// Types an arbitrary Unicode string via a synthetic key event — handles
    /// emoji and multibyte glyphs (like ツ) that a keycode map can't express.
    private func postString(_ string: String, source: CGEventSource?) {
        let utf16 = Array(string.utf16)

        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down?.setIntegerValueField(.eventSourceUserData, value: Self.magic)
        down?.post(tap: .cghidEventTap)

        // Plain key-up (no string) keeps the down/up pair balanced without
        // risking a double insertion.
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        up?.setIntegerValueField(.eventSourceUserData, value: Self.magic)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Menu status lines

    private func axStatusTitle() -> String {
        AXIsProcessTrusted()
            ? "✅ Accessibility granted"
            : "⚠️ Accessibility needed — check System Settings"
    }

    private func tapStatusTitle() -> String {
        guard tapActive else { return "⚠️ Event tap inactive" }
        return Preferences.shared.isEnabled
            ? "✅ Listening for “\(Preferences.shared.triggerPrefix)…”"
            : "⏸ Expansion paused"
    }

    // MARK: - Menu Actions

    @objc private func toggleEnabled() {
        Preferences.shared.isEnabled.toggle()
        attachMenu()
    }

    @objc private func addSnippet() {
        showManager()
        snippetsWindowController?.focusAddField()
    }

    @objc private func manageSnippets() {
        showManager()
    }

    private func showManager() {
        if snippetsWindowController == nil {
            snippetsWindowController = SnippetsWindowController()
        }
        snippetsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        if settingsPopover == nil {
            let vc = SettingsViewController()
            settingsVC = vc
            let pop = NSPopover()
            pop.contentViewController = vc
            pop.behavior = .transient
            pop.contentSize = NSSize(width: 280, height: 180)
            pop.delegate = self
            settingsPopover = pop
        }

        guard let button = statusItem.button else { return }
        statusItem.menu = nil   // must be nil or the popover won't appear
        settingsPopover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Poof 💨",
            .applicationVersion: "1.0",
            .credits: NSAttributedString(
                string: "Curated text expansion for your Mac.\nType a trigger in any app and it poofs into your text.",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]
            )
        ])
    }
}

// MARK: - NSPopoverDelegate

extension AppDelegate: NSPopoverDelegate {
    /// Re-attach the status item menu once the settings popover has fully closed.
    func popoverDidClose(_ notification: Notification) {
        attachMenu()
    }
}

// MARK: - CGEvent character helper

private extension CGEvent {
    /// The single Unicode character produced by this keyDown event. Uses
    /// `keyboardGetUnicodeString` so non-US layouts and composed characters work
    /// without any custom keymap.
    var character: String? {
        var length = 0
        var chars  = [UniChar](repeating: 0, count: 4)
        self.keyboardGetUnicodeString(maxStringLength: 4,
                                      actualStringLength: &length,
                                      unicodeString: &chars)
        guard length > 0 else { return nil }
        var result = ""
        for i in 0..<length {
            guard let scalar = Unicode.Scalar(chars[i]) else { continue }
            result.append(Character(scalar))
        }
        return result.isEmpty ? nil : String(result.prefix(1))
    }
}
