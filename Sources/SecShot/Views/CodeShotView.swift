// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import SwiftUI
import UniformTypeIdentifiers

enum CodeShotMode: String, CaseIterable, Identifiable {
    case single, compare, timeline
    var id: String { rawValue }
    var label: String {
        switch self {
        case .single: return "Single"
        case .compare: return "Compare"
        case .timeline: return "Timeline"
        }
    }
}

struct CodeStep: Identifiable, Equatable {
    var id = UUID()
    var title = ""
    var code = ""
}

/// Everything that affects the rendered image (used to trigger re-rendering).
private struct RenderInput: Equatable {
    var mode: CodeShotMode
    var options: CodeShotOptions
    var base: String
    var change: String
    var baseLabel: String
    var changeLabel: String
    var compareHorizontal: Bool
    var showDiff: Bool
    var steps: [CodeStep]
    var timelineHorizontal: Bool
    var arrows: Bool
}

/// Turns pasted code, terminal sessions or HTTP traffic into styled images: a single snippet,
/// a before/after comparison with a line diff, or a numbered timeline.
/// Pasted text is kept in memory only; nothing is written to disk until an image is saved.
struct CodeShotView: View {
    @EnvironmentObject var store: LibraryStore

    // Content
    @AppStorage("code.mode") private var modeRaw = CodeShotMode.single.rawValue
    @ViewState private var code = CodeSamples.httpResponse
    @ViewState private var title = ""
    @ViewState private var highlightLines = ""
    @ViewState private var base = CodeSamples.compareBefore
    @ViewState private var change = CodeSamples.compareAfter
    @ViewState private var baseLabel = "ORIGINAL REQUEST"
    @ViewState private var changeLabel = "TAMPERED REQUEST"
    @ViewState private var showDiff = true
    @AppStorage("code.compareHorizontal") private var compareHorizontal = true
    @ViewState private var steps: [CodeStep] = CodeSamples.timelineSteps
    @ViewState private var selectedStep: UUID?
    @AppStorage("code.timelineHorizontal") private var timelineHorizontal = false
    @AppStorage("code.arrows") private var showArrows = true
    @AppStorage(Prefs.redactionText) private var redactionText = "[REDACTED]"

    // Style
    @AppStorage("code.language") private var language = CodeLanguage.auto.rawValue
    @AppStorage("code.theme") private var themeName = "Dracula"
    @AppStorage("code.frame") private var frame = CodeFrame.macOS.rawValue
    @AppStorage("code.background") private var background = CodeBackground.ocean.rawValue
    @AppStorage("code.padding") private var padding = 48.0
    @AppStorage("code.fontSize") private var fontSize = 14.0
    @AppStorage("code.lineNumbers") private var lineNumbers = true
    @AppStorage("code.maxColumns") private var maxColumns = 100
    @AppStorage("code.security") private var securityAnalysis = true
    @AppStorage("code.formatJSON") private var formatJSON = true
    @AppStorage("code.shadow") private var shadow = true
    @ViewState private var themes: [CodeTheme] = CodeThemeLibrary.all()
    @ViewState private var editingTheme: CodeTheme?
    @ViewState private var alertMessage: String?

    // Output
    @ViewState private var preview: CGImage?
    @ViewState private var detected: CodeLanguage = .auto
    @ViewState private var findings: [HeaderFinding] = []
    @ViewState private var summary = ""
    @ViewState private var renderTask: Task<Void, Never>?
    @ViewState private var status = ""

    private var mode: CodeShotMode { CodeShotMode(rawValue: modeRaw) ?? .single }
    private var theme: CodeTheme { themes.first { $0.name == themeName } ?? CodeTheme.builtIn[2] }

    private var options: CodeShotOptions {
        CodeShotOptions(code: code,
                        language: CodeLanguage(rawValue: language) ?? .auto,
                        theme: theme,
                        frame: CodeFrame(rawValue: frame) ?? .macOS,
                        background: CodeBackground(rawValue: background) ?? .ocean,
                        padding: padding, fontSize: fontSize, lineNumbers: lineNumbers,
                        title: mode == .single ? title : "", highlightLines: mode == .single ? highlightLines : "",
                        maxColumns: maxColumns, securityAnalysis: securityAnalysis,
                        formatJSON: formatJSON, redactionMarker: redactionText, shadow: shadow)
    }

    private var input: RenderInput {
        RenderInput(mode: mode, options: options, base: base, change: change, baseLabel: baseLabel, changeLabel: changeLabel,
                    compareHorizontal: compareHorizontal, showDiff: showDiff, steps: steps, timelineHorizontal: timelineHorizontal,
                    arrows: showArrows)
    }

