// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import AppKit
import SwiftUI

/// Position of the floating capture bar (⌘⇧5 style).
enum BarPosition: String, CaseIterable, Identifiable {
    case bottom, top, left, right, free

    var id: String { rawValue }
    var vertical: Bool { self == .left || self == .right }

    var label: String {
        switch self {
        case .bottom: return "Bottom"
        case .top: return "Top"
        case .left: return "Left"
        case .right: return "Right"
        case .free: return "Free (where you drop it)"
        }
    }

    var symbol: String {
        switch self {
        case .bottom: return "rectangle.bottomthird.inset.filled"
        case .top: return "rectangle.topthird.inset.filled"
        case .left: return "rectangle.leftthird.inset.filled"
        case .right: return "rectangle.rightthird.inset.filled"
        case .free: return "hand.draw"
        }
    }
}

@MainActor
final class CaptureBarState: ObservableObject {
    @Published var position: BarPosition
    @Published var timer: Int {
        didSet { UserDefaults.standard.set(timer, forKey: Prefs.captureBarTimer) }
    }

    init() {
        let d = UserDefaults.standard
        position = BarPosition(rawValue: d.string(forKey: Prefs.captureBarPosition) ?? "") ?? .bottom
        timer = d.integer(forKey: Prefs.captureBarTimer)
    }
}

/// Panel that does not steal focus from the active app but still accepts clicks and menus.
final class CaptureBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CaptureBar: NSObject, NSWindowDelegate {
    static let shared = CaptureBar()

    let state = CaptureBarState()
    /// Called when toggled (used to update the status menu checkmark).
    var onChange: (() -> Void)?

    private var panel: CaptureBarPanel?
    private var programmaticMove = false
    private var suspended = false
    private var snapWork: DispatchWorkItem?

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Prefs.captureBar) }

    // MARK: Enable / disable

    func restore() {
        if isEnabled { show() }
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Prefs.captureBar)
        if on { show() } else { panel?.orderOut(nil) }
        onChange?()
    }

    func toggle() { setEnabled(!isEnabled) }

    private func show() {
        let p = panel ?? makePanel()
        panel = p
        p.orderFrontRegardless()
        place()
    }

    // MARK: During capture

    func suspend() {
        guard let p = panel, p.isVisible else { return }
        suspended = true
        p.orderOut(nil)
    }

    func resume() {
        guard suspended else { return }
        suspended = false
        if isEnabled { panel?.orderFrontRegardless() }
    }

    // MARK: Position

    func setPosition(_ position: BarPosition) {
        state.position = position
        UserDefaults.standard.set(position.rawValue, forKey: Prefs.captureBarPosition)
        if position == .free, let o = panel?.frame.origin {
            UserDefaults.standard.set(Double(o.x), forKey: Prefs.captureBarX)
            UserDefaults.standard.set(Double(o.y), forKey: Prefs.captureBarY)
        }
        // Wait for SwiftUI to recompute the size (horizontal ↔ vertical) before repositioning.
        DispatchQueue.main.async { self.place() }
    }

    private func place() {
        guard let p = panel else { return }
        let size = p.frame.size
        let m: CGFloat = 14
        var origin: CGPoint
        let screen: NSScreen

        if state.position == .free {
            let d = UserDefaults.standard
            let saved = CGPoint(x: d.double(forKey: Prefs.captureBarX), y: d.double(forKey: Prefs.captureBarY))
            screen = NSScreen.screens.first { $0.frame.contains(saved) } ?? NSScreen.main ?? NSScreen.screens[0]
            origin = saved
        } else {
            screen = p.screen ?? NSScreen.main ?? NSScreen.screens[0]
            let vf = screen.visibleFrame
            switch state.position {
            case .bottom: origin = CGPoint(x: vf.midX - size.width / 2, y: vf.minY + m)
            case .top: origin = CGPoint(x: vf.midX - size.width / 2, y: vf.maxY - size.height - m)
            case .left: origin = CGPoint(x: vf.minX + m, y: vf.midY - size.height / 2)
            case .right: origin = CGPoint(x: vf.maxX - size.width - m, y: vf.midY - size.height / 2)
            case .free: origin = .zero
            }
        }

        let vf = screen.visibleFrame
        origin.x = min(max(origin.x, vf.minX), vf.maxX - size.width)
        origin.y = min(max(origin.y, vf.minY), vf.maxY - size.height)

        programmaticMove = true
        p.setFrameOrigin(origin)
        p.invalidateShadow()
        DispatchQueue.main.async { self.programmaticMove = false }
    }

    /// When the bar is dropped: dock it to a nearby edge, otherwise leave it floating.
    private func snapAfterDrag() {
        guard let p = panel else { return }
        if NSEvent.pressedMouseButtons != 0 {
            scheduleSnap()
            return
        }
        guard let screen = p.screen ?? NSScreen.main else { return }
        let vf = screen.visibleFrame, f = p.frame, t: CGFloat = 70
        let target: BarPosition
        if f.minY - vf.minY < t { target = .bottom }
        else if vf.maxY - f.maxY < t { target = .top }
        else if f.minX - vf.minX < t { target = .left }
        else if vf.maxX - f.maxX < t { target = .right }
        else { target = .free }
        setPosition(target)
    }

    private func scheduleSnap() {
        snapWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.snapAfterDrag() }
        snapWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    // MARK: NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard !programmaticMove else { return }
        scheduleSnap()
    }

    func windowDidResize(_ notification: Notification) {
        place()
    }

    // MARK: Panel

    private func makePanel() -> CaptureBarPanel {
        let host = NSHostingController(rootView: CaptureBarView(state: state))
        host.sizingOptions = [.preferredContentSize]
        let p = CaptureBarPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 60),
                                styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                                backing: .buffered, defer: false)
        p.contentViewController = host
        p.title = "SecShot Capture Bar"
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.sharingType = .none   // excluded from screenshots
        p.isReleasedWhenClosed = false
        p.delegate = self
        return p
    }
}

