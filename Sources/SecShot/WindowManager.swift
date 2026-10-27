// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import AppKit
import SwiftUI

@MainActor
final class WindowManager {
    static let shared = WindowManager()
    private var windows: [String: NSWindow] = [:]

    private func show(_ key: String, title: String, size: NSSize, view: () -> AnyView) {
        if let w = windows[key] {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let host = NSHostingController(rootView: view())
        host.sceneBridgingOptions = [.toolbars, .title]
        let w = NSWindow(contentViewController: host)
        w.title = title
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(size)
        w.center()
        w.setFrameAutosaveName("SecShot.\(key)")
        w.isReleasedWhenClosed = false
        w.isRestorable = false
        windows[key] = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Brings up the main window on the given section.
    func showSection(_ section: AppSection) {
        AppNavigation.shared.section = section
        show("main", title: "SecShot", size: NSSize(width: 1460, height: 900)) {
            AnyView(MainWindowView().environmentObject(LibraryStore.shared))
        }
    }

    func showLibrary() { showSection(.library) }

    static let compareTabKey = "compareTab"

    /// Opens Compare & Timeline. `external: true` switches to the External Images tab.
    func showCompare(external: Bool = false) {
        UserDefaults.standard.set(external ? 1 : 0, forKey: Self.compareTabKey)
        showSection(.compare)
    }

    func showCode() { showSection(.code) }

    func showTraffic() { showSection(.traffic) }

    /// Opens an editor window for any item (used for external images in the comparison workspace).
    func showEditor(_ item: CaptureItem) {
        show("editor-\(item.id.uuidString)", title: "SecShot — Edit \(item.name)", size: NSSize(width: 1200, height: 780)) {
            AnyView(EditorView(item: item).environmentObject(LibraryStore.shared))
        }
    }

    func showSettings() {
        show("settings", title: "SecShot — Settings", size: NSSize(width: 560, height: 680)) {
            AnyView(SettingsView().environmentObject(LibraryStore.shared))
        }
    }
}
