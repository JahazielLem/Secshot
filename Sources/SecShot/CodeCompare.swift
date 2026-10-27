// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import AppKit

enum DiffMark: Equatable {
    case added, removed
}

/// Line-level diff (LCS) with intra-line emphasis for modified lines, e.g. `role=user` → `role=admin`.
enum LineDiff {
    struct Result {
        var left: [Int: DiffMark] = [:]
        var right: [Int: DiffMark] = [:]
        var leftSpans: [Int: [NSRange]] = [:]
        var rightSpans: [Int: [NSRange]] = [:]
        var added = 0
        var removed = 0
    }

    static func compute(_ a: [String], _ b: [String]) -> Result {
        let n = a.count, m = b.count
        let ka = a.map { $0.trimmingCharacters(in: .whitespaces) }
        let kb = b.map { $0.trimmingCharacters(in: .whitespaces) }
        // LCS table (snippets are small, O(n·m) is fine).
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    dp[i][j] = ka[i] == kb[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }
        var r = Result()
        var i = 0, j = 0
        var removedRun: [Int] = [], addedRun: [Int] = []

        func flush() {
            // Pair removed/added lines of the same hunk and emphasize what changed inside them.
            for (x, y) in zip(removedRun, addedRun) {
                let (ra, rb) = changedRanges(a[x] as NSString, b[y] as NSString)
                if let ra { r.leftSpans[x] = [ra] }
                if let rb { r.rightSpans[y] = [rb] }
            }
            removedRun = []
            addedRun = []
        }

        while i < n || j < m {
            if i < n, j < m, ka[i] == kb[j] {
                flush()
                i += 1; j += 1
            } else if j < m, i == n || dp[i][j + 1] >= dp[i + 1][j] {
                r.right[j] = .added; r.added += 1; addedRun.append(j); j += 1
            } else {
                r.left[i] = .removed; r.removed += 1; removedRun.append(i); i += 1
            }
        }
        flush()
        return r
    }

    /// Ranges that differ between two lines once the common prefix and suffix are removed.
    private static func changedRanges(_ a: NSString, _ b: NSString) -> (NSRange?, NSRange?) {
        let la = a.length, lb = b.length
        var p = 0
        while p < la, p < lb, a.character(at: p) == b.character(at: p) { p += 1 }
        var s = 0
        while s < la - p, s < lb - p, a.character(at: la - 1 - s) == b.character(at: lb - 1 - s) { s += 1 }
        let ra = la - p - s > 0 ? NSRange(location: p, length: la - p - s) : nil
        let rb = lb - p - s > 0 ? NSRange(location: p, length: lb - p - s) : nil
        // Emphasis only helps when most of the line is shared.
        let shared = p + s
        guard shared >= max(la, lb) / 3 else { return (nil, nil) }
        return (ra, rb)
    }
}

// MARK: - Comparison and timeline images

extension CodeShotRenderer {
    struct Panel {
        var image: CGImage
        var label: String
        var accent: NSColor
    }

    static let accents: [NSColor] = [hex(0x2E66D9), hex(0x6B4DCC), hex(0xBF4D9E), hex(0xD63338)]

    /// Transparent margin `render` adds around a window so its shadow is not clipped.
    static func shadowInset(_ o: CodeShotOptions) -> CGFloat {
        o.background == .none && o.shadow && o.frame != .none ? 28 * o.scale : 0
    }

    /// Before/after comparison of two snippets with an optional line diff.
    static func renderComparison(base: String, change: String, baseLabel: String, changeLabel: String,
                                 options o: CodeShotOptions, horizontal: Bool, diff: Bool, arrows: Bool = false)
        -> (image: CGImage?, findings: [HeaderFinding], summary: String) {
        var a = o, b = o
        // Format first so the diff compares the same lines that are drawn.
        let base = o.formatJSON ? JSONFormatter.format(base, language: o.language) : base
        let change = o.formatJSON ? JSONFormatter.format(change, language: o.language) : change
        a.code = base; b.code = change
        a.background = .none; b.background = .none
        a.highlightLines = ""; b.highlightLines = ""
        var summary = ""
        if diff {
            let la = CodeHighlighter.highlight(base, language: o.language).lines
            let lb = CodeHighlighter.highlight(change, language: o.language).lines
            let d = LineDiff.compute(la, lb)
            a.lineMarks = d.left; a.emphasis = d.leftSpans
            b.lineMarks = d.right; b.emphasis = d.rightSpans
            summary = d.added + d.removed == 0 ? "No differences." : "\(d.removed) line(s) removed · \(d.added) line(s) added"
        }
        guard let ra = render(a), let rb = render(b) else { return (nil, [], summary) }
        let panels = [Panel(image: ra.image, label: baseLabel, accent: hex(0x2E66D9)),
                      Panel(image: rb.image, label: changeLabel, accent: hex(0xD63338))]
        let image = composite(panels, horizontal: horizontal, background: o.background, padding: o.padding,
                              scale: o.scale, connectors: arrows, inset: shadowInset(a))
        return (image, rb.findings, summary)
    }

