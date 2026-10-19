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

    func showLibrary() {
        show("library", title: "SecShot — Evidence Library", size: NSSize(width: 1320, height: 820)) {
            AnyView(LibraryView().environmentObject(LibraryStore.shared))
        }
    }

    func showCompare() {
        show("compare", title: "SecShot — Comparison & Timeline", size: NSSize(width: 1280, height: 800)) {
            AnyView(CompareView().environmentObject(LibraryStore.shared))
        }
    }

    func showSettings() {
        show("settings", title: "SecShot — Settings", size: NSSize(width: 560, height: 680)) {
            AnyView(SettingsView().environmentObject(LibraryStore.shared))
        }
    }
}
