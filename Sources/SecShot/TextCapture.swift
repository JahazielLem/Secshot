// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import AppKit
import ImageIO
import UniformTypeIdentifiers

struct TextCaptureEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let image: CGImage
    let fragments: [OCRFragment]
    let source: String

    var preview: String {
        fragments.first.map { String($0.text.prefix(60)) } ?? "No text"
    }
}

/// Text capture (OCR): select an area, recognize it on-device and copy it as plain text, Markdown or CSV.
/// Captured images are not written to disk; recent captures are kept in memory only.
@MainActor
final class TextCaptureStore: ObservableObject {
    static let shared = TextCaptureStore()

    @Published private(set) var entries: [TextCaptureEntry] = []
    @Published var selectedID: UUID? { didSet { regenerate() } }
    @Published var format: TextOutputFormat {
        didSet {
            UserDefaults.standard.set(format.rawValue, forKey: Prefs.textFormat)
            regenerate()
        }
    }
    /// Text shown (and editable) in the Text section.
    @Published var text = ""
    @Published var summary = ""
    @Published private(set) var busy = false

    private var isCapturing = false

    init() {
        format = TextOutputFormat(rawValue: UserDefaults.standard.string(forKey: Prefs.textFormat) ?? "") ?? .markdown
    }

    var selected: TextCaptureEntry? { entries.first { $0.id == selectedID } ?? entries.first }

    private var languages: [String] {
        switch UserDefaults.standard.string(forKey: Prefs.textLanguage) ?? "auto" {
        case "en": return ["en-US"]
        case "es": return ["es-ES"]
        case "en-es": return ["en-US", "es-ES"]
        case "pt": return ["pt-BR"]
        case "fr": return ["fr-FR"]
        case "de": return ["de-DE"]
        default: return []
        }
    }

    // MARK: Capture

    /// Global ⌘⇧2: select an area, recognize it and copy the result in the default format.
    func captureArea() {
        guard !isCapturing, ScreenPermission.ensure() else { return }
        isCapturing = true
        CaptureBar.shared.suspend()
        let hide = UserDefaults.standard.bool(forKey: Prefs.hideDuringCapture) && NSApp.isActive
        if hide { NSApp.hide(nil) }

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("secshot-ocr-\(UUID().uuidString).png")
        DispatchQueue.main.asyncAfter(deadline: .now() + (hide ? 0.3 : 0.05)) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-s", "-x", "-o", "-t", "png", tmp.path]
            process.terminationHandler = { _ in
                Task { @MainActor in TextCaptureStore.shared.finishCapture(tmp: tmp, unhide: hide) }
            }
            do { try process.run() } catch { self.finishCapture(tmp: tmp, unhide: hide) }
        }
    }

    /// Decodes an image fully into memory. `CGImageSourceCreateWithURL` decodes lazily, so an image
    /// whose file is deleted afterwards (like the temporary capture) would reach OCR empty.
    static func loadImage(_ url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url),
              let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    private func finishCapture(tmp: URL, unhide: Bool) {
        isCapturing = false
        CaptureBar.shared.resume()
        // Decode into memory first, then delete: the captured image is never kept on disk.
        let captured = Self.loadImage(tmp)
        try? FileManager.default.removeItem(at: tmp)
        guard let image = captured else {
            if unhide { NSApp.unhideWithoutActivation() }
            return   // cancelled with Esc
        }
        if unhide { NSApp.unhideWithoutActivation() }
        Task { await recognize(image, source: "Screen area", copy: true) }
    }

    // MARK: Recognition

    func recognize(_ image: CGImage, source: String, copy: Bool) async {
        busy = true
        let fragments = await TextRecognizer.recognize(image, languages: languages,
                                                       languageCorrection: UserDefaults.standard.bool(forKey: Prefs.textLanguageCorrection))
        busy = false
        guard !fragments.isEmpty else {
            ToastHUD.show("No text found", subtitle: "Nothing was copied or saved. Try a larger or sharper area.",
                          symbol: "text.badge.xmark")
            return
        }
        let entry = TextCaptureEntry(image: image, fragments: fragments, source: source)
        entries.insert(entry, at: 0)
        if entries.count > 20 { entries.removeLast(entries.count - 20) }
        selectedID = entry.id

        guard copy else { return }
        if UserDefaults.standard.bool(forKey: Prefs.copyText) {
            copyText(text)
            if UserDefaults.standard.bool(forKey: Prefs.textShowToast) {
                ToastHUD.show("Copied as \(format.label)", subtitle: summary)
            }
        } else if UserDefaults.standard.bool(forKey: Prefs.textShowToast) {
            ToastHUD.show("Text recognized", subtitle: "\(summary) · open Text (⌘6) to copy it", symbol: "text.viewfinder")
        }
        if UserDefaults.standard.bool(forKey: Prefs.textOpenWindow) {
            WindowManager.shared.showSection(.text)
        }
    }

    func regenerate() {
        guard let entry = selected else { text = ""; summary = ""; return }
        let out = TextLayoutFormatter.format(entry.fragments, as: format)
        text = out.text
        summary = out.summary
    }

    func copyText(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }

    func copyCurrent() {
        guard !text.isEmpty else { return }
        copyText(text)
        ToastHUD.show("Copied as \(format.label)", subtitle: summary)
    }

    // MARK: Other sources

    func importImageWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.prompt = "Recognize Text"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        recognizeFile(url)
    }

    func recognizeFile(_ url: URL) {
        guard let image = Self.loadImage(url) else { return }
        Task { await recognize(image, source: url.lastPathComponent, copy: false) }
    }

    /// Recognizes an image from the clipboard (e.g. a screenshot copied with ⌃⌘⇧4).
    @discardableResult
    func recognizeClipboardImage() -> Bool {
        guard let image = NSImage(pasteboard: .general),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        Task { await recognize(cg, source: "Clipboard", copy: false) }
        return true
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        if selectedID == id { selectedID = entries.first?.id }
    }

    func clear() {
        entries.removeAll()
        selectedID = nil
    }
}
