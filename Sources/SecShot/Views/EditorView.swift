// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import SwiftUI

struct EditorView: View {
    @StateObject private var vm: EditorModel

    init(item: CaptureItem) {
        _vm = StateObject(wrappedValue: EditorModel(item: item, store: .shared))
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(vm: vm)
            Divider()
            HStack(spacing: 0) {
                Group {
                    if vm.showFinal {
                        FinalPreview(vm: vm)
                    } else {
                        EditorCanvas(vm: vm)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                EditorInspector(vm: vm).frame(width: 290)
            }
        }
        .alert("Add Text", isPresented: $vm.showTextPrompt) {
            TextField("Text", text: $vm.pendingText)
            Button("Add") { vm.commitText() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Toolbar

struct EditorToolbar: View {
    @ObservedObject var vm: EditorModel
    private let swatches: [Color] = [RGBAColor.red.color, .orange, .yellow, .green, .blue, .purple, .black, .white]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(EditorTool.allCases) { t in
                Button { vm.tool = t } label: {
                    Image(systemName: t.symbol)
                        .frame(width: 26, height: 22)
                        .foregroundStyle(t.kind?.isRedaction == true ? Color.orange : Color.primary)
                }
                .buttonStyle(.borderless)
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 6).fill(vm.tool == t ? Color.accentColor.opacity(0.28) : .clear))
                .help(t.label)
                if t == .select || t == .step || t == .magnify || t == .redact {
                    Divider().frame(height: 20).padding(.horizontal, 2)
                }
            }

            ColorPicker("", selection: $vm.color, supportsOpacity: false).labelsHidden().frame(width: 36)
            HStack(spacing: 2) {
                ForEach(swatches.indices, id: \.self) { i in
                    Circle().fill(swatches[i])
                        .overlay(Circle().stroke(Color.primary.opacity(0.25)))
                        .frame(width: 13, height: 13)
                        .onTapGesture { vm.color = swatches[i] }
                }
            }
            Divider().frame(height: 20).padding(.horizontal, 2)
            Image(systemName: "lineweight").foregroundStyle(.secondary).help("Line width")
            Slider(value: $vm.lineWidth, in: 1...40).frame(width: 70)
            Image(systemName: "textformat.size").foregroundStyle(.secondary).help("Text / step size")
            Slider(value: $vm.fontSize, in: 10...120).frame(width: 70)

            Spacer(minLength: 8)

            Button(action: vm.undo) { Image(systemName: "arrow.uturn.backward") }
                .keyboardShortcut("z", modifiers: .command).disabled(!vm.canUndo).help("Undo (⌘Z)")
            Button(action: vm.redo) { Image(systemName: "arrow.uturn.forward") }
                .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!vm.canRedo).help("Redo (⇧⌘Z)")
            Button(action: vm.deleteSelected) { Image(systemName: "trash") }
                .disabled(vm.selectedID == nil).help("Delete selected annotation (⌫)")
            Toggle(isOn: $vm.showFinal) { Label("Final View", systemImage: "eye") }
                .toggleStyle(.button)
                .help("Shows the image as it will be exported (crop + shadow)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

// MARK: - Canvas

struct EditorCanvas: View {
    @ObservedObject var vm: EditorModel
    @ViewState private var gestureActive = false
    @ViewState private var moving = false
    @FocusState private var focused: Bool

    private struct Layout {
        var scale: CGFloat
        var origin: CGPoint
        var size: CGSize

        func toImage(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - origin.x) / scale, y: (p.y - origin.y) / scale) }
        func toView(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale) }
        func toView(_ r: CGRect) -> CGRect {
            CGRect(x: origin.x + r.minX * scale, y: origin.y + r.minY * scale, width: r.width * scale, height: r.height * scale)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let layout = makeLayout(geo.size)
            ZStack(alignment: .topLeading) {
                Color(nsColor: .underPageBackgroundColor)
                if let img = vm.preview {
                    Image(decorative: img, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: layout.size.width, height: layout.size.height)
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                        .offset(x: layout.origin.x, y: layout.origin.y)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Canvas { ctx, _ in drawOverlays(ctx, layout) }
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(layout))
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onKeyPress(.delete) { vm.deleteSelected(); return .handled }
            .onKeyPress(.deleteForward) { vm.deleteSelected(); return .handled }
            .onKeyPress(.escape) { vm.select(nil); vm.draftCrop = nil; return .handled }
            .onKeyPress(characters: .letters) { press in
                switch press.characters.lowercased() {
                case "v": vm.tool = .select
                case "r": vm.tool = .rectangle
                case "a": vm.tool = .arrow
                case "t": vm.tool = .text
                case "p": vm.tool = .pixelate
                case "b": vm.tool = .blur
                case "x": vm.tool = .redact
                case "c": vm.tool = .crop
                case "h": vm.tool = .highlight
                case "n": vm.tool = .step
                case "s": vm.tool = .spotlight
                case "z": vm.tool = .magnify
                default: return .ignored
                }
                return .handled
            }
            .onAppear { focused = true }
        }
    }

    private func makeLayout(_ size: CGSize) -> Layout {
        let iw = vm.imageSize.width, ih = vm.imageSize.height
        let pad: CGFloat = 24
        let scale = max(0.01, min((size.width - pad * 2) / iw, (size.height - pad * 2) / ih, 1))
        let s = CGSize(width: iw * scale, height: ih * scale)
        return Layout(scale: scale, origin: CGPoint(x: (size.width - s.width) / 2, y: (size.height - s.height) / 2), size: s)
    }

    private func dragGesture(_ layout: Layout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                focused = true
                let s = layout.toImage(v.startLocation), p = layout.toImage(v.location)
                let first = !gestureActive
                gestureActive = true
                switch vm.tool {
                case .select:
                    if first {
                        let hit = vm.hitTest(s)
                        vm.select(hit)
                        moving = hit != nil
                        if moving { vm.beginMove(at: s) }
                    }
                    if moving { vm.move(by: CGSize(width: p.x - s.x, height: p.y - s.y)) }
                case .crop:
                    vm.draftCrop = CGRect(x: min(s.x, p.x), y: min(s.y, p.y), width: abs(p.x - s.x), height: abs(p.y - s.y))
                case .text, .step:
                    break
                default:
                    if let kind = vm.tool.kind { vm.draft = vm.newAnnotation(kind: kind, from: s, to: p) }
                }
            }
            .onEnded { v in
                gestureActive = false
                let p = layout.toImage(v.location)
                switch vm.tool {
                case .select:
                    if moving { vm.endMove() }
                    moving = false
                case .crop:
                    if let r = vm.draftCrop, r.width > 10, r.height > 10 { vm.setCrop(r) }
                    vm.draftCrop = nil
                case .text:
                    if let hit = vm.hitTest(p), vm.annotations.first(where: { $0.id == hit })?.kind == .text {
                        vm.tool = .select
                        vm.select(hit)
                    } else {
                        vm.beginText(at: p)
                    }
                case .step:
                    vm.addStep(at: p)
                default:
                    if let d = vm.draft {
                        let len = hypot(d.end.x - d.start.x, d.end.y - d.start.y)
                        if len > 4 { vm.add(d) }
                    }
                    vm.draft = nil
                }
            }
    }

    private func drawOverlays(_ ctx: GraphicsContext, _ l: Layout) {
        let imageRect = CGRect(origin: l.origin, size: l.size)

        if let c = vm.draftCrop ?? vm.crop {
            var p = Path()
            p.addRect(imageRect)
            p.addRect(l.toView(c))
            ctx.fill(p, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
            ctx.stroke(Path(l.toView(c)), with: .color(.white), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }

        if let d = vm.draft {
            let r = l.toView(d.rect)
            let color = d.color.color
            let lw = max(1, d.lineWidth * l.scale)
            switch d.kind {
            case .rectangle: ctx.stroke(Path(r), with: .color(color), lineWidth: lw)
            case .ellipse: ctx.stroke(Path(ellipseIn: r), with: .color(color), lineWidth: lw)
            case .line, .arrow:
                var p = Path()
                p.move(to: l.toView(d.start))
                p.addLine(to: l.toView(d.end))
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: lw, lineCap: .round))
            case .highlight: ctx.fill(Path(r), with: .color(color.opacity(0.4)))
            case .pixelate, .blur, .redact:
                ctx.fill(Path(r), with: .color(d.kind == .redact ? .black.opacity(0.85) : .gray.opacity(0.6)))
                ctx.stroke(Path(r), with: .color(.orange), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                ctx.draw(Text(d.kind.label).font(.caption.bold()).foregroundColor(.white), at: CGPoint(x: r.midX, y: r.midY))
            case .spotlight:
                let shape = d.spotlightShape == "rectangle"
                    ? Path(roundedRect: r, cornerRadius: min(r.width, r.height) * 0.08)
                    : Path(ellipseIn: r)
                var dimmed = Path(imageRect)
                dimmed.addPath(shape)
                ctx.fill(dimmed, with: .color(.black.opacity(d.spotlightDim)), style: FillStyle(eoFill: true))
                ctx.stroke(shape, with: .color(.white), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            case .magnify:
                ctx.stroke(Path(r), with: .color(color), style: StrokeStyle(lineWidth: max(1.5, lw * 0.6), dash: [6, 4]))
                let frame = l.toView(vm.magnifierFrame(d))
                ctx.stroke(Path(frame), with: .color(color.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                ctx.draw(Text(String(format: "%.1f×", d.zoomFactor)).font(.caption.bold()).foregroundColor(color),
                         at: CGPoint(x: frame.midX, y: frame.midY))
            default: break
            }
        }

        if let sel = vm.selected {
            let style = StrokeStyle(lineWidth: 1.5, dash: [5, 3])
            if sel.kind == .magnify {
                // Two handles: the source region and the enlarged copy can be dragged separately.
                ctx.stroke(Path(l.toView(sel.rect).insetBy(dx: -4, dy: -4)), with: .color(.accentColor), style: style)
                ctx.stroke(Path(l.toView(vm.magnifierFrame(sel)).insetBy(dx: -4, dy: -4)), with: .color(.accentColor), style: style)
            } else {
                let r = l.toView(Renderer.bounds(sel, imageSize: vm.imageSize)).insetBy(dx: -4, dy: -4)
                ctx.stroke(Path(r), with: .color(.accentColor), style: style)
            }
        }
    }
}

// MARK: - Final preview

struct FinalPreview: View {
    @ObservedObject var vm: EditorModel
    @AppStorage(Prefs.shadow) private var shadow = true
    @AppStorage(Prefs.cornerRadius) private var corner = 10.0
    @AppStorage(Prefs.transparentBG) private var transparent = true

    var body: some View {
        ZStack {
            CheckerboardView()
            if let img = vm.finalImage {
                Image(decorative: img, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fit).padding(24)
            }
        }
        .onAppear { vm.refreshFinal() }
        .onChange(of: shadow) { vm.refreshFinal() }
        .onChange(of: corner) { vm.refreshFinal() }
        .onChange(of: transparent) { vm.refreshFinal() }
    }
}

struct CheckerboardView: View {
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 12
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.92)))
            for y in stride(from: 0, to: size.height, by: s) {
                for x in stride(from: 0, to: size.width, by: s) where (Int(x / s) + Int(y / s)) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(Color(white: 0.84)))
                }
            }
        }
    }
}