    var body: some View {
        HSplitView {
            controls.frame(minWidth: 380, idealWidth: 440, maxWidth: 580)
            previewArea.frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1040, minHeight: 680)
        .onAppear {
            if selectedStep == nil { selectedStep = steps.first?.id }
            scheduleRender(immediately: true)
        }
        .onChange(of: input) { scheduleRender() }
        .sheet(item: Binding(get: { editingTheme.map(EditableTheme.init) }, set: { editingTheme = $0?.theme })) { item in
            ThemeEditorView(theme: item.theme) { saved in
                do {
                    let stored = try CodeThemeLibrary.save(saved)
                    themes = CodeThemeLibrary.all()
                    themeName = stored.name
                } catch { alertMessage = error.localizedDescription }
                editingTheme = nil
            } onCancel: { editingTheme = nil }
        }
        .alert("Theme", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(alertMessage ?? "") }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("Mode", selection: $modeRaw) {
                    ForEach(CodeShotMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("⌥⌘1 Single · ⌥⌘2 Compare · ⌥⌘3 Timeline")
                redactControls
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .background(modeShortcuts)

            switch mode {
            case .single: singleEditor
            case .compare: compareEditor
            case .timeline: timelineEditor
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    contentOptions
                    styleOptions
                    if !findings.isEmpty, mode != .timeline { findingsBox }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .frame(minHeight: 220)
        }
    }

    private func editor(_ text: Binding<String>, minHeight: CGFloat = 120) -> some View {
        CodeTextEditor(text: text)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)))
            .frame(minHeight: minHeight)
    }

    private func pasteButton(into text: Binding<String>) -> some View {
        Button("Paste") { if let s = NSPasteboard.general.string(forType: .string) { text.wrappedValue = s } }
    }

    /// "Redact" button plus the replacement text (also configurable in Settings → Security).
    private var redactControls: some View {
        HStack(spacing: 2) {
            Button {
                if !CodeRedactor.redactSelection() { status = "Select text in an editor to redact it." }
            } label: {
                Label("Redact", systemImage: "eye.slash")
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .help("Replace the selected text with “\(redactionText)” (⇧⌘R). Also in the editor's right-click menu.")
            Menu {
                ForEach(CodeRedactor.presets, id: \.self) { p in
                    Button { redactionText = p } label: {
                        if p == redactionText { Label(p, systemImage: "checkmark") } else { Text(p) }
                    }
                }
                Divider()
                Button("Custom Text in Settings…") { WindowManager.shared.showSettings() }
            } label: {
                Text(redactionText).font(.caption.monospaced()).lineLimit(1)
            }
            .menuIndicator(.visible)
            .fixedSize()
            .help("Replacement text")
        }
        .controlSize(.small)
    }

    /// Invisible buttons that provide the ⌥⌘1/2/3 mode shortcuts.
    private var modeShortcuts: some View {
        HStack {
            Button("") { modeRaw = CodeShotMode.single.rawValue }.keyboardShortcut("1", modifiers: [.command, .option])
            Button("") { modeRaw = CodeShotMode.compare.rawValue }.keyboardShortcut("2", modifiers: [.command, .option])
            Button("") { modeRaw = CodeShotMode.timeline.rawValue }.keyboardShortcut("3", modifiers: [.command, .option])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private var singleEditor: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Code").font(.headline)
                Spacer()
                Menu("Samples") {
                    ForEach(CodeSamples.all, id: \.0) { name, sample in
                        Button(name) { code = sample; title = "" }
                    }
                }
                .fixedSize()
                pasteButton(into: $code)
                Button("Clear") { code = "" }
            }
            .controlSize(.small)
            editor($code, minHeight: 200)
        }
        .padding(12)
    }

    private var compareEditor: some View {
        VStack(spacing: 6) {
            HStack {
                Circle().fill(Color.blue).frame(width: 8, height: 8)
                TextField("Label", text: $baseLabel).textFieldStyle(.roundedBorder)
                pasteButton(into: $base)
            }
            .controlSize(.small)
            editor($base)
            HStack {
                Button { swap(&base, &change); swap(&baseLabel, &changeLabel) } label: {
                    Label("Swap", systemImage: "arrow.up.arrow.down")
                }
                Spacer()
                Toggle("Arrows", isOn: $showArrows)
                    .help("Draw an arrow from the first snippet to the second")
                Toggle("Diff", isOn: $showDiff)
                    .help("Highlight removed and added lines")
                Picker("", selection: $compareHorizontal) {
                    Image(systemName: "rectangle.split.2x1").tag(true)
                    Image(systemName: "rectangle.split.1x2").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .controlSize(.small)
            HStack {
                Circle().fill(Color.red).frame(width: 8, height: 8)
                TextField("Label", text: $changeLabel).textFieldStyle(.roundedBorder)
                pasteButton(into: $change)
            }
            .controlSize(.small)
            editor($change)
        }
        .padding(12)
    }

    private var timelineEditor: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Steps").font(.headline)
                Spacer()
                Toggle("Arrows", isOn: $showArrows)
                    .help("Draw arrows between steps in reading order")
                Picker("", selection: $timelineHorizontal) {
                    Image(systemName: "arrow.down").tag(false)
                    Image(systemName: "arrow.right").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Button { addStep() } label: { Label("Add Step", systemImage: "plus") }
            }
            .controlSize(.small)
            VStack(spacing: 3) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { idx, step in
                    HStack(spacing: 6) {
                        Text("\(idx + 1)").font(.caption.monospacedDigit().bold()).frame(width: 18)
                        TextField("Step title", text: binding(for: step.id).title)
                            .textFieldStyle(.plain)
                        Button { moveStep(idx, -1) } label: { Image(systemName: "chevron.up") }.disabled(idx == 0)
                        Button { moveStep(idx, 1) } label: { Image(systemName: "chevron.down") }.disabled(idx == steps.count - 1)
                        Button { removeStep(step.id) } label: { Image(systemName: "xmark") }.disabled(steps.count <= 1)
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5)
                        .fill(selectedStep == step.id ? Color.accentColor.opacity(0.18) : Color.clear))
                    .contentShape(Rectangle())
                    .onTapGesture { selectedStep = step.id }
                }
            }
            if let id = selectedStep, steps.contains(where: { $0.id == id }) {
                HStack {
                    Text("Code of step \((steps.firstIndex { $0.id == id } ?? 0) + 1)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    pasteButton(into: binding(for: id).code)
                }
                .controlSize(.small)
                editor(binding(for: id).code, minHeight: 140)
            }
        }
        .padding(12)
    }

    private var contentOptions: some View {
        GroupBox("Content") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Language", selection: $language) {
                    ForEach(CodeLanguage.allCases) { Text($0.label).tag($0.rawValue) }
                }
                if mode == .single {
                    if language == CodeLanguage.auto.rawValue, detected != .auto {
                        Text("Detected: \(detected.label)").font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("Window title (automatic if empty)", text: $title)
                    TextField("Highlight lines, e.g. 1, 6-7", text: $highlightLines)
                }
                Toggle("Format JSON (indent minified JSON and HTTP bodies)", isOn: $formatJSON)
                Toggle("Line numbers", isOn: $lineNumbers)
                Toggle("Analyze HTTP security headers", isOn: $securityAnalysis)
                    .help("Marks each header as good / weak / informational and lists missing recommended headers.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var styleOptions: some View {
        GroupBox("Style") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Picker("Theme", selection: $themeName) {
                        Section("Built-in") {
                            ForEach(CodeTheme.builtIn, id: \.name) { Text($0.name).tag($0.name) }
                        }
                        let custom = themes.filter { CodeThemeLibrary.isCustom($0.name) }
                        if !custom.isEmpty {
                            Section("Custom") {
                                ForEach(custom, id: \.name) { Text($0.name).tag($0.name) }
                            }
                        }
                    }
                    Menu {
                        Button("Customize “\(theme.name)”…") { editingTheme = theme }
                        Button("Import Theme…") { importTheme() }
                        Button("Export “\(theme.name)”…") { exportTheme() }
                        Divider()
                        Button("Show Themes Folder") {
                            try? FileManager.default.createDirectory(at: CodeThemeLibrary.directory, withIntermediateDirectories: true)
                            NSWorkspace.shared.activateFileViewerSelecting([CodeThemeLibrary.directory])
                        }
                        if CodeThemeLibrary.isCustom(theme.name) {
                            Divider()
                            Button("Delete “\(theme.name)”", role: .destructive) {
                                CodeThemeLibrary.delete(theme.name)
                                themes = CodeThemeLibrary.all()
                                themeName = "Dracula"
                            }
                        }
                    } label: { Image(systemName: "paintpalette") }
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Customize, import (VS Code / TextMate) or export themes")
                }
                Picker("Window", selection: $frame) {
                    ForEach(CodeFrame.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("Background", selection: $background) {
                    ForEach(CodeBackground.allCases) { Text($0.label).tag($0.rawValue) }
                }
                HStack {
                    Text("Padding").frame(width: 80, alignment: .leading)
                    Slider(value: $padding, in: 0...120, step: 4)
                    Text("\(Int(padding))").monospacedDigit().frame(width: 30)
                }
                .disabled(background == CodeBackground.none.rawValue)
                HStack {
                    Text("Font size").frame(width: 80, alignment: .leading)
                    Slider(value: $fontSize, in: 10...24, step: 1)
                    Text("\(Int(fontSize))").monospacedDigit().frame(width: 30)
                }
                Stepper("Wrap at \(maxColumns) columns", value: $maxColumns, in: 40...200, step: 10)
                Toggle("Window shadow", isOn: $shadow)
                HStack(spacing: 6) {
                    Text("Presets:").font(.caption).foregroundStyle(.secondary)
                    Button("Terminal") { applyPreset(theme: "Terminal", frame: .plain, background: .none) }
                    Button("macOS") { applyPreset(theme: "Catppuccin Mocha", frame: .macOS, background: .candy) }
                    Button("Report") { applyPreset(theme: "GitHub Light", frame: .macOS, background: .none) }
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var findingsBox: some View {
        GroupBox(mode == .compare ? "Security headers (\(changeLabel))" : "Security headers") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(findings.enumerated()), id: \.offset) { _, f in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Circle().fill(Color(nsColor: CodeShotRenderer.color(f.level, CodeTheme.builtIn[2]))).frame(width: 7, height: 7)
                        Text(f.header == "missing" ? "Missing \(f.message)" : "\(f.header) — \(f.message)")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Preview

    private var previewArea: some View {
        VStack(spacing: 0) {
            ZStack {
                CheckerboardView().opacity(0.5)
                if let preview {
                    ScrollView([.vertical, .horizontal]) {
                        Image(decorative: preview, scale: 2)
                            .interpolation(.high)
                            .padding(20)
                    }
                } else {
                    Text("Paste code, a terminal session or an HTTP request/response").foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                Text(status.isEmpty ? summary : status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button { if let preview { ExportService.copyImage(preview); status = "Image copied to the clipboard." } } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("Copy the image (⇧⌘C)")
                Button { if let preview { ExportService.save(preview, suggestedName: "code-\(mode.rawValue)", options: pngOptions) } } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut("e", modifiers: .command)
                .help("Export the image (⌘E)")
                Button { saveToLibrary() } label: {
                    Label("Save as Evidence (\(store.peekNextName()))", systemImage: "tray.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                .help("Save to the evidence library (⌘S)")
                .buttonStyle(.borderedProminent)
            }
            .disabled(preview == nil)
            .padding(10)
        }
    }

    // MARK: Actions

    /// Code images keep their own background, so they are exported as PNG without extra decoration.
    private var pngOptions: ExportOptions {
        var o = ExportOptions.current
        o.format = .png
        o.shadow = false
        return o
    }

    private func applyPreset(theme t: String, frame f: CodeFrame, background b: CodeBackground) {
        themeName = t
        frame = f.rawValue
        background = b.rawValue
    }

    private func binding(for id: UUID) -> Binding<CodeStep> {
        Binding(get: { steps.first { $0.id == id } ?? CodeStep() },
                set: { new in if let i = steps.firstIndex(where: { $0.id == id }) { steps[i] = new } })
    }

    private func addStep() {
        let step = CodeStep(title: "", code: NSPasteboard.general.string(forType: .string) ?? "")
        steps.append(step)
        selectedStep = step.id
    }

    private func removeStep(_ id: UUID) {
        steps.removeAll { $0.id == id }
        if selectedStep == id { selectedStep = steps.first?.id }
    }

    private func moveStep(_ idx: Int, _ delta: Int) {
        let to = idx + delta
        guard steps.indices.contains(to) else { return }
        steps.swapAt(idx, to)
    }

    private func importTheme() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .propertyList, .xml] + [UTType(filenameExtension: "tmTheme")].compactMap { $0 }
        panel.message = "Choose a VS Code theme (.json), a TextMate theme (.tmTheme) or a SecShot theme."
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let t = try CodeThemeLibrary.importTheme(from: url)
            themes = CodeThemeLibrary.all()
            themeName = t.name
            status = "Imported theme “\(t.name)”."
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func exportTheme() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(theme.name).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try CodeThemeLibrary.encode(theme).write(to: url, options: .atomic) }
        catch { alertMessage = error.localizedDescription }
    }

    private func scheduleRender(immediately: Bool = false) {
        renderTask?.cancel()
        let input = input
        renderTask = Task {
            if !immediately { try? await Task.sleep(nanoseconds: 150_000_000) }
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) { () -> (CGImage?, CodeLanguage, [HeaderFinding], String) in
                switch input.mode {
                case .single:
                    guard !input.options.code.isEmpty, let out = CodeShotRenderer.render(input.options) else { return (nil, .auto, [], "") }
                    return (out.image, out.language, out.findings, "")
                case .compare:
                    guard !input.base.isEmpty || !input.change.isEmpty else { return (nil, .auto, [], "") }
                    let r = CodeShotRenderer.renderComparison(base: input.base, change: input.change,
                                                              baseLabel: input.baseLabel, changeLabel: input.changeLabel,
                                                              options: input.options, horizontal: input.compareHorizontal,
                                                              diff: input.showDiff, arrows: input.arrows)
                    return (r.image, .auto, r.findings, r.summary)
                case .timeline:
                    let steps = input.steps.map { (title: $0.title, code: $0.code) }
                    let img = CodeShotRenderer.renderTimeline(steps: steps, options: input.options,
                                                              horizontal: input.timelineHorizontal, arrows: input.arrows)
                    return (img, .auto, [], "Timeline with \(steps.filter { !$0.code.isEmpty }.count) steps.")
                }
            }.value
            guard !Task.isCancelled else { return }
            preview = result.0
            detected = result.1
            findings = result.2
            summary = result.3
            status = ""
        }
    }

    private func saveToLibrary() {
        guard let preview else { return }
        let notes: String
        switch mode {
        case .single:
            let firstLine = code.split(separator: "\n").first.map(String.init) ?? ""
            notes = "Code snippet (\(detected.label)): \(firstLine.prefix(120))"
        case .compare:
            notes = "Code comparison \(baseLabel) vs \(changeLabel). \(summary)"
        case .timeline:
            notes = "Code timeline: " + steps.enumerated().map { "\($0.offset + 1). \($0.element.title)" }.joined(separator: " → ")
        }
        if let item = store.addImage(preview, mode: "code", notes: notes) {
            store.selection = [item.id]
            status = "Saved as \(item.name). Open it in the library to redact, annotate or zoom."
        }
    }
}

// MARK: - Theme editor

private struct EditableTheme: Identifiable {
    var theme: CodeTheme
    var id: String { theme.name }
}

struct ThemeEditorView: View {
    @ViewState private var theme: CodeTheme
    @ViewState private var preview: CGImage?
    let onSave: (CodeTheme) -> Void
    let onCancel: () -> Void

    init(theme: CodeTheme, onSave: @escaping (CodeTheme) -> Void, onCancel: @escaping () -> Void) {
        var t = theme
        if !CodeThemeLibrary.isCustom(t.name) { t.name += " (Custom)" }
        _theme = ViewState(initialValue: t)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Theme name", text: $theme.name).textFieldStyle(.roundedBorder)
                    Toggle("Light theme", isOn: $theme.isLight)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(CodeTheme.roles, id: \.key) { role in
                                ColorPicker(role.label, selection: Binding(
                                    get: { Color(nsColor: theme[keyPath: role.path]) },
                                    set: { theme[keyPath: role.path] = NSColor($0).usingColorSpace(.sRGB) ?? NSColor($0) }
                                ))
                            }
                        }
                    }
                }
                .frame(width: 280)
                ZStack {
                    CheckerboardView().opacity(0.4)
                    if let preview {
                        Image(decorative: preview, scale: 2).resizable().aspectRatio(contentMode: .fit).padding(10)
                    }
                }
                .frame(minWidth: 460, minHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(16)
            Divider()
            HStack {
                Text("Saved to ~/Library/Application Support/SecShot/Themes").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save Theme") { onSave(theme) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(theme.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
        }
        .frame(width: 800, height: 560)
        .onAppear(perform: refresh)
        .onChange(of: theme) { refresh() }
    }

    private func refresh() {
        var o = CodeShotOptions(code: CodeSamples.themePreview)
        o.theme = theme
        o.background = .none
        o.shadow = false
        o.securityAnalysis = false
        o.fontSize = 12
        o.maxColumns = 60
        preview = CodeShotRenderer.render(o)?.image
    }
}
