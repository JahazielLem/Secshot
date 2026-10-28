// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import SwiftUI
import UniformTypeIdentifiers

/// Text capture (OCR): last capture with the recognized boxes, output format, editable text and history.
struct TextCaptureView: View {
    @ObservedObject private var store = TextCaptureStore.shared
    @EnvironmentObject var library: LibraryStore
    @ViewState private var showBoxes = true
    @AppStorage(Prefs.copyText) private var copyText = true
    @ViewState private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.entries.isEmpty {
                emptyState
            } else {
                HSplitView {
                    imagePane.frame(minWidth: 380, idealWidth: 480)
                    textPane.frame(minWidth: 420)
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { (UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image)) ?? false })
            else { return false }
            store.recognizeFile(url)
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Button { store.captureArea() } label: { Label("Capture Text", systemImage: "text.viewfinder") }
                .buttonStyle(.borderedProminent)
                .help("Select an area of the screen and copy its text (⌘⇧2 from any app)")
            Button { store.importImageWithPanel() } label: { Label("From Image…", systemImage: "photo") }
            Button { _ = store.recognizeClipboardImage() } label: { Label("From Clipboard", systemImage: "doc.on.clipboard") }
                .help("Recognize an image copied to the clipboard")
            if store.busy { ProgressView().controlSize(.small) }
            Spacer()
            Toggle("Copy automatically", isOn: $copyText)
                .help("When on, ⌘⇧2 copies the recognized text straight to the clipboard")
            Picker("Format", selection: $store.format) {
                ForEach(TextOutputFormat.allCases) { f in Label(f.label, systemImage: f.symbol).tag(f) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Output format used by ⌘⇧2 and the Copy button")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.viewfinder").font(.system(size: 52)).foregroundStyle(.secondary)
            Text("Capture text from anywhere").font(.title2.bold())
            Text("Press **⌘⇧2**, select an area, and the text is copied to the clipboard as \(store.format.label).")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Label("**Markdown** turns tables into Markdown tables and keeps lists and headings.", systemImage: "number")
                Label("**Plain text** keeps line breaks; table columns are separated by tabs (paste into a spreadsheet).", systemImage: "text.alignleft")
                Label("**CSV** for spreadsheets.", systemImage: "tablecells")
            }
            .font(.callout)
            .frame(maxWidth: 560, alignment: .leading)
            Button { store.captureArea() } label: { Label("Capture Text  ⌘⇧2", systemImage: "text.viewfinder") }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            Text("Recognized on this Mac with Apple Vision. Captured images are not saved unless you add them to the library.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Image and history

    private var imagePane: some View {
        VStack(spacing: 0) {
            ZStack {
                CheckerboardView().opacity(0.4)
                if let entry = store.selected {
                    GeometryReader { geo in
                        let size = fitted(CGSize(width: entry.image.width, height: entry.image.height), in: geo.size)
                        ZStack(alignment: .topLeading) {
                            Image(decorative: entry.image, scale: 1).resizable().frame(width: size.width, height: size.height)
                            if showBoxes {
                                Canvas { ctx, _ in
                                    for f in entry.fragments {
                                        let r = CGRect(x: f.rect.minX * size.width, y: f.rect.minY * size.height,
                                                       width: f.rect.width * size.width, height: f.rect.height * size.height)
                                        ctx.fill(Path(r.insetBy(dx: -2, dy: -1)), with: .color(.accentColor.opacity(0.12)))
                                        ctx.stroke(Path(r.insetBy(dx: -2, dy: -1)), with: .color(.accentColor.opacity(0.8)), lineWidth: 1)
                                    }
                                }
                                .frame(width: size.width, height: size.height)
                            }
                        }
                        .frame(width: size.width, height: size.height)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                    .padding(12)
                }
            }
            HStack {
                Toggle("Show detected text", isOn: $showBoxes).controlSize(.small)
                Spacer()
                if let entry = store.selected {
                    Button { saveToLibrary(entry) } label: { Label("Add Image to Library", systemImage: "tray.and.arrow.down") }
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            history.frame(height: 170)
        }
    }

    private var history: some View {
        List(selection: Binding(get: { store.selectedID }, set: { store.selectedID = $0 })) {
            Section("Recent (kept in memory)") {
                ForEach(store.entries) { entry in
                    HStack(spacing: 8) {
                        Image(decorative: entry.image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                            .frame(width: 44, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.preview).lineLimit(1).font(.callout)
                            Text("\(entry.source) · \(entry.date.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tag(Optional(entry.id))
                    .contextMenu {
                        Button("Remove", role: .destructive) { store.remove(entry.id) }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: Text

    private var textPane: some View {
        VStack(spacing: 0) {
            CodeTextEditor(text: $store.text)
                .padding(10)
            Divider()
            HStack {
                Text(store.summary).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) { store.clear() } label: { Image(systemName: "trash") }
                    .help("Clear recent text captures")
                Button { store.copyCurrent() } label: { Label("Copy \(store.format.label)", systemImage: "doc.on.doc") }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .buttonStyle(.borderedProminent)
                    .help("Copy the text (⇧⌘C). You can edit it before copying.")
            }
            .controlSize(.small)
            .padding(10)
        }
    }

    private func fitted(_ image: CGSize, in box: CGSize) -> CGSize {
        let s = min(box.width / max(image.width, 1), box.height / max(image.height, 1), 1)
        return CGSize(width: image.width * s, height: image.height * s)
    }

    private func saveToLibrary(_ entry: TextCaptureEntry) {
        let first = entry.fragments.first?.text ?? ""
        if let item = library.addImage(entry.image, mode: "region", notes: "Text capture: \(first.prefix(120))") {
            ToastHUD.show("Added to the library", subtitle: item.name, symbol: "tray.and.arrow.down.fill")
        }
    }
}