// MARK: - Inspector

struct EditorInspector: View {
    @ObservedObject var vm: EditorModel
    @EnvironmentObject var store: LibraryStore
    @AppStorage(Prefs.shadow) private var shadow = true
    @AppStorage(Prefs.defaultRedaction) private var defaultRedaction = AnnotationKind.pixelate.rawValue
    @AppStorage(Prefs.disabledDetectors) private var disabledDetectors = ""
    @ViewState private var nameDraft = ""

    private var item: CaptureItem? { store.item(vm.itemID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let item {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Name", text: $nameDraft)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .onSubmit { store.rename(item.id, to: nameDraft); nameDraft = store.item(item.id)?.name ?? nameDraft }
                            info("Date", Fmt.dateTime.string(from: item.createdAt))
                            info("Type", item.modeLabel)
                            info("Size", "\(item.pixelWidth) × \(item.pixelHeight) px")
                            Text("SHA-256 (original)").font(.caption).foregroundStyle(.secondary)
                            Text(item.sha256).font(.system(size: 9.5, design: .monospaced)).textSelection(.enabled).lineLimit(3)
                        }
                    } label: { Label("Evidence", systemImage: "doc.text.magnifyingglass") }
                    .onAppear { nameDraft = item.name }
                }

                GroupBox {
                    TextEditor(text: $vm.notes)
                        .font(.callout)
                        .frame(height: 80)
                        .scrollContentBackground(.hidden)
                } label: { Label("Report Notes", systemImage: "note.text") }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: vm.detectSensitive) {
                            HStack {
                                if vm.detecting { ProgressView().controlSize(.small) } else { Image(systemName: "eye.trianglebadge.exclamationmark") }
                                Text("Detect & Redact Sensitive Data")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(vm.detecting)

                        Menu("Categories to Detect") {
                            ForEach(SensitiveDetector.categories, id: \.0) { cat, _ in
                                Toggle(cat, isOn: categoryBinding(cat))
                            }
                        }
                        .controlSize(.small)

                        Picker("Style", selection: $defaultRedaction) {
                            Text("Pixelate").tag(AnnotationKind.pixelate.rawValue)
                            Text("Hardened blur").tag(AnnotationKind.blur.rawValue)
                            Text("Solid redaction").tag(AnnotationKind.redact.rawValue)
                        }
                        .controlSize(.small)

                        if let s = vm.detectionSummary {
                            Text(s).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Use solid redaction for passwords, tokens and keys: it is irreversible. The unedited original stays only in the local library; exports are always flattened and metadata-free.")
                            .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                } label: { Label("Security", systemImage: "lock.shield") }

                if vm.tool == .spotlight || vm.selected?.kind == .spotlight {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Shape", selection: $vm.spotlightShape) {
                                Label("Ellipse", systemImage: "circle").tag("ellipse")
                                Label("Rectangle", systemImage: "rectangle").tag("rectangle")
                            }
                            .pickerStyle(.segmented)
                            HStack {
                                Text("Darken").frame(width: 50, alignment: .leading)
                                Slider(value: $vm.spotlightDim, in: 0...0.9)
                            }
                            HStack {
                                Text("Blur").frame(width: 50, alignment: .leading)
                                Slider(value: $vm.spotlightBlur, in: 0...1)
                            }
                            Toggle("Outline in the current color", isOn: $vm.spotlightOutline)
                            Text("Everything outside the shape is darkened and blurred to draw attention to it. Redactions stay intact.")
                                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    } label: { Label("Focus Spotlight", systemImage: "circle.dashed.inset.filled") }
                }

                if vm.tool == .magnify || vm.selected?.kind == .magnify {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Zoom")
                                Slider(value: $vm.zoomFactor, in: 1.5...6, step: 0.5)
                                Text(String(format: "%.1f×", vm.zoomFactor)).monospacedDigit().frame(width: 38)
                            }
                            Picker("Scaling", selection: $vm.smoothZoom) {
                                Text("Pixel-perfect").tag(false)
                                Text("Smooth").tag(true)
                            }
                            .pickerStyle(.segmented)
                            Text("Pixel-perfect enlarges every pixel exactly, so screenshot text stays sharp. Smooth uses Lanczos resampling, better for photos. Drag the source or the enlarged copy separately with the Select tool.")
                                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    } label: { Label("Zoom", systemImage: "plus.magnifyingglass") }
                }

                if let sel = vm.selected {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(sel.kind.label).font(.headline)
                            if sel.kind == .text {
                                TextField("Text", text: Binding(get: { sel.text }, set: { t in vm.updateSelected { $0.text = t } }))
                                    .textFieldStyle(.roundedBorder)
                                Toggle("Solid background (callout)", isOn: Binding(get: { sel.filled }, set: { f in vm.updateSelected { $0.filled = f } }))
                            }
                            if sel.kind == .step {
                                Stepper("Number: \(sel.number)", value: Binding(get: { sel.number }, set: { n in vm.updateSelected { $0.number = max(1, n) } }))
                            }
                            if sel.kind.isRedaction {
                                Picker("Type", selection: Binding(get: { sel.kind }, set: { k in vm.updateSelected { $0.kind = k } })) {
                                    Text("Pixelate").tag(AnnotationKind.pixelate)
                                    Text("Hardened blur").tag(AnnotationKind.blur)
                                    Text("Solid redaction").tag(AnnotationKind.redact)
                                }
                                if !sel.text.isEmpty { Text("Detected: \(sel.text)").font(.caption).foregroundStyle(.secondary) }
                            }
                            Button(role: .destructive, action: vm.deleteSelected) { Label("Delete", systemImage: "trash") }
                        }
                    } label: { Label("Selection", systemImage: "cursorarrow.click") }
                }

                if vm.crop != nil {
                    Button { vm.setCrop(nil) } label: { Label("Remove Crop", systemImage: "crop") }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("macOS-style shadow", isOn: $shadow)
                            .onChange(of: shadow) { if vm.showFinal { vm.refreshFinal() } }
                        if let item {
                            HStack {
                                Button { ExportService.copy(item) } label: { Label("Copy", systemImage: "doc.on.doc") }
                                    .keyboardShortcut("c", modifiers: [.command, .shift])
                                Button { ExportService.export(item) } label: { Label("Export…", systemImage: "square.and.arrow.up") }
                                    .keyboardShortcut("e", modifiers: .command)
                            }
                            Button { vm.saveAsNewCapture() } label: { Label("Save as New Evidence", systemImage: "plus.square.on.square") }
                            Button { store.revealInFinder([item.id]) } label: { Label("Show Original in Finder", systemImage: "folder") }
                            Button(role: .destructive) { vm.clearAll() } label: { Label("Remove All Edits", systemImage: "eraser") }
                                .disabled(vm.annotations.isEmpty && vm.crop == nil)
                        }
                    }
                } label: { Label("Output", systemImage: "square.and.arrow.up.on.square") }

                Text("Shortcuts: V select · R rectangle · A arrow · T text · H highlight · N step · S spotlight · Z zoom · P pixelate · B blur · X redact · C crop · ⌫ delete")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(12)
        }
    }

    private func info(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v) }.font(.caption)
    }

    private func categoryBinding(_ cat: String) -> Binding<Bool> {
        Binding(
            get: { !disabledDetectors.split(separator: "|").map(String.init).contains(cat) },
            set: { on in
                var set = Set(disabledDetectors.split(separator: "|").map(String.init))
                if on { set.remove(cat) } else { set.insert(cat) }
                disabledDetectors = set.sorted().joined(separator: "|")
            }
        )
    }
}
