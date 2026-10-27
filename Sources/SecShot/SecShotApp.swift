// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import AppKit
import SwiftUI

@main
struct SecShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        CommandLineTools.runIfRequested()
        Prefs.register()
    }

    var body: some Scene {
        // Invisible "anchor" scene. SwiftUI's `Settings` scene is not used because macOS opens it
        // automatically at launch when the app has no other windows (e.g. at login).
        MenuBarExtra("SecShot", systemImage: "camera.viewfinder", isInserted: .constant(false)) {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { WindowManager.shared.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("Library") { WindowManager.shared.showLibrary() }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Comparison / Timeline") { WindowManager.shared.showCompare() }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Compare External Images…") { WindowManager.shared.showCompare(external: true) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Code Snippet…") { WindowManager.shared.showCode() }
                    .keyboardShortcut("4", modifiers: .command)
                Divider()
                Button("Import Images…") { LibraryStore.shared.importWithPanel() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("Capture") {
                ForEach(CaptureMode.allCases) { mode in
                    Button("\(mode.label)  (\(mode.hotkey))") { CaptureService.shared.capture(mode) }
                }
                Divider()
                Button("Full Screen in 5 s") { CaptureService.shared.capture(.fullscreen, delay: 5) }
                Button("Region in 5 s") { CaptureService.shared.capture(.region, delay: 5) }
                Divider()
                Button("Show/Hide Capture Bar  (⌃⇧2)") { CaptureBar.shared.toggle() }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var barMenuItem: NSMenuItem?

    /// When SecShot is opened at login it starts without windows: only the capture bar
    /// (if enabled), the menu bar icon and the global hotkeys.

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Never restore windows from the previous session.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        if let id = Bundle.main.bundleIdentifier {
            let saved = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Saved Application State/\(id).savedState")
            try? FileManager.default.removeItem(at: saved)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.register()
        NSApp.setActivationPolicy(.regular)
        setupStatusItem()
        HotKeyManager.shared.setup()
        LoginItem.migrateLegacyRegistration()
        if !LoginItem.launchedAtLogin() {
            WindowManager.shared.showLibrary()
            DispatchQueue.main.async { ScreenPermission.checkAtLaunch() }
        }
        CaptureBar.shared.onChange = { [weak self] in self?.updateBarMenuItem() }
        CaptureBar.shared.restore()
        updateBarMenuItem()
    }

    private func updateBarMenuItem() {
        barMenuItem?.state = CaptureBar.shared.isEnabled ? .on : .off
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowManager.shared.showLibrary() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "SecShot")
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, _ key: String = "") {
            let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
            mi.target = self
            menu.addItem(mi)
        }
        add("Capture Region   ⌃⇧4", #selector(captureRegion))
        add("Capture Window   ⌃⇧5", #selector(captureWindow))
        add("Capture Screen   ⌃⇧3", #selector(captureFull))
        add("Screen in 5 s", #selector(captureDelayed))
        menu.addItem(.separator())
        add("Compare: Capture BASE", #selector(captureBase))
        add("Compare: Capture CHANGE", #selector(captureChange))
        menu.addItem(.separator())
        add("Capture Bar   ⌃⇧2", #selector(toggleBar))
        barMenuItem = menu.items.last
        add("Library…", #selector(openLibrary))
        add("Comparison / Timeline…   ⌃⇧7", #selector(openCompare))
        add("Compare External Images…", #selector(openCompareExternal))
        add("Code Snippet…   ⌃⇧6", #selector(openCode))
        add("Settings…", #selector(openSettings))
        menu.addItem(.separator())
        add("Quit SecShot", #selector(quit), "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func captureRegion() { CaptureService.shared.capture(.region) }
    @objc private func captureWindow() { CaptureService.shared.capture(.window) }
    @objc private func captureFull() { CaptureService.shared.capture(.fullscreen) }
    @objc private func captureDelayed() { CaptureService.shared.capture(.fullscreen, delay: 5) }
    @objc private func captureBase() {
        CaptureService.shared.capture(.region, openEditor: false) { item in
            if let item { LibraryStore.shared.compareBaseID = item.id }
            WindowManager.shared.showCompare()
        }
    }
    @objc private func captureChange() {
        CaptureService.shared.capture(.region, openEditor: false) { item in
            if let item { LibraryStore.shared.compareChangeID = item.id }
            WindowManager.shared.showCompare()
        }
    }
    @objc private func toggleBar() { CaptureBar.shared.toggle() }
    @objc private func openLibrary() { WindowManager.shared.showLibrary() }
    @objc private func openCompare() { WindowManager.shared.showCompare() }
    @objc private func openCompareExternal() { WindowManager.shared.showCompare(external: true) }
    @objc private func openCode() { WindowManager.shared.showCode() }
    @objc private func openSettings() { WindowManager.shared.showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
