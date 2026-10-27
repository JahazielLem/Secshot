// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum CompareMode: String, CaseIterable, Identifiable {
    case sideBySide, stacked, diff, slider, timeline

    var id: String { rawValue }
    var label: String {
        switch self {
        case .sideBySide: return "Side by side"
        case .stacked: return "Stacked (top / bottom)"
        case .diff: return "Highlighted differences"
        case .slider: return "Before/after slider"
        case .timeline: return "Timeline (N steps)"
        }
    }
}

/// Where the images being compared come from.
enum CompareScope {
    /// Evidence captured with SecShot.
    case library
    /// External images added only for comparison (not evidence until saved).
    case workspace
}

/// Comparison window: one tab for library captures, one for external images.
struct CompareWindowView: View {
    @AppStorage(WindowManager.compareTabKey) private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            CompareView(scope: .library)
                .tabItem { Label("Library Captures", systemImage: "photo.stack") }
                .tag(0)
            CompareView(scope: .workspace)
                .tabItem { Label("External Images", systemImage: "photo.on.rectangle.angled") }
                .tag(1)
        }
        .padding(.top, 6)
        .frame(minWidth: 980, minHeight: 640)
    }
}

struct CompareView: View {
    @EnvironmentObject var store: LibraryStore
    let scope: CompareScope
    @ViewState private var mode: CompareMode = .sideBySide
    @ViewState private var baseLabel = "BEFORE"
    @ViewState private var changeLabel = "AFTER"
    @ViewState private var useEdits = true
    @ViewState private var sensitivity: Double = 30
    @ViewState private var tint = true
    @ViewState private var onlyChange = false
    @ViewState private var fraction: Double = 0.5
    @ViewState private var horizontal = true
    @ViewState private var result: CGImage?
    @ViewState private var sliderImages: (CGImage, CGImage)?
    @ViewState private var summary = ""
    @ViewState private var working = false
    @ViewState private var generation = 0
    @ViewState private var dropTargeted = false

    // MARK: Scope-dependent state

    private var baseID: UUID? {
        get { scope == .library ? store.compareBaseID : store.workspaceBaseID }
        nonmutating set { if scope == .library { store.compareBaseID = newValue } else { store.workspaceBaseID = newValue } }
    }

    private var changeID: UUID? {
        get { scope == .library ? store.compareChangeID : store.workspaceChangeID }
        nonmutating set { if scope == .library { store.compareChangeID = newValue } else { store.workspaceChangeID = newValue } }
    }

    private var timeline: [UUID] {
        get { scope == .library ? store.timelineIDs : store.workspaceTimelineIDs }
        nonmutating set { if scope == .library { store.timelineIDs = newValue } else { store.workspaceTimelineIDs = newValue } }
    }

    private var scopeItems: [CaptureItem] { scope == .library ? store.libraryItems : store.workspaceItems }

    private static let blue = CGColor(srgbRed: 0.18, green: 0.40, blue: 0.85, alpha: 1)
    private static let red = CGColor(srgbRed: 0.84, green: 0.20, blue: 0.22, alpha: 1)
    private static let palette: [CGColor] = [
        CGColor(srgbRed: 0.18, green: 0.40, blue: 0.85, alpha: 1),
        CGColor(srgbRed: 0.42, green: 0.30, blue: 0.80, alpha: 1),
        CGColor(srgbRed: 0.75, green: 0.30, blue: 0.62, alpha: 1),
        CGColor(srgbRed: 0.84, green: 0.20, blue: 0.22, alpha: 1),
    ]

    private var regenKey: String {
        [mode.rawValue, baseID?.uuidString ?? "", changeID?.uuidString ?? "",
         timeline.map(\.uuidString).joined(), baseLabel, changeLabel, "\(useEdits)", "\(Int(sensitivity))",
         "\(tint)", "\(onlyChange)", "\(horizontal)", "\(store.items.count)", "\(store.editRevision)"].joined(separator: "|")
    }

    var body: some View {
        HSplitView {
            controls.frame(minWidth: 300, idealWidth: 330, maxWidth: 400)
            previewArea.frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 960, minHeight: 600)
        .onAppear(perform: regenerate)
        .onChange(of: regenKey) { regenerate() }
        .dropDestination(for: URL.self) { urls, _ in
            guard scope == .workspace else { return false }
            return addExternal(urls)
        } isTargeted: { dropTargeted = scope == .workspace && $0 }
    }

