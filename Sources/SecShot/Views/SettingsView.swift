// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: LibraryStore
    @AppStorage(Prefs.namePrefix) private var prefix = "EVIDENCE-"
    @AppStorage(Prefs.digits) private var digits = 0
    @AppStorage(Prefs.shadow) private var shadow = true
    @AppStorage(Prefs.cornerRadius) private var corner = 10.0
    @AppStorage(Prefs.transparentBG) private var transparent = true
    @AppStorage(Prefs.playSound) private var sound = false
    @AppStorage(Prefs.hideDuringCapture) private var hide = true
    @AppStorage(Prefs.openEditor) private var openEditor = true
    @AppStorage(Prefs.copyAfterCapture) private var copyAfter = false
    @AppStorage(Prefs.exportFormat) private var format = "png"
    @AppStorage(Prefs.retinaDPI) private var retina = true
    @AppStorage(Prefs.defaultRedaction) private var redaction = AnnotationKind.pixelate.rawValue
    @AppStorage(Prefs.captureBar) private var captureBar = true
    @ObservedObject private var barState = CaptureBar.shared.state
    @ViewState private var launchAtLogin = LoginItem.isEnabled
    @ViewState private var loginError: String?
    @ViewState private var screenAccess = ScreenPermission.isGranted

    var body: some View {
        Form {
            Section("Evidence Naming") {
                TextField("Prefix", text: $prefix)
                Picker("Numbering", selection: $digits) {
                    Text("1, 2, 3…").tag(0)
                    Text("01, 02, 03…").tag(2)
                    Text("001, 002, 003…").tag(3)
                }
                LabeledContent("Next name") {
                    Text(store.peekNextName()).font(.body.monospaced()).id("\(prefix)\(digits)")
                }
                Button("Reset Counter for “\(prefix)”") { store.resetCounter() }
                Text("Each prefix keeps its own counter. Numbers already used in the library are never reused.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Open SecShot at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
                Text("At login, SecShot starts in the background: only the capture bar, the menu bar icon and the hotkeys.")
                    .font(.caption).foregroundStyle(.secondary)
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                if !Bundle.main.bundlePath.hasPrefix("/Applications") {
                    Text("To use it as a regular app, install it in /Applications with scripts/install.sh.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Floating Capture Bar") {
                Toggle("Show capture bar (⌃⇧2)", isOn: $captureBar)
                    .onChange(of: captureBar) { CaptureBar.shared.setEnabled(captureBar) }
                Picker("Position", selection: Binding(get: { barState.position }, set: { CaptureBar.shared.setPosition($0) })) {
                    ForEach(BarPosition.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!captureBar)
                Text("You can also drag it: drop it near an edge to dock it, or anywhere else to leave it there.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Permissions") {
                LabeledContent("Screen Recording") {
                    Label(screenAccess ? "Granted" : "Not granted",
                          systemImage: screenAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(screenAccess ? .green : .orange)
                }
                if !screenAccess {
                    Text("If SecShot already looks enabled in System Settings, the entry belongs to an older build. Repair it, enable SecShot again and relaunch.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Repair Permission") { ScreenPermission.repair() }
                        Button("Relaunch SecShot") { ScreenPermission.relaunch() }
                    }
                }
            }
            .onAppear { screenAccess = ScreenPermission.isGranted }

            Section("Capture") {
                Toggle("Hide SecShot while capturing", isOn: $hide)
                Toggle("Open the editor after capturing", isOn: $openEditor)
                Toggle("Copy to clipboard after capturing", isOn: $copyAfter)
                Toggle("Shutter sound", isOn: $sound)
                LabeledContent("Global hotkeys") {
                    Text("⌃⇧4 region · ⌃⇧5 window · ⌃⇧3 screen · ⌃⇧2 bar").font(.callout)
                }
                Button("Open Screen Recording Permissions…") { ScreenPermission.openSettings() }
            }

            Section("Decoration & Export") {
                Toggle("macOS-style shadow", isOn: $shadow)
                HStack {
                    Text("Rounded corners")
                    Slider(value: $corner, in: 0...24, step: 1)
                    Text("\(Int(corner)) pt").monospacedDigit().frame(width: 40)
                }
                .disabled(!shadow)
                Toggle("Transparent background (PNG)", isOn: $transparent)
                Picker("Format", selection: $format) {
                    ForEach(ExportFormat.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("Mark as 144 DPI (Retina size in Word/Pages)", isOn: $retina)
                Text("Exports are re-encoded without EXIF metadata (author, device, location).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Security") {
                Picker("Automatic redaction", selection: $redaction) {
                    Text("Pixelate").tag(AnnotationKind.pixelate.rawValue)
                    Text("Hardened blur").tag(AnnotationKind.blur.rawValue)
                    Text("Solid redaction (recommended for secrets)").tag(AnnotationKind.redact.rawValue)
                }
            }

            Section("Library") {
                LabeledContent("Folder") {
                    Text(store.directory.path).font(.caption.monospaced()).textSelection(.enabled)
                }
                Button("Show in Finder") { store.revealInFinder([]) }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 600)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            try LoginItem.set(on)
            loginError = LoginItem.needsApproval
                ? "Approve it in System Settings → General → Login Items." : nil
        } catch {
            loginError = "Could not change it: \(error.localizedDescription)"
            launchAtLogin = LoginItem.isEnabled
        }
    }
}
