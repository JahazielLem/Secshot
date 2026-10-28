// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import CoreGraphics
import Foundation
import Vision

enum TextOutputFormat: String, CaseIterable, Identifiable {
    case plain, markdown, csv

    var id: String { rawValue }

    var label: String {
        switch self {
        case .plain: return "Plain text"
        case .markdown: return "Markdown"
        case .csv: return "CSV"
        }
    }

    var symbol: String {
        switch self {
        case .plain: return "text.alignleft"
        case .markdown: return "number"
        case .csv: return "tablecells"
        }
    }
}

/// One piece of recognized text. `rect` is normalized (0–1) with a top-left origin.
struct OCRFragment: Equatable {
    var text: String
    var rect: CGRect
}

/// On-device OCR with Apple Vision. Nothing leaves the Mac.
enum TextRecognizer {
    static func recognize(_ image: CGImage, languages: [String], languageCorrection: Bool) async -> [OCRFragment] {
        await Task.detached(priority: .userInitiated) { () -> [OCRFragment] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = languageCorrection
            if languages.isEmpty {
                request.automaticallyDetectsLanguage = true
            } else {
                request.recognitionLanguages = languages
            }
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do { try handler.perform([request]) } catch { return [] }
            return (request.results ?? []).flatMap { obs -> [OCRFragment] in
                guard let candidate = obs.topCandidates(1).first,
                      !candidate.string.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
                return splitColumns(candidate, lineBox: obs.boundingBox)
            }
        }.value
    }

    private static let wordPattern = try! NSRegularExpression(pattern: #"\S+"#)

    /// Vision often returns a whole table row as one line when columns are separated only by
    /// spaces (typical in PDFs). Using each word's position, a gap clearly wider than a normal space
    /// starts a new fragment, so columns can be detected later.
    private static func splitColumns(_ candidate: VNRecognizedText, lineBox: CGRect) -> [OCRFragment] {
        func topLeft(_ b: CGRect) -> CGRect { CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height) }
        let text = candidate.string
        let ns = text as NSString
        var words: [OCRFragment] = []
        for m in wordPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let range = Range(m.range, in: text),
                  let box = (try? candidate.boundingBox(for: range))?.boundingBox, box.width > 0 else { return [OCRFragment(text: text, rect: topLeft(lineBox))] }
            words.append(OCRFragment(text: ns.substring(with: m.range), rect: topLeft(box)))
        }
        guard var current = words.first else { return [] }
        var fragments: [OCRFragment] = []
        for word in words.dropFirst() {
            let gap = word.rect.minX - current.rect.maxX
            if gap > max(current.rect.height, word.rect.height) * 1.0 {
                fragments.append(current)
                current = word
            } else {
                current.text += " " + word.text
                current.rect = current.rect.union(word.rect)
            }
        }
        fragments.append(current)
        return fragments
    }
}

/// Rebuilds document structure (lines, paragraphs, tables, lists, headings) from OCR fragments.
enum TextLayoutFormatter {
    struct Line {
        var fragments: [OCRFragment]
        var rect: CGRect
        var text: String { fragments.map(\.text).joined(separator: " ") }
    }

    enum Block {
        case paragraph([Line])
        case table([[String]])
    }

    struct Output {
        var text: String
        var summary: String
        var tables: Int
    }

    // MARK: Lines

    static func lines(_ fragments: [OCRFragment]) -> [Line] {
        var lines: [Line] = []
        for f in fragments.sorted(by: { $0.rect.midY < $1.rect.midY }) {
            if let i = lines.indices.last,
               abs(f.rect.midY - lines[i].rect.midY) < 0.5 * min(f.rect.height, lines[i].rect.height) {
                lines[i].fragments.append(f)
                lines[i].rect = lines[i].rect.union(f.rect)
            } else {
                lines.append(Line(fragments: [f], rect: f.rect))
            }
        }
        for i in lines.indices { lines[i].fragments.sort { $0.rect.minX < $1.rect.minX } }
        return lines
    }

    // MARK: Blocks

    // MARK: Tables

