// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var store: LibraryStore
    @AppStorage(Prefs.namePrefix) private var prefix = "EVIDENCE-"
    @AppStorage(Prefs.digits) private var digits = 0
    @ViewState private var search = ""
    @ViewState private var renameTarget: UUID?
    @ViewState private var renameText = ""

    private var filtered: [CaptureItem] {
        guard !search.isEmpty else { return store.libraryItems }
        return store.libraryItems.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.notes.localizedCaseInsensitiveContains(search)
        }
    }

    private var grouped: [(String, [CaptureItem])] {
        var result: [(String, [CaptureItem])] = []
        for item in filtered {
            let key = Fmt.dayTitle(item.createdAt)
            if let i = result.firstIndex(where: { $0.0 == key }) { result[i].1.append(item) } else { result.append((key, [item])) }
        }
        return result
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 420)
        } detail: {
            detail
        }
        .frame(minWidth: 1000, minHeight: 620)
        .alert("Rename Evidence", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let id = renameTarget { store.rename(id, to: renameText) }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(CaptureMode.allCases) { mode in
                        Button { CaptureService.shared.capture(mode) } label: {
                            VStack(spacing: 3) {
                                Image(systemName: mode.symbol).font(.system(size: 16))
                                Text(mode == .window ? "Window" : mode == .region ? "Region" : "Screen").font(.caption2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.bordered)
                        .help("\(mode.label) (\(mode.hotkey))")
                    }
                }
                HStack(spacing: 6) {
                    Menu {
                        Button("Library Captures") { WindowManager.shared.showCompare() }
                        Button("External Images…") { WindowManager.shared.showCompare(external: true) }
                    } label: {
                        Label("Compare / Timeline", systemImage: "rectangle.split.2x1").frame(maxWidth: .infinity)
                    } primaryAction: {
                        WindowManager.shared.showCompare()
                    }
                    Button { WindowManager.shared.showCode() } label: { Image(systemName: "chevron.left.forwardslash.chevron.right") }
                        .help("Code snippet (⌘4)")
                    Button { store.importWithPanel() } label: { Image(systemName: "square.and.arrow.down") }
                        .help("Import images")
                    Button { WindowManager.shared.showSettings() } label: { Image(systemName: "gearshape") }
                        .help("Settings")
                }
                .controlSize(.small)

                HStack(spacing: 6) {
                    Image(systemName: "tag").foregroundStyle(.secondary)
                    TextField("Prefix", text: $prefix)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .help("Naming convention: new captures are saved as PREFIX-1, PREFIX-2…")
                    Text("→ \(store.peekNextName())")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .id("\(prefix)-\(digits)-\(store.libraryItems.count)")
                }
            }
            .padding(10)

            Divider()

            List(selection: $store.selection) {
                if store.libraryItems.isEmpty {
                    Text("No captures yet.\nPress ⌃⇧4 to capture a region.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .padding(.vertical, 20)
                }
                ForEach(grouped, id: \.0) { day, items in
                    Section(day) {
                        ForEach(items) { item in
                            CaptureRow(item: item)
                                .tag(item.id)
                                .contextMenu { contextMenu(for: item) }
                                .onDrag {
                                    if let url = ExportService.dragFile(for: item), let provider = NSItemProvider(contentsOf: url) {
                                        return provider
                                    }
                                    return NSItemProvider()
                                }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $search, placement: .sidebar, prompt: "Search by name or note")
            .onDeleteCommand { store.moveToTrash(store.selection) }
            .dropDestination(for: URL.self) { urls, _ in
                let images = urls.filter { (UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image)) ?? false }
                store.importFiles(images)
                return !images.isEmpty
            }

            Divider()
            HStack {
                Text("\(store.libraryItems.count) captures").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { store.revealInFinder([]) } label: { Image(systemName: "folder") }
                    .buttonStyle(.borderless)
                    .help("Open the library folder")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func contextMenu(for item: CaptureItem) -> some View {
        let targets = store.selection.contains(item.id) ? store.selection : [item.id]
        Button("Rename…") { renameText = item.name; renameTarget = item.id }
        Button("Apply Convention \(prefix)N") { store.applyConvention(to: targets) }
        Divider()
        Button("Use as Comparison BASE") { store.compareBaseID = item.id; WindowManager.shared.showCompare() }
        Button("Use as Comparison CHANGE") { store.compareChangeID = item.id; WindowManager.shared.showCompare() }
        Button("Add to Timeline") {
            let ordered = store.libraryItems.filter { targets.contains($0.id) }.sorted { $0.createdAt < $1.createdAt }
            for i in ordered where !store.timelineIDs.contains(i.id) { store.timelineIDs.append(i.id) }
            WindowManager.shared.showCompare()
        }
        Divider()
        Button("Copy Final Image") { ExportService.copy(item) }
        Button("Export…") { ExportService.export(item) }
        Button("Export Selection with Manifest…") {
            ExportService.exportBatch(store.libraryItems.filter { targets.contains($0.id) })
        }
        Button("Show in Finder") { store.revealInFinder(targets) }
        Divider()
        Button("Move to Trash", role: .destructive) { store.moveToTrash(targets) }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if store.selection.count == 1, let item = store.item(store.selection.first) {
            EditorView(item: item).id(item.id)
        } else if store.selection.count > 1 {
            MultiSelectionView(items: store.libraryItems.filter { store.selection.contains($0.id) })
        } else if store.libraryItems.isEmpty {
            EmptyStateView()
        } else {
            HistoryGrid(items: filtered, title: "Capture History")
        }
    }
}

struct CaptureRow: View {
    @EnvironmentObject var store: LibraryStore
    let item: CaptureItem

    var body: some View {
        HStack(spacing: 10) {
            ThumbnailView(item: item, maxPixel: 160)
                .frame(width: 64, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.system(.body, design: .monospaced)).fontWeight(.medium).lineLimit(1)
                HStack(spacing: 4) {
                    Text(item.createdAt, format: .dateTime.hour().minute().second())
                    Text("·")
                    Text(item.modeLabel)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if item.annotations.contains(where: { $0.kind.isRedaction }) {
                Image(systemName: "eye.slash").font(.caption).foregroundStyle(.orange).help("Contains redactions")
            } else if item.isEdited {
                Image(systemName: "pencil.tip").font(.caption).foregroundStyle(.secondary).help("Edited")
            }
        }
        .padding(.vertical, 2)
    }
}

struct ThumbnailView: View {
    @EnvironmentObject var store: LibraryStore
    let item: CaptureItem
    var maxPixel: Int = 360

    var body: some View {
        ZStack {
            Color(nsColor: .quaternaryLabelColor).opacity(0.3)
            if let img = store.thumbnail(for: item, maxPixel: maxPixel) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
    }
}

struct HistoryGrid: View {
    @EnvironmentObject var store: LibraryStore
    let items: [CaptureItem]
    let title: String
    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.title2.bold())
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            ThumbnailView(item: item, maxPixel: 480)
                                .frame(height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(item.name).font(.system(.callout, design: .monospaced)).bold().lineLimit(1)
                            Text("\(Fmt.dateTime.string(from: item.createdAt)) · \(item.modeLabel)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
                        .contentShape(Rectangle())
                        .onTapGesture { store.selection = [item.id] }
                    }
                }
            }
            .padding(20)
        }
    }
}

struct MultiSelectionView: View {
    @EnvironmentObject var store: LibraryStore
    @AppStorage(Prefs.namePrefix) private var prefix = "EVIDENCE-"
    let items: [CaptureItem]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("\(items.count) captures selected").font(.headline)
                Spacer()
                Button("Apply Convention \(prefix)N") { store.applyConvention(to: Set(items.map(\.id))) }
                    .help("Renames in chronological order using the current prefix")
                Button("Timeline") {
                    store.timelineIDs = items.sorted { $0.createdAt < $1.createdAt }.map(\.id)
                    WindowManager.shared.showCompare()
                }
                if items.count == 2 {
                    Button("Compare") {
                        let o = items.sorted { $0.createdAt < $1.createdAt }
                        store.compareBaseID = o[0].id
                        store.compareChangeID = o[1].id
                        WindowManager.shared.showCompare()
                    }
                }
                Button("Export with Manifest…") { ExportService.exportBatch(items) }
                    .buttonStyle(.borderedProminent)
                Button(role: .destructive) { store.moveToTrash(Set(items.map(\.id))) } label: { Image(systemName: "trash") }
            }
            .padding(12)
            Divider()
            HistoryGrid(items: items, title: "Selection")
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.viewfinder").font(.system(size: 56)).foregroundStyle(.secondary)
            Text("SecShot").font(.largeTitle.bold())
            Text("Evidence screenshots for security reports").foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(CaptureMode.allCases) { mode in
                    Button { CaptureService.shared.capture(mode) } label: {
                        Label("\(mode.label)  \(mode.hotkey)", systemImage: mode.symbol)
                    }
                    .controlSize(.large)
                }
            }
            Text("Hotkeys work from any app. If captures come out empty, grant SecShot the\n“Screen Recording” permission in System Settings → Privacy & Security.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
