// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import AppKit
import Carbon.HIToolbox
import ServiceManagement

/// Launch at login.
///
/// Uses `SMAppService.mainApp`. A bundled LaunchAgent (`SMAppService.agent`) cannot be used:
/// macOS only lets launchd start agents signed with an Apple Team ID, so builds signed with a
/// local or self-signed certificate are killed with "Launch Constraint Violation".
/// Because `mainApp` cannot pass arguments, SecShot detects a login launch itself and then
/// starts in the background (no windows).
enum LoginItem {
    private static var service: SMAppService { .mainApp }
    private static let legacyAgentPlist = "local.secshot.app.login.plist"

    static var isEnabled: Bool {
        service.status == .enabled || service.status == .requiresApproval
    }

    static var needsApproval: Bool { service.status == .requiresApproval }

    static func set(_ on: Bool) throws {
        if on { try service.register() } else { try service.unregister() }
    }

    /// Earlier builds registered a LaunchAgent that macOS refuses to start without a Team ID.
    /// Replace it with the main-app login item.
    static func migrateLegacyRegistration() {
        let agent = SMAppService.agent(plistName: legacyAgentPlist)
        guard agent.status == .enabled || agent.status == .requiresApproval else { return }
        try? agent.unregister()
        try? service.register()
    }

    /// `true` when macOS opened SecShot as a login item. Call from `applicationDidFinishLaunching`.
    static func launchedAtLogin() -> Bool {
        if CommandLine.arguments.contains("--background") { return true }
        guard isEnabled else { return false }

        // 1) The "open application" event carries a login-item flag when the system launches us.
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.eventID == kAEOpenApplication,
           event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            return true
        }

        // 2) Fallback: the Dock starts when the user session begins; login items follow within seconds.
        guard let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier,
              let dockStart = processStart(dockPID),
              let selfStart = processStart(getpid()) else { return false }
        let delay = selfStart.timeIntervalSince(dockStart)
        return delay >= 0 && delay < 120
    }

    private static func processStart(_ pid: pid_t) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let tv = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }
}
