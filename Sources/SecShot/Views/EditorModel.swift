// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import SwiftUI

@MainActor
final class EditorModel: ObservableObject {
    let store: LibraryStore
    let itemID: UUID
    let base: CGImage?

    @Published private(set) var annotations: [Annotation]
    @Published private(set) var crop: CGRect?
    @Published var notes: String { didSet { save(rerender: false) } }

    @Published var preview: CGImage?
    @Published var finalImage: CGImage?
    @Published var showFinal = false { didSet { if showFinal { refreshFinal() } } }

    @Published var tool: EditorTool = .rectangle { didSet { if tool != .select { selectedID = nil } } }
    @Published var color: Color = RGBAColor.red.color { didSet { applyStyle { $0.color = RGBAColor(color) } } }
    @Published var lineWidth: Double { didSet { applyStyle { $0.lineWidth = lineWidth } } }
    @Published var fontSize: Double { didSet { applyStyle { $0.fontSize = fontSize } } }

    // Defaults for new focus spotlights and magnifiers (also applied to the selected one).
    @Published var spotlightShape = "ellipse" { didSet { applyStyle(to: .spotlight) { $0.shape = spotlightShape } } }
    @Published var spotlightDim = 0.55 { didSet { applyStyle(to: .spotlight) { $0.dim = spotlightDim } } }
    @Published var spotlightBlur = 0.5 { didSet { applyStyle(to: .spotlight) { $0.blurAmount = spotlightBlur } } }
    @Published var spotlightOutline = false { didSet { applyStyle(to: .spotlight) { $0.filled = spotlightOutline } } }
    @Published var zoomFactor = 2.0 { didSet { applyStyle(to: .magnify) { $0.zoom = zoomFactor } } }
    @Published var smoothZoom = false { didSet { applyStyle(to: .magnify) { $0.smooth = smoothZoom } } }

    @Published var selectedID: UUID?
    @Published var draft: Annotation?
    @Published var draftCrop: CGRect?

    @Published var showTextPrompt = false
    @Published var pendingText = ""
    private var pendingTextPoint: CGPoint = .zero

    @Published var detecting = false
    @Published var detectionSummary: String?

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var syncingStyle = false
    private var lastStyleEdit = Date.distantPast
    private var renderGeneration = 0
    private var moveOrigin: Annotation?
    /// When dragging a magnifier: `true` moves the enlarged copy, `false` moves the source region.
    private var movingMagnifiedCopy = false

    private struct Snapshot {
        var annotations: [Annotation]
        var crop: CGRect?
    }

    init(item: CaptureItem, store: LibraryStore) {
        self.store = store
        itemID = item.id
        base = store.image(for: item)
        annotations = item.annotations
        crop = item.crop
        notes = item.notes
        let w = Double(base?.width ?? 1600)
        lineWidth = max(3, (w / 360).rounded())
        fontSize = max(18, (w / 55).rounded())
        rerender()
    }

    var imageSize: CGSize { CGSize(width: base?.width ?? 1, height: base?.height ?? 1) }
    var selected: Annotation? { annotations.first { $0.id == selectedID } }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: Render

    func rerender() {
        guard let base else { return }
        renderGeneration += 1
        let gen = renderGeneration
        let anns = annotations
        Task.detached(priority: .userInitiated) {
            let img = Renderer.render(base, annotations: anns, crop: nil)
            await MainActor.run {
                guard gen == self.renderGeneration else { return }
                self.preview = img
                if self.showFinal { self.refreshFinal() }
            }
        }
    }

    func refreshFinal() {
        guard let item = store.item(itemID) else { return }
        finalImage = ExportService.finalImage(for: item)
    }

    private func save(rerender doRender: Bool = true) {
        store.updateEdits(id: itemID, annotations: annotations, crop: crop, notes: notes)
        if doRender { rerender() }
    }

    // MARK: Undo

    private func pushUndo() {
        undoStack.append(Snapshot(annotations: annotations, crop: crop))
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let s = undoStack.popLast() else { return }
        redoStack.append(Snapshot(annotations: annotations, crop: crop))
        annotations = s.annotations
        crop = s.crop
        if selected == nil { selectedID = nil }
        save()
    }