    // MARK: Controls

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if scope == .workspace {
                    workspacePanel
                }

                Picker("Mode", selection: $mode) {
                    ForEach(CompareMode.allCases) { Text($0.label).tag($0) }
                }

                if mode == .timeline {
                    timelineControls
                } else {
                    SlotPicker(title: "BASE (initial state)", accent: .blue,
                               itemID: Binding(get: { baseID }, set: { baseID = $0 }), label: $baseLabel,
                               items: scopeItems, scope: scope)
                    HStack {
                        Spacer()
                        Button {
                            let b = baseID
                            baseID = changeID
                            changeID = b
                        } label: { Label("Swap", systemImage: "arrow.up.arrow.down") }
                            .controlSize(.small)
                        Spacer()
                    }
                    SlotPicker(title: "CHANGE (evidence of the change)", accent: .red,
                               itemID: Binding(get: { changeID }, set: { changeID = $0 }), label: $changeLabel,
                               items: scopeItems, scope: scope)
                }

                GroupBox("Options") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Include annotations and redactions", isOn: $useEdits)
                        if mode == .diff {
                            HStack {
                                Text("Sensitivity")
                                Slider(value: $sensitivity, in: 5...120)
                            }
                            .help("Minimum per-channel difference (0–255) for a pixel to count as changed")
                            Toggle("Tint changed pixels", isOn: $tint)
                            Toggle("Changes image only", isOn: $onlyChange)
                        }
                        if mode == .timeline {
                            Picker("Orientation", selection: $horizontal) {
                                Text("Horizontal").tag(true)
                                Text("Vertical").tag(false)
                            }
                            .pickerStyle(.segmented)
                        }
                        if mode == .slider {
                            Text("Drag over the preview to move the divider.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Result") {
                    VStack(alignment: .leading, spacing: 8) {
                        Button { saveToLibrary() } label: {
                            Label("Save as Evidence (\(store.peekNextName()))", systemImage: "tray.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasOutput)
                        HStack {
                            Button { if let img = outputImage() { ExportService.copyImage(img); summary = "Image copied to the clipboard." } } label: { Label("Copy", systemImage: "doc.on.doc") }
                                .keyboardShortcut("c", modifiers: [.command, .shift])
                                .help("Copy the result (⇧⌘C)")
                            Button { if let img = outputImage() { ExportService.save(img, suggestedName: "comparison") } } label: { Label("Export…", systemImage: "square.and.arrow.up") }
                        }
                        .disabled(!hasOutput)
                        if !summary.isEmpty {
                            Text(summary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
        }
    }

    private var timelineControls: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                if timeline.isEmpty {
                    Text(scope == .library
                         ? "Add captures in attack-chain order, or capture each step directly."
                         : "Add external images in the order of the flow you want to show.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(timeline.enumerated()), id: \.element) { idx, id in
                    if let item = store.item(id) {
                        HStack(spacing: 6) {
                            Text("\(idx + 1).").font(.caption.monospacedDigit()).frame(width: 20)
                            ThumbnailView(item: item, maxPixel: 120).frame(width: 46, height: 30)
                            Text(item.name).font(.caption.monospaced()).lineLimit(1)
                            Spacer()
                            Button { moveTimeline(idx, -1) } label: { Image(systemName: "chevron.up") }.disabled(idx == 0)
                            Button { moveTimeline(idx, 1) } label: { Image(systemName: "chevron.down") }.disabled(idx == timeline.count - 1)
                            Button { timeline.remove(at: idx) } label: { Image(systemName: "xmark") }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Menu("Add") {
                        ForEach(scopeItems) { item in
                            Button(item.name) { timeline.append(item.id) }
                        }
                    }
                    if scope == .library {
                        Menu("Capture Step") {
                            ForEach(CaptureMode.allCases) { m in
                                Button(m.label) {
                                    CaptureService.shared.capture(m, openEditor: false) { item in
                                        if let item { store.timelineIDs.append(item.id) }
                                        WindowManager.shared.showCompare()
                                    }
                                }
                            }
                        }
                        Button("Use Selection") {
                            store.timelineIDs = store.libraryItems.filter { store.selection.contains($0.id) }
                                .sorted { $0.createdAt < $1.createdAt }.map(\.id)
                        }
                        .disabled(store.selection.count < 2)
                    } else {
                        Button("Add All") { timeline = store.workspaceItems.map(\.id) }
                            .disabled(store.workspaceItems.isEmpty)
                    }
                }
                .controlSize(.small)
                if !timeline.isEmpty {
                    Button("Clear", role: .destructive) { timeline.removeAll() }.controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: { Label("Steps", systemImage: "list.number") }
    }

    private func moveTimeline(_ idx: Int, _ delta: Int) {
        let to = idx + delta
        guard timeline.indices.contains(to) else { return }
        timeline.swapAt(idx, to)
    }

    // MARK: External images

    private var workspacePanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Button { chooseExternal() } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down.on.square").font(.title2)
                        Text("Drop images here or click to choose").font(.callout)
                        Text("PNG, JPEG, HEIC, TIFF… They stay out of your evidence library.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 86)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(dropTargeted ? 0.15 : 0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                ForEach(store.workspaceItems) { item in
                    WorkspaceRow(item: item,
                                 isBase: baseID == item.id,
                                 isChange: changeID == item.id,
                                 inTimeline: timeline.contains(item.id),
                                 setBase: { baseID = item.id; if mode == .timeline { mode = .sideBySide } },
                                 setChange: { changeID = item.id; if mode == .timeline { mode = .sideBySide } },
                                 toggleTimeline: {
                                     if let i = timeline.firstIndex(of: item.id) { timeline.remove(at: i) } else { timeline.append(item.id) }
                                 })
                }
                if !store.workspaceItems.isEmpty {
                    Button("Remove All", role: .destructive) {
                        store.moveToTrash(Set(store.workspaceItems.map(\.id)))
                    }
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: { Label("External Images", systemImage: "photo.on.rectangle.angled") }
    }

    private func chooseExternal() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        panel.prompt = "Add"
        panel.message = "Choose images to compare. They are not added to your evidence library."
        guard panel.runModal() == .OK else { return }
        _ = addExternal(panel.urls)
    }

    /// Adds dropped/chosen images and fills the empty slots so a comparison appears right away.
    private func addExternal(_ urls: [URL]) -> Bool {
        let images = urls.filter { (UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image)) ?? false }
        let added = store.addWorkspaceImages(images)
        guard !added.isEmpty else { return false }
        if mode == .timeline {
            timeline.append(contentsOf: added.map(\.id))
        } else {
            var queue = added.map(\.id)
            if baseID == nil, !queue.isEmpty { baseID = queue.removeFirst() }
            if changeID == nil, !queue.isEmpty { changeID = queue.removeFirst() }
            if !queue.isEmpty { timeline.append(contentsOf: queue) }
        }
        return true
    }

    // MARK: Preview

    @ViewBuilder
    private var previewArea: some View {
        ZStack {
            CheckerboardView().opacity(0.5)
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.08)))
                    .padding(12)
            }
            if mode == .slider, let (b, c) = sliderImages {
                SliderCompare(base: b, change: c, fraction: $fraction, baseLabel: baseLabel, changeLabel: changeLabel)
                    .padding(20)
            } else if let result {
                Image(decorative: result, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fit).padding(20)
            } else if !working {
                VStack(spacing: 10) {
                    Image(systemName: scope == .workspace ? "photo.on.rectangle.angled" : "rectangle.split.2x1")
                        .font(.system(size: 44)).foregroundStyle(.secondary)
                    Text(emptyMessage).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            if working { ProgressView() }
        }
    }

    private var emptyMessage: String {
        switch (scope, mode == .timeline) {
        case (.library, true): return "Add at least 2 captures to the timeline"
        case (.library, false): return "Choose or capture a BASE and a CHANGE"
        case (.workspace, true): return "Drop images here, then add them to the timeline"
        case (.workspace, false): return "Drop two images here (or choose them on the left)\nto compare a BASE and a CHANGE"
        }
    }

    private var hasOutput: Bool { mode == .slider ? sliderImages != nil : result != nil }

    private func outputImage() -> CGImage? {
        if mode == .slider, let (b, c) = sliderImages {
            return Renderer.split(base: b, change: c, fraction: fraction, baseLabel: baseLabel, changeLabel: changeLabel)
        }
        return result
    }

    // MARK: Generation

    private func source(_ item: CaptureItem) -> CGImage? {
        useEdits ? store.renderedImage(for: item) : store.image(for: item)
    }

    private func subtitle(_ item: CaptureItem) -> String {
        "\(item.name) · \(Fmt.dateTime.string(from: item.createdAt))"
    }

    private func regenerate() {
        generation += 1
        let gen = generation
        result = nil
        sliderImages = nil
        summary = ""

        if mode == .timeline {
            let items = timeline.compactMap { store.item($0) }
            guard items.count >= 1 else { return }
            let panels: [Renderer.Panel] = items.enumerated().compactMap { i, item in
                guard let img = source(item) else { return nil }
                let accent = Self.palette[min(Self.palette.count - 1, i * Self.palette.count / max(1, items.count))]
                return Renderer.Panel(image: img, title: "STEP \(i + 1) — \(item.name)",
                                      subtitle: Fmt.dateTime.string(from: item.createdAt) + (item.notes.isEmpty ? "" : " · \(item.notes)"),
                                      accent: accent)
            }
            let h = horizontal
            run(gen) { (Renderer.compose(panels, horizontal: h, connectors: true), "Timeline with \(panels.count) steps.") }
            return
        }

        guard let bItem = store.item(baseID), let cItem = store.item(changeID),
              let b = source(bItem), let c = source(cItem) else { return }

        switch mode {
        case .slider:
            sliderImages = (b, c)
        case .sideBySide, .stacked:
            let panels = [Renderer.Panel(image: b, title: baseLabel, subtitle: subtitle(bItem), accent: Self.blue),
                          Renderer.Panel(image: c, title: changeLabel, subtitle: subtitle(cItem), accent: Self.red)]
            let h = mode == .sideBySide
            run(gen) { (Renderer.compose(panels, horizontal: h, connectors: false), "") }
        case .diff:
            let threshold = Int(sensitivity), tint = tint, only = onlyChange
            let bl = baseLabel, cl = changeLabel, bs = subtitle(bItem), cs = subtitle(cItem)
            run(gen) {
                guard let d = Renderer.highlightDifferences(base: b, change: c, threshold: threshold, tint: tint) else { return (nil, "") }
                let pct = String(format: "%.2f", d.changedRatio * 100)
                let info = "\(d.regions.count) changed regions · \(pct)% of pixels modified"
                if only { return (d.image, info) }
                let panels = [Renderer.Panel(image: b, title: bl, subtitle: bs, accent: Self.blue),
                              Renderer.Panel(image: d.image, title: "\(cl) — changes highlighted", subtitle: "\(cs) · \(info)", accent: Self.red)]
                return (Renderer.compose(panels, horizontal: true, connectors: false), info)
            }
        case .timeline:
            break
        }
    }

    private func run(_ gen: Int, _ work: @escaping () -> (CGImage?, String)) {
        working = true
        Task.detached(priority: .userInitiated) {
            let (img, info) = work()
            await MainActor.run {
                guard gen == generation else { return }
                result = img
                summary = info
                working = false
            }
        }
    }

    private func saveToLibrary() {
        guard let img = outputImage() else { return }
        var notes: String
        let modeKey: String
        if mode == .timeline {
            modeKey = "timeline"
            notes = "Timeline: " + timeline.compactMap { store.item($0)?.name }.joined(separator: " → ")
        } else {
            modeKey = "comparison"
            notes = "Comparison \(baseLabel): \(store.item(baseID)?.name ?? "?") vs \(changeLabel): \(store.item(changeID)?.name ?? "?"). \(summary)"
        }
        if scope == .workspace { notes = "Built from external images. " + notes }
        if let item = store.addImage(img, mode: modeKey, notes: notes) {
            store.selection = [item.id]
            summary = "Saved as \(item.name)."
        }
    }
}

// MARK: - Slot (base / change)

struct SlotPicker: View {
    @EnvironmentObject var store: LibraryStore
    let title: String
    let accent: Color
    @Binding var itemID: UUID?
    @Binding var label: String
    let items: [CaptureItem]
    let scope: CompareScope
    @ViewState private var targeted = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle().fill(accent).frame(width: 9, height: 9)
                    Text(title).font(.headline)
                }
                ZStack {
                    if let item = store.item(itemID) {
                        ThumbnailView(item: item, maxPixel: 480)
                    } else {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                            .foregroundStyle(.secondary)
                        Text(scope == .library ? "No capture" : "Drop an image here").font(.caption).foregroundStyle(.secondary)
                    }
                    if targeted {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 3)
                    }
                }
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .dropDestination(for: URL.self) { urls, _ in
                    guard scope == .workspace, let item = store.addWorkspaceImages(Array(urls.prefix(1))).first else { return false }
                    itemID = item.id
                    return true
                } isTargeted: { targeted = scope == .workspace && $0 }

                Picker(scope == .library ? "Capture" : "Image", selection: $itemID) {
                    Text("—").tag(UUID?.none)
                    ForEach(items) { Text($0.name).tag(Optional($0.id)) }
                }
                TextField("Label", text: $label).textFieldStyle(.roundedBorder)
                HStack(spacing: 6) {
                    if scope == .library {
                        Text("Capture now:").font(.caption).foregroundStyle(.secondary)
                        ForEach(CaptureMode.allCases) { m in
                            Button {
                                CaptureService.shared.capture(m, openEditor: false) { item in
                                    if let item { itemID = item.id }
                                    WindowManager.shared.showCompare()
                                }
                            } label: { Image(systemName: m.symbol) }
                                .help(m.label)
                        }
                    } else {
                        Button { chooseImage() } label: { Label("Choose Image…", systemImage: "folder") }
                    }
                    if let item = store.item(itemID) {
                        Spacer()
                        Button { WindowManager.shared.showEditor(item) } label: { Label("Edit", systemImage: "pencil.tip") }
                            .help("Annotate, redact, add a focus spotlight or zoom")
                    }
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension SlotPicker {
    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let item = store.addWorkspaceImages(panel.urls).first else { return }
        itemID = item.id
    }
}

// MARK: - External image row

struct WorkspaceRow: View {
    @EnvironmentObject var store: LibraryStore
    let item: CaptureItem
    let isBase: Bool
    let isChange: Bool
    let inTimeline: Bool
    let setBase: () -> Void
    let setChange: () -> Void
    let toggleTimeline: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ThumbnailView(item: item, maxPixel: 160)
                .frame(width: 56, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.caption.weight(.medium)).lineLimit(1)
                HStack(spacing: 4) {
                    if isBase { tag("BASE", .blue) }
                    if isChange { tag("CHANGE", .red) }
                    if inTimeline { tag("TIMELINE", .purple) }
                    if item.isEdited { Image(systemName: "pencil.tip").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button("Use as BASE", action: setBase)
                Button("Use as CHANGE", action: setChange)
                Button(inTimeline ? "Remove from Timeline" : "Add to Timeline", action: toggleTimeline)
                Divider()
                Button("Edit…") { WindowManager.shared.showEditor(item) }
                Button("Add to Evidence Library") { store.promoteToLibrary(item.id) }
                Divider()
                Button("Remove", role: .destructive) { store.moveToTrash([item.id]) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { WindowManager.shared.showEditor(item) }
        .help("Double-click to edit")
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 8.5, weight: .bold)).foregroundStyle(.white)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.85)))
    }
}

