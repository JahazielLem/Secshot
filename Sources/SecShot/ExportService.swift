// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case png, jpeg

    var id: String { rawValue }
    var ext: String { self == .png ? "png" : "jpg" }
    var utType: UTType { self == .png ? .png : .jpeg }
    var label: String { self == .png ? "PNG" : "JPEG" }
}

struct ExportOptions {
    var format: ExportFormat
    var shadow: Bool
    var cornerRadius: Double
    var transparent: Bool
    var retina: Bool
    var quality: Double = 0.92

    static var current: ExportOptions {
        let d = UserDefaults.standard
        return ExportOptions(format: ExportFormat(rawValue: d.string(forKey: Prefs.exportFormat) ?? "png") ?? .png,
                             shadow: d.bool(forKey: Prefs.shadow),
                             cornerRadius: d.double(forKey: Prefs.cornerRadius),
                             transparent: d.bool(forKey: Prefs.transparentBG),
                             retina: d.bool(forKey: Prefs.retinaDPI))
    }
}

@MainActor
enum ExportService {
    /// Final image: annotations + crop + decoration (shadow) according to the options.
    static func finalImage(for item: CaptureItem, options: ExportOptions = .current) -> CGImage? {
        guard let flat = LibraryStore.shared.renderedImage(for: item) else { return nil }
        return decorate(flat, options: options)
    }

    static func decorate(_ img: CGImage, options: ExportOptions) -> CGImage {
        let bg: CGColor? = (options.transparent && options.format == .png) ? nil : .white
        return Renderer.decorate(img, shadow: options.shadow,
                                 cornerRadius: options.shadow ? options.cornerRadius : 0, background: bg)
    }

    /// Encodes the image without EXIF/GPS/author metadata. DPI is only included when requested.
    nonisolated static func encode(_ img: CGImage, format: ExportFormat, dpi: Int?, quality: Double = 0.92) -> Data? {
        var image = img
        if format == .jpeg, let flat = Renderer.flatten(img, background: .white) { image = flat }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else { return nil }
        var props: [CFString: Any] = [:]
        if format == .jpeg { props[kCGImageDestinationLossyCompressionQuality] = quality }
        if let dpi {
            props[kCGImagePropertyDPIWidth] = dpi
            props[kCGImagePropertyDPIHeight] = dpi
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    static func encode(_ img: CGImage, options: ExportOptions) -> Data? {
        encode(img, format: options.format, dpi: options.retina ? 144 : nil, quality: options.quality)
    }

    // MARK: - Clipboard

    static func copyImage(_ img: CGImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let png = encode(img, format: .png, dpi: nil) { pb.setData(png, forType: .png) }
        let ns = NSImage(cgImage: img, size: NSSize(width: img.width / 2, height: img.height / 2))
        if let tiff = ns.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
    }

    static func copy(_ item: CaptureItem) {
        if let img = finalImage(for: item) { copyImage(img) }
    }

    // MARK: - Single export

    static func export(_ item: CaptureItem) {
        let options = ExportOptions.current
        guard let img = finalImage(for: item, options: options) else { return }
        save(img, suggestedName: item.name, options: options)
    }

    static func save(_ img: CGImage, suggestedName: String, options: ExportOptions = .current) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [options.format.utType]
        panel.nameFieldStringValue = "\(suggestedName).\(options.format.ext)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url,
              let data = encode(img, options: options) else { return }
        do { try data.write(to: url, options: .atomic) } catch { NSAlert(error: error).runModal() }
    }

    /// Temporary file used to drag evidence into Word, Pages, Dradis, etc.
    static func dragFile(for item: CaptureItem) -> URL? {
        let options = ExportOptions.current
        guard let img = finalImage(for: item, options: options), let data = encode(img, options: options) else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SecShot-drag", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(item.fileName.replacingOccurrences(of: ".png", with: "")).\(options.format.ext)")
        try? data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Batch export with manifest (chain of custody)

    static func exportBatch(_ items: [CaptureItem]) {
        guard !items.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "\(items.count) evidence files will be exported, plus a SHA-256 manifest and a Markdown report"
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let options = ExportOptions.current
        let ordered = items.sorted { $0.createdAt < $1.createdAt }
        var csv = "name,file,captured_at,mode,sha256_original,sha256_exported,notes\n"
        var md = "# Evidence\n\nGenerated by SecShot on \(Fmt.dateTime.string(from: Date())).\n\n"

        func csvField(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }

        for item in ordered {
            guard let img = finalImage(for: item, options: options), let data = encode(img, options: options) else { continue }
            let base = item.fileName.replacingOccurrences(of: ".png", with: "")
            var fileName = "\(base).\(options.format.ext)"
            var n = 2
            while FileManager.default.fileExists(atPath: folder.appendingPathComponent(fileName).path) {
                fileName = "\(base)_\(n).\(options.format.ext)"; n += 1
            }
            let url = folder.appendingPathComponent(fileName)
            do { try data.write(to: url, options: .atomic) } catch { continue }
            let hash = Hashing.sha256(data)
            let date = Fmt.dateTime.string(from: item.createdAt)
            csv += [item.name, fileName, date, item.modeLabel, item.sha256, hash, item.notes].map(csvField).joined(separator: ",") + "\n"
            md += "## \(item.name)\n\n"
            md += "- **Captured at:** \(date)\n- **Type:** \(item.modeLabel)\n- **Original SHA-256:** `\(item.sha256)`\n- **Exported SHA-256:** `\(hash)`\n\n"
            if !item.notes.isEmpty { md += "\(item.notes)\n\n" }
            md += "![\(item.name)](\(fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName))\n\n"
        }
        try? csv.write(to: folder.appendingPathComponent("evidence-manifest.csv"), atomically: true, encoding: .utf8)
        try? md.write(to: folder.appendingPathComponent("evidence-report.md"), atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}
