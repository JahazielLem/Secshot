// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import AppKit
import ImageIO
import UniformTypeIdentifiers

final class ImageBox {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

/// Capture history: persistence, evidence naming and image access.
@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var items: [CaptureItem] = []
    @Published var selection: Set<UUID> = []

    // State shared with the comparison / timeline window.
    @Published var compareBaseID: UUID?
    @Published var compareChangeID: UUID?
    @Published var timelineIDs: [UUID] = []

    // Comparison workspace for external images (not taken with SecShot).
    @Published var workspaceBaseID: UUID?
    @Published var workspaceChangeID: UUID?
    @Published var workspaceTimelineIDs: [UUID] = []

    /// Incremented on every edit so open comparisons can re-render.
    @Published private(set) var editRevision = 0

    /// Evidence shown in the library (excludes workspace images).
    var libraryItems: [CaptureItem] { items.filter { !$0.isWorkspace } }
    /// External images added to the comparison workspace.
    var workspaceItems: [CaptureItem] { items.filter(\.isWorkspace).sorted { $0.createdAt < $1.createdAt } }

    let directory: URL
    private var counters: [String: Int] = [:]
    private let imageCache = NSCache<NSString, ImageBox>()
    private let thumbCache = NSCache<NSString, NSImage>()

    private struct Index: Codable {
        var items: [CaptureItem]
        var counters: [String: Int]
    }