// MARK: - Interactive slider

struct SliderCompare: View {
    let base: CGImage
    let change: CGImage
    @Binding var fraction: Double
    let baseLabel: String
    let changeLabel: String

    var body: some View {
        GeometryReader { geo in
            let W = CGFloat(max(base.width, change.width)), H = CGFloat(max(base.height, change.height))
            let s = min(geo.size.width / W, geo.size.height / H)
            let w = W * s, h = H * s
            let x = CGFloat(fraction) * w
            ZStack(alignment: .topLeading) {
                Color.white
                Image(decorative: base, scale: 1).resizable()
                    .frame(width: CGFloat(base.width) * s, height: CGFloat(base.height) * s)
                ZStack(alignment: .topLeading) {
                    Color.white
                    Image(decorative: change, scale: 1).resizable()
                        .frame(width: CGFloat(change.width) * s, height: CGFloat(change.height) * s)
                }
                .frame(width: w, height: h, alignment: .topLeading)
                .mask(alignment: .topLeading) {
                    Rectangle().frame(width: max(0, w - x), height: h).offset(x: x)
                }
                Rectangle().fill(.white).frame(width: 3, height: h).shadow(radius: 3).offset(x: x - 1.5)
                Circle().fill(.white).frame(width: 26, height: 26).shadow(radius: 3)
                    .overlay(Image(systemName: "arrow.left.and.right").font(.caption.bold()).foregroundStyle(.black))
                    .offset(x: x - 13, y: h / 2 - 13)
                badge(baseLabel, .blue).offset(x: 10, y: 10)
                badge(changeLabel, .red).frame(width: w - 10, alignment: .trailing).offset(y: 10)
            }
            .frame(width: w, height: h)
            .clipped()
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                fraction = Double(min(max(v.location.x / w, 0), 1))
            })
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption.bold()).foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.9)))
    }
}
