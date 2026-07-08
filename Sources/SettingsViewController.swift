/// SettingsViewController.swift
/// Poof — system-wide text expander
///
/// A compact popover (280×180pt) attached to the menu bar status item.
/// Contains three settings:
///   - Trigger prefix:  single-character field with live validation (mirrors
///                      Disco's trigger-character control)
///   - Enable expansion: NSSwitch bound to Preferences.isEnabled
///   - Launch at login:  NSSwitch bound to SMAppService (macOS 13+)
///
/// Popover/menu coexistence: NSStatusItem.menu and NSPopover cannot show at the
/// same time. AppDelegate detaches the menu before showing this popover and
/// re-attaches it in popoverDidClose.

import Cocoa

final class SettingsViewController: NSViewController {

    private let prefixField    = NSTextField()
    private let prefixWarning  = NSTextField(labelWithString: "")
    private let enableToggle   = NSSwitch()
    private let loginToggle    = NSSwitch()

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 180))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        loadValues()
    }

    // MARK: - UI

    private func buildUI() {
        let title = NSTextField(labelWithString: "Poof Settings 💨")
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(title)

        // ── Trigger prefix ─────────────────────────────────────────────────────
        let prefixLabel = NSTextField(labelWithString: "Trigger prefix")
        prefixLabel.font = NSFont.systemFont(ofSize: 12)
        prefixLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(prefixLabel)

        prefixField.stringValue = Preferences.shared.triggerPrefix
        prefixField.font        = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        prefixField.alignment   = .center
        prefixField.bezelStyle  = .roundedBezel
        prefixField.delegate    = self
        prefixField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(prefixField)

        prefixWarning.font      = NSFont.systemFont(ofSize: 10)
        prefixWarning.textColor = .systemOrange
        prefixWarning.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(prefixWarning)

        // ── Enable expansion ───────────────────────────────────────────────────
        let enableLabel = NSTextField(labelWithString: "Enable expansion")
        enableLabel.font = NSFont.systemFont(ofSize: 12)
        enableLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(enableLabel)

        enableToggle.target = self
        enableToggle.action = #selector(enableToggled)
        enableToggle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(enableToggle)

        // ── Launch at login ────────────────────────────────────────────────────
        let loginLabel = NSTextField(labelWithString: "Launch at login")
        loginLabel.font = NSFont.systemFont(ofSize: 12)
        loginLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loginLabel)

        loginToggle.target = self
        loginToggle.action = #selector(loginToggled)
        loginToggle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loginToggle)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            prefixLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 18),
            prefixLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            prefixField.centerYAnchor.constraint(equalTo: prefixLabel.centerYAnchor),
            prefixField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            prefixField.widthAnchor.constraint(equalToConstant: 42),

            prefixWarning.topAnchor.constraint(equalTo: prefixField.bottomAnchor, constant: 2),
            prefixWarning.trailingAnchor.constraint(equalTo: prefixField.trailingAnchor),

            enableLabel.topAnchor.constraint(equalTo: prefixLabel.bottomAnchor, constant: 26),
            enableLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            enableToggle.centerYAnchor.constraint(equalTo: enableLabel.centerYAnchor),
            enableToggle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            loginLabel.topAnchor.constraint(equalTo: enableLabel.bottomAnchor, constant: 18),
            loginLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            loginToggle.centerYAnchor.constraint(equalTo: loginLabel.centerYAnchor),
            loginToggle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    private func loadValues() {
        prefixField.stringValue = Preferences.shared.triggerPrefix
        enableToggle.state      = Preferences.shared.isEnabled ? .on : .off
        loginToggle.state       = Preferences.shared.launchAtLogin ? .on : .off
    }

    @objc private func enableToggled() {
        Preferences.shared.isEnabled = (enableToggle.state == .on)
    }

    @objc private func loginToggled() {
        Preferences.shared.launchAtLogin = (loginToggle.state == .on)
    }
}

// MARK: - NSTextFieldDelegate (prefix validation)

extension SettingsViewController: NSTextFieldDelegate {

    /// Fires on every keystroke. Enforces single-character input and warns if the
    /// user picks a prefix that would collide with ordinary typing.
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        let raw = field.stringValue

        // Keep only the most recently typed character.
        let single = raw.isEmpty ? "/" : String(raw.suffix(1))
        if raw.count > 1 { field.stringValue = single }

        // Letters, digits, and whitespace would fire on normal typing.
        let risky = Set("abcdefghijklmnopqrstuvwxyz0123456789 ".map(String.init))
        if risky.contains(single.lowercased()) {
            prefixWarning.stringValue = "⚠ May conflict with normal typing"
        } else {
            prefixWarning.stringValue = ""
            Preferences.shared.triggerPrefix = single
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        prefixWarning.stringValue = ""
        let val = prefixField.stringValue
        if !val.isEmpty {
            Preferences.shared.triggerPrefix = String(val.prefix(1))
        } else {
            prefixField.stringValue = Preferences.shared.triggerPrefix
        }
    }
}