    func redo() {
        guard let s = redoStack.popLast() else { return }
        undoStack.append(Snapshot(annotations: annotations, crop: crop))
        annotations = s.annotations
        crop = s.crop
        save()
    }

    // MARK: Editing

    func newAnnotation(kind: AnnotationKind, from s: CGPoint, to e: CGPoint) -> Annotation {
        var c = RGBAColor(color)
        if kind == .redact { c = .black }
        var a = Annotation(kind: kind, start: s, end: e, color: c, lineWidth: lineWidth, fontSize: fontSize)
        switch kind {
        case .spotlight:
            a.shape = spotlightShape
            a.dim = spotlightDim
            a.blurAmount = spotlightBlur
            a.filled = spotlightOutline
        case .magnify:
            a.zoom = zoomFactor
            a.smooth = smoothZoom
        default:
            break
        }
        return a
    }

    func add(_ a: Annotation) {
        var a = a
        if a.kind == .magnify { a.dest = defaultMagnifierOrigin(for: a) }
        pushUndo()
        annotations.append(a)
        save()
    }

    /// Places the enlarged copy next to the source: right, left, below or above, whichever fits.
    private func defaultMagnifierOrigin(for a: Annotation) -> CGPoint {
        let src = a.rect, gap: CGFloat = max(24, CGFloat(a.lineWidth) * 4)
        let size = CGSize(width: src.width * a.zoomFactor, height: src.height * a.zoomFactor)
        let candidates = [
            CGPoint(x: src.maxX + gap, y: src.midY - size.height / 2),
            CGPoint(x: src.minX - gap - size.width, y: src.midY - size.height / 2),
            CGPoint(x: src.midX - size.width / 2, y: src.maxY + gap),
            CGPoint(x: src.midX - size.width / 2, y: src.minY - gap - size.height),
        ]
        let bounds = CGRect(origin: .zero, size: imageSize)
        let fit = candidates.first { bounds.contains(CGRect(origin: $0, size: size)) }
        return fit ?? candidates[0]   // the renderer clamps it inside the image
    }

    /// Frame of a magnifier's enlarged copy as it will be rendered.
    func magnifierFrame(_ a: Annotation) -> CGRect {
        Renderer.magnifierFrame(a, imageSize: imageSize).rect
    }

    func addStep(at p: CGPoint) {
        let n = (annotations.filter { $0.kind == .step }.map(\.number).max() ?? 0) + 1
        var a = newAnnotation(kind: .step, from: p, to: p)
        a.number = n
        add(a)
    }

    func beginText(at p: CGPoint) {
        pendingTextPoint = p
        pendingText = ""
        showTextPrompt = true
    }

    func commitText() {
        let t = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var a = newAnnotation(kind: .text, from: pendingTextPoint, to: pendingTextPoint)
        a.text = t
        add(a)
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        pushUndo()
        annotations.removeAll { $0.id == id }
        selectedID = nil
        save()
    }

    func clearAll() {
        guard !annotations.isEmpty || crop != nil else { return }
        pushUndo()
        annotations.removeAll()
        crop = nil
        selectedID = nil
        save()
    }

    func setCrop(_ r: CGRect?) {
        pushUndo()
        crop = r.map { $0.intersection(CGRect(origin: .zero, size: imageSize)).integral }
        save()
    }

    func updateSelected(_ change: (inout Annotation) -> Void) {
        guard let i = annotations.firstIndex(where: { $0.id == selectedID }) else { return }
        pushUndo()
        change(&annotations[i])
        save()
    }

    func select(_ id: UUID?) {
        selectedID = id
        guard let a = selected else { return }
        syncingStyle = true
        if !a.kind.isRedaction { color = a.color.color }
        lineWidth = a.lineWidth
        fontSize = a.fontSize
        if a.kind == .spotlight {
            spotlightShape = a.spotlightShape
            spotlightDim = a.spotlightDim
            spotlightBlur = a.spotlightBlur
            spotlightOutline = a.filled
        }
        if a.kind == .magnify {
            zoomFactor = a.zoomFactor
            smoothZoom = a.smoothZoom
        }
        syncingStyle = false
    }