    /// Detects a table starting at a line with 2+ cells and rebuilds it as a grid.
    ///
    /// Columns come from the cells' left edges. Rows are anchored on the first column; every other
    /// fragment joins the row whose vertical band contains it, so wrapped (multi-line) cells — often
    /// vertically centered next to a single-line cell — become one cell instead of extra lines.
    /// Returns the range of lines used and the rows.
    private static func detectTable(_ lines: [Line], at i: Int, textHeight h: CGFloat) -> (Range<Int>, [[String]])? {
        let first = lines[i]
        let k = first.fragments.count
        guard k >= 2 else { return nil }
        let tolerance = max(0.012, h * 1.6)
        var anchors = first.fragments.map(\.rect.minX)

        func column(_ f: OCRFragment) -> Int? {
            let c = anchors.indices.min { abs(anchors[$0] - f.rect.minX) < abs(anchors[$1] - f.rect.minX) } ?? 0
            return abs(anchors[c] - f.rect.minX) < tolerance ? c : nil
        }
        /// A line belongs to the table if it has the same number of cells, or all its cells sit on columns.
        /// A lone fragment in the first column is treated as ordinary text (e.g. a caption), not a row.
        func belongs(_ line: Line) -> Bool {
            if line.fragments.count == k { return true }
            let cols = line.fragments.map(column)
            guard !cols.contains(where: { $0 == nil }) else { return false }
            return !(line.fragments.count == 1 && cols.first == 0)
        }
        func closeEnough(_ a: Line, _ b: Line) -> Bool { b.rect.minY - a.rect.maxY < h * 3 }

        var end = i + 1
        while end < lines.count, closeEnough(lines[end - 1], lines[end]), belongs(lines[end]) { end += 1 }
        // Wrapped cells of the first row can start above it: extend upwards with non-first-column lines.
        var start = i
        while start > 0, closeEnough(lines[start - 1], lines[start]),
              lines[start - 1].fragments.allSatisfy({ (column($0) ?? 0) > 0 }) { start -= 1 }

        let run = Array(lines[start..<end])
        let multi = run.filter { $0.fragments.count >= 2 }
        guard multi.count >= 2 else { return nil }

        // Refine column anchors from complete rows.
        let complete = run.filter { $0.fragments.count == k }
        if complete.count >= 2 {
            anchors = (0..<k).map { c in complete.map { $0.fragments[c].rect.minX }.reduce(0, +) / CGFloat(complete.count) }
        }
        guard zip(anchors, anchors.dropFirst()).allSatisfy({ $0 < $1 }) else { return nil }

        // Assign each fragment to a column (complete rows by order, others by nearest left edge).
        var placed: [(f: OCRFragment, col: Int, rowStart: Bool)] = []
        for line in run {
            let isComplete = line.fragments.count == k
            for (n, f) in line.fragments.enumerated() {
                let c = isComplete ? n : (anchors.indices.min { abs(anchors[$0] - f.rect.minX) < abs(anchors[$1] - f.rect.minX) } ?? 0)
                placed.append((f, c, c == 0 && line.fragments.count >= 2))
            }
        }
        // Row anchors: first-column cells on lines that also have other cells.
        var rowCenters = placed.filter { $0.rowStart }.map { $0.f.rect.midY }.sorted()
        if rowCenters.isEmpty { rowCenters = [placed.map { $0.f.rect.midY }.min() ?? 0] }
        let bounds = zip(rowCenters, rowCenters.dropFirst()).map { ($0 + $1) / 2 }

        var cells = Array(repeating: Array(repeating: [OCRFragment](), count: k), count: rowCenters.count)
        for p in placed {
            let row = bounds.firstIndex { p.f.rect.midY < $0 } ?? bounds.count
            cells[row][p.col].append(p.f)
        }
        let clean = CharacterSet(charactersIn: "|│¦┃ \t")
        let rows = cells.map { row in
            row.map { frags in
                frags.sorted { abs($0.rect.midY - $1.rect.midY) < h * 0.5 ? $0.rect.minX < $1.rect.minX : $0.rect.midY < $1.rect.midY }
                    .map(\.text).joined(separator: " ")
                    .trimmingCharacters(in: clean)   // grid lines are often read as "|"
            }
        }
        guard rows.count >= 2 else { return nil }
        return (start..<end, rows)
    }

    static func blocks(_ lines: [Line]) -> [Block] {
        guard !lines.isEmpty else { return [] }
        let h = textHeight(lines)
        var blocks: [Block] = []
        var paragraph: [Line] = []
        var paragraphStart = 0
        var i = 0

        func flushParagraph(upTo limit: Int) {
            // Lines already absorbed by a table (it can extend upwards) are dropped from the paragraph.
            let keep = paragraph.prefix(max(0, limit - paragraphStart))
            if !keep.isEmpty { blocks.append(.paragraph(Array(keep))) }
            paragraph = []
        }

        while i < lines.count {
            if lines[i].fragments.count >= 2, let (range, rows) = detectTable(lines, at: i, textHeight: h) {
                flushParagraph(upTo: range.lowerBound)
                blocks.append(.table(rows))
                i = range.upperBound
                paragraphStart = i
                continue
            }
            // Paragraph break on a large vertical gap.
            if let prev = paragraph.last, lines[i].rect.minY - prev.rect.maxY > h * 0.9 {
                flushParagraph(upTo: i)
                paragraphStart = i
            }
            if paragraph.isEmpty { paragraphStart = i }
            paragraph.append(lines[i])
            i += 1
        }
        flushParagraph(upTo: lines.count)
        return blocks
    }

