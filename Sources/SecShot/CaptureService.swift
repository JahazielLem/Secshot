// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import AppKit

enum CaptureMode: String, CaseIterable, Identifiable {
    case region, window, fullscreen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .region: return "Region"
        case .window: return "Window / app"
        case .fullscreen: return "Full screen"
        }
    }

    var symbol: String {
        switch self {
        case .region: return "rectangle.dashed"
        case .window: return "macwindow"
        case .fullscreen: return "display"
        }
    }

    var hotkey: String {
        switch self {
        case .region: return "⌃⇧4"
        case .window: return "⌃⇧5"
        case .fullscreen: return "⌃⇧3"
        }
    }

    /// /usr/sbin/screencapture arguments for each mode.
    var arguments: [String] {
        switch self {
        case .region: return ["-i", "-s"]   // rectangle selection (Esc cancels)
        case .window: return ["-i", "-w"]   // click on a window
        case .fullscreen: return ["-m"]     // main display
        }
    }
}

/// Captures with the native macOS engine (`screencapture`) to keep its familiar UX.
@MainActor
final class CaptureService {
    static let shared = CaptureService()
    private var isCapturing = false

    func capture(_ mode: CaptureMode, delay: Int = 0, openEditor: Bool? = nil,
                 completion: ((CaptureItem?) -> Void)? = nil) {
        guard !isCapturing else { return }
        isCapturing = true
        CaptureBar.shared.suspend()

        let defaults = UserDefaults.standard
        let hide = defaults.bool(forKey: Prefs.hideDuringCapture)
        let wasActive = NSApp.isActive
        let shouldOpen = openEditor ?? defaults.bool(forKey: Prefs.openEditor)
        if hide { NSApp.hide(nil) }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("secshot-\(UUID().uuidString).png")
        var args = ["-o", "-t", "png"]   // -o: no shadow; the shadow is added on export
        if !defaults.bool(forKey: Prefs.playSound) { args.append("-x") }
        if delay > 0 { args += ["-T", String(delay)] }
        args += mode.arguments
        args.append(tmp.path)

        DispatchQueue.main.asyncAfter(deadline: .now() + (hide ? 0.35 : 0.05)) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = args
            process.terminationHandler = { _ in
                Task { @MainActor in
                    CaptureService.shared.finish(tmp: tmp, mode: mode, hid: hide, wasActive: wasActive,
                                                 open: shouldOpen, completion: completion)
                }
            }
            do {
                try process.run()
            } catch {
                NSLog("SecShot: screencapture failed: \(error)")
                self.finish(tmp: tmp, mode: mode, hid: hide, wasActive: wasActive, open: false, completion: completion)
            }
        }
    }

    private func finish(tmp: URL, mode: CaptureMode, hid: Bool, wasActive: Bool, open: Bool,
                        completion: ((CaptureItem?) -> Void)?) {
        isCapturing = false
        CaptureBar.shared.resume()
        let store = LibraryStore.shared
        var item: CaptureItem?
        if let attrs = try? FileManager.default.attributesOfItem(atPath: tmp.path),
           (attrs[.size] as? Int ?? 0) > 0 {
            item = store.addImage(fileAt: tmp, mode: mode.rawValue, moveFile: true)
        }

        if let item, UserDefaults.standard.bool(forKey: Prefs.copyAfterCapture),
           let img = store.image(for: item) {
            ExportService.copyImage(img)
        }

        if let item, open {
            store.selection = [item.id]
            WindowManager.shared.showLibrary()
        } else if hid {
            if wasActive { NSApp.unhide(nil) } else { NSApp.unhideWithoutActivation() }
        }
        completion?(item)
    }
}
