// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import Carbon.HIToolbox
import Foundation

/// Global hotkeys via Carbon (no Accessibility permission required).
final class HotKeyManager {
    static let shared = HotKeyManager()
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []

    func setup() {
        install()
        let mods = UInt32(controlKey | shiftKey)
        register(UInt32(kVK_ANSI_3), mods) { CaptureService.shared.capture(.fullscreen) }
        register(UInt32(kVK_ANSI_4), mods) { CaptureService.shared.capture(.region) }
        register(UInt32(kVK_ANSI_5), mods) { CaptureService.shared.capture(.window) }
        register(UInt32(kVK_ANSI_2), mods) { CaptureBar.shared.toggle() }
        register(UInt32(kVK_ANSI_6), mods) { WindowManager.shared.showCode() }
        register(UInt32(kVK_ANSI_7), mods) { WindowManager.shared.showCompare() }
        register(UInt32(kVK_ANSI_8), mods) { WindowManager.shared.showTraffic() }
    }

    private func install() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            if status == noErr {
                let id = hk.id
                DispatchQueue.main.async { HotKeyManager.shared.handlers[id]?() }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }

    private func register(_ key: UInt32, _ mods: UInt32, _ action: @escaping @MainActor () -> Void) {
        let id = UInt32(handlers.count + 1)
        handlers[id] = { MainActor.assumeIsolated { action() } }
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x5343_5348), id: id)  // 'SCSH'
        if RegisterEventHotKey(key, mods, hkID, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
            refs.append(ref)
        }
    }
}