    /// Typical text height, measured on individual fragments (a line's box grows when its cells are
    /// vertically offset, which would distort heading detection).
    static func textHeight(_ lines: [Line]) -> CGFloat {
        median(lines.flatMap { $0.fragments.map(\.rect.height) })
    }

    // MARK: Output

    static func format(_ fragments: [OCRFragment], as format: TextOutputFormat) -> Output {
        let allLines = lines(fragments)
        let blocks = blocks(allLines)
        let medianH = textHeight(allLines)
        var parts: [String] = []
        var tables: [String] = []

        for block in blocks {
            switch block {
            case .table(let rows):
                tables.append("\(rows.count)×\(rows.first?.count ?? 0)")
                switch format {
                case .plain: parts.append(rows.map { $0.joined(separator: "\t") }.joined(separator: "\n"))
                case .markdown: parts.append(markdownTable(rows))
                case .csv: parts.append(rows.map(csvRow).joined(separator: "\n"))
                }
            case .paragraph(let lines):
                switch format {
                case .plain:
                    parts.append(lines.map { plainLine($0) }.joined(separator: "\n"))
                case .markdown:
                    parts.append(lines.map { markdownLine($0, medianHeight: medianH) }.joined(separator: "\n"))
                case .csv:
                    parts.append(lines.map { csvRow($0.fragments.map(\.text)) }.joined(separator: "\n"))
                }
            }
        }

        let text = parts.joined(separator: format == .csv ? "\n\n" : "\n\n")
        var summary = "\(allLines.count) line\(allLines.count == 1 ? "" : "s")"
        if !tables.isEmpty { summary += " · \(tables.count) table\(tables.count == 1 ? "" : "s") (\(tables.joined(separator: ", ")))" }
        return Output(text: text, summary: summary, tables: tables.count)
    }

    /// Fragments far apart on the same line are separated by a tab, close ones by a space.
    private static func plainLine(_ line: Line) -> String {
        var out = ""
        for (k, f) in line.fragments.enumerated() {
            if k > 0 {
                let gap = f.rect.minX - line.fragments[k - 1].rect.maxX
                out += gap > line.rect.height * 1.5 ? "\t" : " "
            }
            out += f.text
        }
        return out
    }

    private static let bulletPattern = try! NSRegularExpression(pattern: #"^\s*[•·▪◦●○■□➤►‣⁃∙]\s*"#)
    private static let dashBulletPattern = try! NSRegularExpression(pattern: #"^\s*[-*–—]\s+"#)
    private static let numberedPattern = try! NSRegularExpression(pattern: #"^\s*\(?(\d{1,3})[.)]\s+"#)

    private static func markdownLine(_ line: Line, medianHeight: CGFloat) -> String {
        var text = line.text.trimmingCharacters(in: .whitespaces)
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        if let m = bulletPattern.firstMatch(in: text, range: full) ?? dashBulletPattern.firstMatch(in: text, range: full) {
            return "- " + ns.substring(from: NSMaxRange(m.range))
        }
        if let m = numberedPattern.firstMatch(in: text, range: full) {
            return "\(ns.substring(with: m.range(at: 1))). " + ns.substring(from: NSMaxRange(m.range))
        }
        // Headings: noticeably taller text on a short line.
        if text.count <= 90, medianHeight > 0 {
            let ratio = (line.fragments.map(\.rect.height).max() ?? line.rect.height) / medianHeight
            if ratio >= 1.7 { return "# " + text }
            if ratio >= 1.3 { return "## " + text }
        }
        // Avoid accidental Markdown syntax from recognized text.
        if let first = text.first, "#>".contains(first) { text = "\\" + text }
        return text
    }

    static func markdownTable(_ rows: [[String]]) -> String {
        guard let header = rows.first else { return "" }
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "|", with: "\\|").trimmingCharacters(in: .whitespaces)
        }
        let widths = (0..<header.count).map { c in max(3, rows.map { esc($0[c]).count }.max() ?? 3) }
        func row(_ cells: [String]) -> String {
            "| " + cells.enumerated().map { esc($0.element).padding(toLength: widths[$0.offset], withPad: " ", startingAt: 0) }
                .joined(separator: " | ") + " |"
        }
        let separator = "| " + widths.map { String(repeating: "-", count: $0) }.joined(separator: " | ") + " |"
        return ([row(header), separator] + rows.dropFirst().map(row)).joined(separator: "\n")
    }

    private static func csvRow(_ cells: [String]) -> String {
        cells.map { c in
            c.contains(where: { ",\"\n".contains($0) }) ? "\"" + c.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : c
        }.joined(separator: ",")
    }

    private static func median(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        return s[s.count / 2]
    }
}