    init() {
        let fm = FileManager.default
        let pictures = fm.urls(for: .picturesDirectory, in: .userDomainMask).first ?? fm.homeDirectoryForCurrentUser
        directory = pictures.appendingPathComponent("SecShot", isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        imageCache.countLimit = 12
        load()
    }

    private var indexURL: URL { directory.appendingPathComponent("library.json") }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let index = try? decoder.decode(Index.self, from: data) else {
            // Never overwrite an index we cannot read (e.g. written by a newer version):
            // keep a copy next to it before this session saves a new one.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = directory.appendingPathComponent("library.unreadable-\(stamp).json")
            try? FileManager.default.copyItem(at: indexURL, to: backup)
            NSLog("SecShot: could not read library.json; a copy was saved to \(backup.lastPathComponent)")
            return
        }
        items = index.items
            .filter { FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
            .sorted { $0.createdAt > $1.createdAt }
        counters = index.counters
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(Index(items: items, counters: counters)) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    // MARK: - Queries

    func item(_ id: UUID?) -> CaptureItem? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }

    func fileURL(for item: CaptureItem) -> URL {
        directory.appendingPathComponent(item.fileName)
    }

    func image(for item: CaptureItem) -> CGImage? {
        let key = item.id.uuidString as NSString
        if let cached = imageCache.object(forKey: key) { return cached.image }
        guard let src = CGImageSourceCreateWithURL(fileURL(for: item) as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        imageCache.setObject(ImageBox(img), forKey: key)
        return img
    }

    /// Image with annotations and crop applied (no decoration).
    func renderedImage(for item: CaptureItem) -> CGImage? {
        guard let base = image(for: item) else { return nil }
        return Renderer.render(base, annotations: item.annotations, crop: item.crop)
    }

    func thumbnail(for item: CaptureItem, maxPixel: Int = 360) -> NSImage? {
        let key = "\(item.id.uuidString)-\(maxPixel)" as NSString
        if let t = thumbCache.object(forKey: key) { return t }
        guard let src = CGImageSourceCreateWithURL(fileURL(for: item) as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbCache.setObject(img, forKey: key)
        return img
    }

    // MARK: - Naming convention (PREFIX-N)

    var currentPrefix: String {
        UserDefaults.standard.string(forKey: Prefs.namePrefix) ?? "EVIDENCE-"
    }

    func nextNumber(for prefix: String) -> Int {
        var maxN = counters[prefix] ?? 0
        for item in items where !item.isWorkspace && item.name.hasPrefix(prefix) {
            if let n = Int(item.name.dropFirst(prefix.count)) { maxN = max(maxN, n) }
        }
        return maxN + 1
    }

    func formatName(prefix: String, number: Int) -> String {
        let digits = UserDefaults.standard.integer(forKey: Prefs.digits)
        let num = digits > 1 ? String(format: "%0\(digits)d", number) : String(number)
        return prefix + num
    }

    func peekNextName() -> String {
        formatName(prefix: currentPrefix, number: nextNumber(for: currentPrefix))
    }

    private func takeNextName() -> String {
        let prefix = currentPrefix
        let n = nextNumber(for: prefix)
        counters[prefix] = n
        return formatName(prefix: prefix, number: n)
    }

    func resetCounter() {
        counters[currentPrefix] = 0
        persist()
        objectWillChange.send()
    }

    private func sanitize(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/:\\?%*|\"<>\n\r\t")
        let cleaned = name.components(separatedBy: bad).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "capture" : cleaned
    }

    private func uniqueFileName(_ base: String, ext: String, ignoring: String? = nil) -> String {
        var candidate = "\(base).\(ext)"
        var i = 2
        while candidate.lowercased() != ignoring?.lowercased(),
              FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = "\(base)_\(i).\(ext)"
            i += 1
        }
        return candidate
    }

    // MARK: - Adding items

    @discardableResult
    func addImage(fileAt src: URL, mode: String, moveFile: Bool, notes: String = "") -> CaptureItem? {
        guard let source = CGImageSourceCreateWithURL(src as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let name = takeNextName()
        let fileName = uniqueFileName(sanitize(name), ext: "png")
        let dest = directory.appendingPathComponent(fileName)
        let isPNG = (CGImageSourceGetType(source) as String?) == UTType.png.identifier
        do {
            if isPNG && moveFile {
                try FileManager.default.moveItem(at: src, to: dest)
            } else if isPNG {
                try FileManager.default.copyItem(at: src, to: dest)
            } else {
                guard let data = ExportService.encode(cg, format: .png, dpi: nil) else { return nil }
                try data.write(to: dest)
            }
        } catch {
            NSLog("SecShot: could not save capture: \(error)")
            return nil
        }
        let item = CaptureItem(name: name, fileName: fileName, createdAt: Date(), mode: mode,
                               sha256: Hashing.sha256(fileAt: dest),
                               pixelWidth: cg.width, pixelHeight: cg.height, notes: notes)
        items.insert(item, at: 0)
        persist()
        return item
    }

    @discardableResult
    func addImage(_ image: CGImage, mode: String, notes: String = "") -> CaptureItem? {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("secshot-\(UUID().uuidString).png")
        guard let data = ExportService.encode(image, format: .png, dpi: 144),
              (try? data.write(to: tmp)) != nil else { return nil }
        return addImage(fileAt: tmp, mode: mode, moveFile: true, notes: notes)
    }

    func importWithPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        panel.prompt = "Import"
        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls)
    }

