/// Preferences.swift
/// Poof — system-wide text expander
///
/// Thin UserDefaults wrapper that centralises all persistent user settings.
/// Access via the singleton `Preferences.shared`.
///
/// Current settings:
///   - triggerPrefix   — the character that must precede every snippet name
///                       (default: "/"). Snippets are stored WITHOUT the prefix,
///                       so changing this here instantly re-triggers every entry.
///   - isEnabled       — master on/off for expansion (default: true)
///   - launchAtLogin   — whether Poof starts automatically on login (default: false)
///
/// Posting `Preferences.didChange` lets open UI (menu, snippet manager) refresh
/// when a value changes.

import Foundation
import ServiceManagement

final class Preferences {
    static let shared = Preferences()
    static let didChange = Notification.Name("com.poof.prefsDidChange")

    private let defaults = UserDefaults.standard

    private enum Key {
        static let triggerPrefix = "com.poof.triggerPrefix"
        static let isEnabled     = "com.poof.isEnabled"
        static let launchAtLogin = "com.poof.launchAtLogin"
    }

    private init() {
        // Default isEnabled to true on first run (bool defaults to false otherwise).
        if defaults.object(forKey: Key.isEnabled) == nil {
            defaults.set(true, forKey: Key.isEnabled)
        }
    }

    // MARK: - Trigger prefix

    /// The single character that must lead every snippet, e.g. "/" in "/shrug".
    /// Stored as a single-character string; the setter trims to the first
    /// character and rejects empty strings.
    var triggerPrefix: String {
        get { defaults.string(forKey: Key.triggerPrefix) ?? "/" }
        set {
            let val = String(newValue.prefix(1))
            defaults.set(val.isEmpty ? "/" : val, forKey: Key.triggerPrefix)
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    // MARK: - Master enable

    var isEnabled: Bool {
        get { defaults.bool(forKey: Key.isEnabled) }
        set {
            defaults.set(newValue, forKey: Key.isEnabled)
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    // MARK: - Launch at login

    /// When true, registers Poof with macOS to launch automatically at login.
    /// Uses SMAppService (macOS 13+). On macOS 12 the toggle is a no-op
    /// (SMLoginItemSetEnabled requires a signed helper bundle).
    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set {
            defaults.set(newValue, forKey: Key.launchAtLogin)
            applyLaunchAtLogin(newValue)
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled { try SMAppService.mainApp.register() }
                else       { try SMAppService.mainApp.unregister() }
            } catch {
                print("Poof: launch at login error: \(error)")
            }
        }
        // macOS 12 fallback: silently ignored.
    }
}
