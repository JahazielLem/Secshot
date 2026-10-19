// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import Foundation
import ServiceManagement

/// Launch at login through a LaunchAgent bundled in `Contents/Library/LaunchAgents`.
/// Unlike `SMAppService.mainApp`, the agent passes `--background`, so the app knows it
/// must start without opening any windows.
enum LoginItem {
    static let plistName = "local.secshot.app.login.plist"
    static var agent: SMAppService { SMAppService.agent(plistName: plistName) }

    static var isEnabled: Bool {
        agent.status == .enabled || agent.status == .requiresApproval
    }

    static var needsApproval: Bool { agent.status == .requiresApproval }

    static func set(_ on: Bool) throws {
        if on { try agent.register() } else { try agent.unregister() }
    }

    /// Earlier versions registered the whole app (`mainApp`), which launched with windows.
    static func migrateLegacyRegistration() {
        guard SMAppService.mainApp.status == .enabled else { return }
        try? SMAppService.mainApp.unregister()
        try? agent.register()
    }
}