// MARK: - View

struct CaptureBarView: View {
    @ObservedObject var state: CaptureBarState

    var body: some View {
        let vertical = state.position.vertical
        let stack = vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))

        stack {
            Image(systemName: vertical ? "line.3.horizontal" : "line.3.horizontal")
                .rotationEffect(.degrees(vertical ? 0 : 90))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: vertical ? 58 : 16, height: vertical ? 16 : 42)
                .help("Drag to move. Drop it near an edge to dock it.")

            separator(vertical)

            ForEach(CaptureMode.allCases) { mode in
                BarButton(symbol: mode.symbol, title: mode == .window ? "Window" : mode == .region ? "Region" : "Screen",
                          help: "\(mode.label) (\(mode.hotkey))") {
                    CaptureService.shared.capture(mode, delay: state.timer)
                }
            }

            separator(vertical)

            BarMenu(symbol: state.timer == 0 ? "timer" : "timer.circle.fill",
                    title: state.timer == 0 ? "No delay" : "\(state.timer) s", help: "Timer") {
                Picker("Timer", selection: $state.timer) {
                    Text("No delay").tag(0)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                }
                .pickerStyle(.inline)
            }

            BarMenu(symbol: "rectangle.split.2x1", title: "Compare", help: "Comparison and timeline") {
                Button("Capture BASE (region)") { captureSlot(base: true) }
                Button("Capture CHANGE (region)") { captureSlot(base: false) }
                Button("Capture Timeline Step") {
                    CaptureService.shared.capture(.region, delay: state.timer, openEditor: false) { item in
                        if let item { LibraryStore.shared.timelineIDs.append(item.id) }
                        WindowManager.shared.showCompare()
                    }
                }
                Divider()
                Button("Open Comparison…") { WindowManager.shared.showCompare() }
            }

            BarButton(symbol: "photo.stack", title: "Library", help: "Open the library") {
                WindowManager.shared.showLibrary()
            }

            separator(vertical)

            BarMenu(symbol: "ellipsis.circle", title: "Options", help: "Position and options") {
                Picker("Position", selection: Binding(get: { state.position }, set: { CaptureBar.shared.setPosition($0) })) {
                    ForEach(BarPosition.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Button("Settings…") { WindowManager.shared.showSettings() }
                Button("Hide Bar (⌃⇧2)") { CaptureBar.shared.setEnabled(false) }
            }

            Button { CaptureBar.shared.setEnabled(false) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: vertical ? 58 : 26, height: vertical ? 26 : 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Hide the bar (use ⌃⇧2 or the SecShot menu to show it again)")
        }
        .padding(6)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }

    @ViewBuilder
    private func separator(_ vertical: Bool) -> some View {
        Rectangle().fill(Color.white.opacity(0.15))
            .frame(width: vertical ? 40 : 1, height: vertical ? 1 : 30)
            .padding(vertical ? .vertical : .horizontal, 4)
    }

    private func captureSlot(base: Bool) {
        CaptureService.shared.capture(.region, delay: state.timer, openEditor: false) { item in
            if let item {
                if base { LibraryStore.shared.compareBaseID = item.id } else { LibraryStore.shared.compareChangeID = item.id }
            }
            WindowManager.shared.showCompare()
        }
    }
}

private struct BarItemLabel: View {
    let symbol: String
    let title: String
    let hover: Bool

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 17))
            Text(title).font(.system(size: 9.5, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(.primary)
        .frame(width: 62, height: 44)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(hover ? 0.16 : 0)))
        .contentShape(Rectangle())
    }
}

struct BarButton: View {
    let symbol: String
    let title: String
    let help: String
    let action: () -> Void
    @ViewState private var hover = false

    var body: some View {
        Button(action: action) { BarItemLabel(symbol: symbol, title: title, hover: hover) }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .help(help)
    }
}

struct BarMenu<Content: View>: View {
    let symbol: String
    let title: String
    let help: String
    @ViewBuilder let content: () -> Content
    @ViewState private var hover = false

    var body: some View {
        Menu(content: content) { BarItemLabel(symbol: symbol, title: title, hover: hover) }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .onHover { hover = $0 }
            .help(help)
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