    func importFiles(_ urls: [URL]) {
        var added: [UUID] = []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if let item = addImage(fileAt: url, mode: "import", moveFile: false) { added.append(item.id) }
        }
        if !added.isEmpty { selection = Set(added) }
    }

    // MARK: - Comparison workspace (external images)

    private var workspaceDirectory: URL { directory.appendingPathComponent("Workspace", isDirectory: true) }

    /// Copies external images into the workspace. Names come from the original file names and
    /// the naming convention is not consumed. Returns the new items in the given order.
    @discardableResult
    func addWorkspaceImages(_ urls: [URL]) -> [CaptureItem] {
        let fm = FileManager.default
        try? fm.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
        var added: [CaptureItem] = []
        for url in urls {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            let base = sanitize(url.deletingPathExtension().lastPathComponent)
            var fileName = "Workspace/\(base).png"
            var n = 2
            while fm.fileExists(atPath: directory.appendingPathComponent(fileName).path) {
                fileName = "Workspace/\(base)_\(n).png"; n += 1
            }
            let dest = directory.appendingPathComponent(fileName)
            do {
                if (CGImageSourceGetType(source) as String?) == UTType.png.identifier {
                    try fm.copyItem(at: url, to: dest)
                } else {
                    guard let data = ExportService.encode(cg, format: .png, dpi: nil) else { continue }
                    try data.write(to: dest)
                }
            } catch {
                NSLog("SecShot: could not add workspace image: \(error)")
                continue
            }
            let item = CaptureItem(name: base, fileName: fileName, createdAt: Date(), mode: "external",
                                   sha256: Hashing.sha256(fileAt: dest),
                                   pixelWidth: cg.width, pixelHeight: cg.height,
                                   notes: "Source: \(url.lastPathComponent)", workspace: true)
            items.append(item)
            added.append(item)
        }
        if !added.isEmpty { persist() }
        return added
    }

    /// Moves a workspace image into the library as evidence, applying the naming convention.
    func promoteToLibrary(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].isWorkspace else { return }
        items[i].workspace = nil
        items[i].mode = "import"
        rename(id, to: takeNextName())
        workspaceTimelineIDs.removeAll { $0 == id }
        if workspaceBaseID == id { workspaceBaseID = nil }
        if workspaceChangeID == id { workspaceChangeID = nil }
        persist()
    }

    // MARK: - Edits

    /// Updates only the editable fields so concurrent renames are not overwritten.
    func updateEdits(id: UUID, annotations: [Annotation], crop: CGRect?, notes: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].annotations = annotations
        items[i].crop = crop
        items[i].notes = notes
        editRevision += 1
        persist()
    }

    func rename(_ id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = items.firstIndex(where: { $0.id == id }),
              items[i].name != trimmed else { return }
        let oldURL = fileURL(for: items[i])
        let folder = items[i].isWorkspace ? "Workspace/" : ""
        let fileName = uniqueFileName(folder + sanitize(trimmed), ext: "png", ignoring: items[i].fileName)
        do {
            if fileName != items[i].fileName {
                try FileManager.default.moveItem(at: oldURL, to: directory.appendingPathComponent(fileName))
            }
            items[i].name = trimmed
            items[i].fileName = fileName
            persist()
        } catch {
            NSLog("SecShot: could not rename: \(error)")
        }
    }

    /// Renames the items (in chronological order) with the current prefix: PREFIX-1, PREFIX-2…
    func applyConvention(to ids: Set<UUID>) {
        let ordered = items.filter { ids.contains($0.id) }.sorted { $0.createdAt < $1.createdAt }
        // Use temporary names first to free up the file names.
        for item in ordered { rename(item.id, to: "tmp-\(item.id.uuidString)") }
        for item in ordered { rename(item.id, to: takeNextName()) }
    }

    func moveToTrash(_ ids: Set<UUID>) {
        for item in items where ids.contains(item.id) {
            try? FileManager.default.trashItem(at: fileURL(for: item), resultingItemURL: nil)
        }
        items.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        timelineIDs.removeAll { ids.contains($0) }
        workspaceTimelineIDs.removeAll { ids.contains($0) }
        if let b = workspaceBaseID, ids.contains(b) { workspaceBaseID = nil }
        if let c = workspaceChangeID, ids.contains(c) { workspaceChangeID = nil }
        if let b = compareBaseID, ids.contains(b) { compareBaseID = nil }
        if let c = compareChangeID, ids.contains(c) { compareChangeID = nil }
        persist()
    }

    func revealInFinder(_ ids: Set<UUID>) {
        let urls = items.filter { ids.contains($0.id) }.map { fileURL(for: $0) }
        NSWorkspace.shared.activateFileViewerSelecting(urls.isEmpty ? [directory] : urls)
    }
}
