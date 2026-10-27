// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import AppKit
import SwiftUI

/// Top-level sections of the main window. New features (findings, projects, reports…) are added
/// here instead of opening more windows.
enum AppSection: String, CaseIterable, Identifiable {
    case library, compare, code, traffic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "Evidence Library"
        case .compare: return "Compare & Timeline"
        case .code: return "Code Snippet"
        case .traffic: return "HTTP Traffic"
        }
    }

    var shortTitle: String {
        switch self {
        case .library: return "Library"
        case .compare: return "Compare"
        case .code: return "Code"
        case .traffic: return "Traffic"
        }
    }

    var symbol: String {
        switch self {
        case .library: return "photo.stack"
        case .compare: return "rectangle.split.2x1"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .traffic: return "arrow.left.arrow.right.square"
        }
    }

    var shortcut: String {
        switch self {
        case .library: return "⌘1"
        case .compare: return "⌘2"
        case .code: return "⌘4"
        case .traffic: return "⌘5"
        }
    }
}

@MainActor
final class AppNavigation: ObservableObject {
    static let shared = AppNavigation()
    @Published var section: AppSection = .library
}

/// Single main window: a navigation rail on the left and the selected section on the right.
struct MainWindowView: View {
    @ObservedObject private var nav = AppNavigation.shared

    var body: some View {
        HStack(spacing: 0) {
            NavigationRail(selection: $nav.section)
            Divider()
            Group {
                switch nav.section {
                case .library: LibraryView()
                case .compare: CompareWindowView()
                case .code: CodeShotView()
                case .traffic: TrafficView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("SecShot — \(nav.section.title)")
        .frame(minWidth: 1180, minHeight: 700)
    }
}

private struct NavigationRail: View {
    @Binding var selection: AppSection

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 34, height: 34)
                .padding(.top, 12)
                .padding(.bottom, 10)

            ForEach(AppSection.allCases) { section in
                RailButton(symbol: section.symbol, title: section.shortTitle, selected: selection == section) {
                    selection = section
                }
                .help("\(section.title) (\(section.shortcut))")
            }

            Divider().frame(width: 40).padding(.vertical, 6)

            RailButton(symbol: "rectangle.dashed", title: "Capture", selected: false) {
                CaptureService.shared.capture(.region)
            }
            .help("Capture a region (⌃⇧4)")

            Spacer()

            RailButton(symbol: "gearshape", title: "Settings", selected: false) {
                WindowManager.shared.showSettings()
            }
            .help("Settings (⌘,)")
            .padding(.bottom, 10)
        }
        .frame(width: 78)
        .frame(maxHeight: .infinity)
        .background(SidebarMaterial())
    }
}

private struct RailButton: View {
    let symbol: String
    let title: String
    let selected: Bool
    let action: () -> Void
    @ViewState private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 18, weight: .medium))
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .frame(width: 64, height: 50)
            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            .background(RoundedRectangle(cornerRadius: 9)
                .fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(hover ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .sidebar
        v.blendingMode = .behindWindow
        v.state = .followsWindowActiveState
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