    /// N snippets in order, numbered, with arrows between them.
    static func renderTimeline(steps: [(title: String, code: String)], options o: CodeShotOptions, horizontal: Bool,
                               arrows: Bool = true) -> CGImage? {
        var panels: [Panel] = []
        var inset: CGFloat = 0
        for (k, step) in steps.enumerated() where !step.code.isEmpty {
            var s = o
            s.code = step.code
            s.background = .none
            s.highlightLines = ""
            inset = shadowInset(s)
            guard let r = render(s) else { continue }
            let label = "STEP \(k + 1)" + (step.title.isEmpty ? "" : " — \(step.title)")
            let accent = accents[min(accents.count - 1, k * accents.count / max(1, steps.count))]
            panels.append(Panel(image: r.image, label: label, accent: accent))
        }
        guard !panels.isEmpty else { return nil }
        return composite(panels, horizontal: horizontal, background: o.background, padding: o.padding,
                         scale: o.scale, connectors: arrows, inset: inset)
    }

    /// Lays out rendered windows on one canvas with a label pill above each one.
    static func composite(_ panels: [Panel], horizontal: Bool, background: CodeBackground, padding: Double,
                          scale s: CGFloat, connectors: Bool, inset: CGFloat) -> CGImage? {
        let labelFont = NSFont.systemFont(ofSize: 13 * s, weight: .bold)
        let labelH = 28 * s, labelGap = 10 * s
        let gap: CGFloat = connectors ? 72 * s : 32 * s
        let pad = max(background == .none ? 16 * s : CGFloat(padding) * s, inset + 8 * s)

        // Visible window size (without the transparent shadow margin) and item frames.
        let sizes = panels.map { CGSize(width: CGFloat($0.image.width) - inset * 2, height: CGFloat($0.image.height) - inset * 2) }
        var frames: [CGRect] = []
        var cursor = pad
        for size in sizes {
            let item = CGSize(width: size.width, height: labelH + labelGap + size.height)
            frames.append(horizontal ? CGRect(x: cursor, y: pad, width: item.width, height: item.height)
                                     : CGRect(x: pad, y: cursor, width: item.width, height: item.height))
            cursor += (horizontal ? item.width : item.height) + gap
        }
        cursor -= gap
        let W = horizontal ? cursor + pad : (frames.map(\.width).max() ?? 0) + pad * 2
        let H = horizontal ? (frames.map(\.height).max() ?? 0) + pad * 2 : cursor + pad
        guard W < 30_000, H < 30_000, let ctx = Renderer.makeContext(width: Int(W), height: Int(H)) else { return nil }

        Renderer.withFlipped(ctx, height: H) {
            let full = CGRect(x: 0, y: 0, width: W, height: H)
            let colors = background.colors
            if colors.count == 1 {
                ctx.setFillColor(colors[0].cgColor); ctx.fill(full)
            } else if colors.count > 1, let g = CGGradient(colorsSpace: Renderer.srgb, colors: colors.map(\.cgColor) as CFArray, locations: nil) {
                ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: W, y: H), options: [])
            }
            for (k, p) in panels.enumerated() {
                let f = frames[k]
                // Label pill
                let text = NSAttributedString(string: p.label, attributes: [.font: labelFont, .foregroundColor: NSColor.white])
                let ts = text.size()
                let pill = CGRect(x: f.minX, y: f.minY, width: min(ts.width + 24 * s, f.width), height: labelH)
                ctx.setFillColor(p.accent.cgColor)
                ctx.addPath(CGPath(roundedRect: pill, cornerWidth: labelH / 2, cornerHeight: labelH / 2, transform: nil))
                ctx.fillPath()
                text.draw(with: CGRect(x: pill.minX + 12 * s, y: pill.midY - ts.height / 2, width: pill.width - 24 * s, height: ts.height),
                          options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
                // Window (with its shadow margin)
                let window = CGRect(x: f.minX - inset, y: f.minY + labelH + labelGap - inset,
                                    width: CGFloat(p.image.width), height: CGFloat(p.image.height))
                Renderer.drawImage(ctx, p.image, in: window)

                if connectors, k < panels.count - 1 {
                    let next = frames[k + 1]
                    let arrowColor = background == .none ? CGColor(gray: 0.5, alpha: 1)
                        : (background == .white || background == .steel ? CGColor(gray: 0.35, alpha: 1) : CGColor(gray: 1, alpha: 0.9))
                    let top = f.minY + labelH + labelGap
                    if horizontal {
                        let y = top + min(sizes[k].height, sizes[k + 1].height) / 2
                        Renderer.strokeArrow(ctx, from: CGPoint(x: f.maxX + gap * 0.2, y: y),
                                             to: CGPoint(x: next.minX - gap * 0.2, y: y), width: 4 * s, color: arrowColor)
                    } else {
                        let x = f.minX + min(f.width, next.width) / 2
                        Renderer.strokeArrow(ctx, from: CGPoint(x: x, y: f.maxY + gap * 0.2),
                                             to: CGPoint(x: x, y: next.minY - gap * 0.2), width: 4 * s, color: arrowColor)
                    }
                }
            }
        }
        return ctx.makeImage()
    }
}