    /// Applies a style change only when the selected annotation is of the given kind.
    private func applyStyle(to kind: AnnotationKind, _ change: (inout Annotation) -> Void) {
        guard selected?.kind == kind else { return }
        applyStyle(change)
    }

    private func applyStyle(_ change: (inout Annotation) -> Void) {
        guard !syncingStyle, let i = annotations.firstIndex(where: { $0.id == selectedID }) else { return }
        // Group continuous changes (sliders) into a single undo step.
        if Date().timeIntervalSince(lastStyleEdit) > 0.8 { pushUndo() }
        lastStyleEdit = Date()
        change(&annotations[i])
        save()
    }

    func hitTest(_ p: CGPoint) -> UUID? {
        annotations.reversed().first { a in
            if a.kind == .magnify {
                return a.rect.insetBy(dx: -4, dy: -4).contains(p) || magnifierFrame(a).insetBy(dx: -4, dy: -4).contains(p)
            }
            return Renderer.bounds(a, imageSize: imageSize).insetBy(dx: -4, dy: -4).contains(p)
        }?.id
    }

    func beginMove(at p: CGPoint) {
        guard var a = selected else { return }
        pushUndo()
        movingMagnifiedCopy = false
        if a.kind == .magnify {
            // Freeze the rendered position so dragging starts from what the user sees.
            a.dest = magnifierFrame(a).origin
            movingMagnifiedCopy = magnifierFrame(a).contains(p) && !a.rect.contains(p)
        }
        moveOrigin = a
    }

    func move(by d: CGSize) {
        guard var a = moveOrigin, let i = annotations.firstIndex(where: { $0.id == a.id }) else { return }
        if a.kind == .magnify && movingMagnifiedCopy {
            let o = a.dest ?? .zero
            a.dest = CGPoint(x: o.x + d.width, y: o.y + d.height)
        } else if a.kind == .magnify {
            // Moving the source keeps the enlarged copy where it is.
            a.start.x += d.width; a.start.y += d.height
            a.end.x += d.width; a.end.y += d.height
        } else {
            a.offset(by: d)
        }
        annotations[i] = a
    }

    func endMove() {
        guard moveOrigin != nil else { return }
        moveOrigin = nil
        save()
    }

    // MARK: Sensitive data detection

    func detectSensitive() {
        guard let base, !detecting else { return }
        detecting = true
        detectionSummary = nil
        let disabled = Set((UserDefaults.standard.string(forKey: Prefs.disabledDetectors) ?? "")
            .split(separator: "|").map(String.init))
        let kind = AnnotationKind(rawValue: UserDefaults.standard.string(forKey: Prefs.defaultRedaction) ?? "") ?? .pixelate
        Task {
            let findings = await SensitiveDetector.detect(in: base, disabled: disabled)
            detecting = false
            guard !findings.isEmpty else {
                detectionSummary = "No sensitive data detected."
                return
            }
            pushUndo()
            for f in findings {
                var a = Annotation(kind: kind, start: f.rect.origin,
                                   end: CGPoint(x: f.rect.maxX, y: f.rect.maxY),
                                   color: .black, lineWidth: lineWidth, fontSize: fontSize)
                a.text = f.category
                annotations.append(a)
            }
            save()
            let byCat = Dictionary(grouping: findings, by: \.category).map { "\($0.key): \($0.value.count)" }.sorted()
            detectionSummary = "Redacted \(findings.count) items — " + byCat.joined(separator: ", ") + ". Review the result; you can undo (⌘Z)."
        }
    }

    // MARK: Output

    func saveAsNewCapture() {
        guard let item = store.item(itemID), let img = store.renderedImage(for: item) else { return }
        if let new = store.addImage(img, mode: "derived", notes: "Derived from \(item.name). " + item.notes) {
            store.selection = [new.id]
        }
    }
}
