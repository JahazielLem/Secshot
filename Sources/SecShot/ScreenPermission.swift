// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import AppKit

/// Screen Recording permission handling.
///
/// macOS ties the permission to the app's code signature. When the signature changes (e.g. an
/// ad-hoc build replaced by a signed one), System Settings keeps showing SecShot as enabled but
/// the entry no longer matches, so access is denied. Instead of re-triggering the system prompt
/// on every launch, SecShot explains the situation and offers to remove the stale entry.
@MainActor
enum ScreenPermission {
    private static let requestedKey = "screenCaptureAccessRequested"
    private static var alertVisible = false

    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Called at launch. The first time, macOS shows its own prompt; afterwards SecShot shows a
    /// guided alert instead of repeating the system prompt.
    static func checkAtLaunch() {
        guard !isGranted else { return }
        let defaults = UserDefaults.standard
        // Existing users (non-empty library) already went through the system prompt once.
        if !defaults.bool(forKey: requestedKey) && LibraryStore.shared.items.isEmpty {
            defaults.set(true, forKey: requestedKey)
            CGRequestScreenCaptureAccess()
        } else {
            presentAlert()
        }
    }

    /// Returns `true` when capturing is allowed; otherwise shows the guided alert.
    static func ensure() -> Bool {
        if isGranted { return true }
        presentAlert()
        return false
    }

    static func presentAlert() {
        guard !alertVisible else { return }
        alertVisible = true
        defer { alertVisible = false }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "SecShot needs Screen Recording access"
        alert.informativeText = """
        macOS is not granting SecShot access to the screen right now.

        If SecShot already appears enabled in System Settings, that entry belongs to a previous \
        build with a different signature. Click “Repair Permission” to remove the stale entry, \
        then enable SecShot again in the list and choose “Quit & Reopen”.
        """
        alert.addButton(withTitle: "Repair Permission")
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: repair()
        case .alertSecondButtonReturn: openSettings()
        default: break
        }
    }

    /// Removes SecShot's (possibly stale) Screen Recording entry and registers it again.
    static func repair() {
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "ScreenCapture", Bundle.main.bundleIdentifier ?? "local.secshot.app"]
        try? reset.run()
        reset.waitUntilExit()
        CGRequestScreenCaptureAccess()   // adds SecShot back to the list
        openSettings()
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// macOS only applies a newly granted permission after the app restarts.
    static func relaunch() {
        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
        relauncher.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? relauncher.run()
        NSApp.terminate(nil)
    }
}
