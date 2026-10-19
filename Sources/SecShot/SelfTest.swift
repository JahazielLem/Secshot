// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import AppKit

/// Command-line utilities:
///   SecShot --selftest <folder>    renders sample images with the rendering engine
///   SecShot --make-icon <iconset>  generates the app iconset
///   SecShot --permission-status <file>  writes whether Screen Recording access is granted
enum CommandLineTools {
    static func runIfRequested() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--selftest"), i + 1 < args.count {
            selfTest(URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        if let i = args.firstIndex(of: "--permission-status"), i + 1 < args.count {
            // Diagnostics: launch with `open -a SecShot --args --permission-status <file>` so that
            // SecShot (not the terminal) is the process macOS evaluates.
            let status = "screenCapture=\(CGPreflightScreenCaptureAccess())\n"
            try? status.write(toFile: args[i + 1], atomically: true, encoding: .utf8)
            exit(0)
        }
        if let i = args.firstIndex(of: "--make-icon"), i + 1 < args.count {
            makeIcon(URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
    }

    private static func write(_ img: CGImage?, _ url: URL) {
        guard let img, let data = ExportService.encode(img, format: .png, dpi: nil) else {
            print("✗ \(url.lastPathComponent)")
            return
        }
        try? data.write(to: url)
        print("✓ \(url.lastPathComponent) \(img.width)x\(img.height)")
    }

    /// Synthetic "terminal" image containing fake sensitive data.
    private static func fakeScreen(extraLine: String?) -> CGImage {
        let W = 1600, H = 900
        let ctx = Renderer.makeContext(width: W, height: H)!
        ctx.setFillColor(CGColor(srgbRed: 0.12, green: 0.13, blue: 0.16, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        Renderer.withFlipped(ctx, height: CGFloat(H)) {
            var lines = [
                "$ curl -i https://api.target.local/v1/login",
                "HTTP/1.1 200 OK",
                "Set-Cookie: PHPSESSID=9f8e7d6c5b4a3f2e1d0c; HttpOnly",
                "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhZG1pbiJ9.dGVzdHNpZ25hdHVyZQ",
                "user: admin@target.local   host: 10.10.20.15",
                "password: Sup3rS3cret!",
                "aws_access_key_id = AKIAIOSFODNN7EXAMPLE",
            ]
            if let extraLine { lines.append(extraLine) }
            for (i, line) in lines.enumerated() {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 30, weight: .regular),
                    .foregroundColor: NSColor(srgbRed: 0.85, green: 0.9, blue: 0.85, alpha: 1),
                ]
                NSAttributedString(string: line, attributes: attrs).draw(at: CGPoint(x: 40, y: 40 + CGFloat(i) * 52))
            }
        }
        return ctx.makeImage()!
    }

    private static func selfTest(_ dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = fakeScreen(extraLine: nil)
        let change = fakeScreen(extraLine: "uid=0(root) gid=0(root) groups=0(root)   <-- privilege escalation")
        write(base, dir.appendingPathComponent("01-base.png"))

        func ann(_ k: AnnotationKind, _ x: CGFloat, _ y: CGFloat, _ x2: CGFloat, _ y2: CGFloat, text: String = "", n: Int = 0) -> Annotation {
            var a = Annotation(kind: k, start: CGPoint(x: x, y: y), end: CGPoint(x: x2, y: y2),
                               color: k == .highlight ? RGBAColor(r: 1, g: 0.85, b: 0) : .red, lineWidth: 6, fontSize: 34)
            a.text = text; a.number = n
            if k == .text && text.hasPrefix("[") { a.filled = true }
            return a
        }
        let anns = [
            ann(.pixelate, 300, 136, 900, 176),
            ann(.blur, 320, 190, 1500, 230),
            ann(.redact, 200, 300, 520, 340),
            ann(.highlight, 30, 34, 900, 82),
            ann(.rectangle, 30, 236, 900, 290),
            ann(.arrow, 1200, 500, 920, 270),
            ann(.text, 1000, 520, 1000, 520, text: "[Cleartext credentials]"),
            ann(.step, 1180, 70, 1180, 70, n: 1),
            ann(.ellipse, 20, 340, 700, 410),
        ]
        let rendered = Renderer.render(base, annotations: anns, crop: nil)
        write(rendered, dir.appendingPathComponent("02-annotated.png"))
        write(Renderer.render(base, annotations: anns, crop: CGRect(x: 0, y: 0, width: 1000, height: 450)),
              dir.appendingPathComponent("03-crop.png"))
        write(Renderer.decorate(rendered, shadow: true, cornerRadius: 10, background: nil), dir.appendingPathComponent("04-shadow.png"))

        let diff = Renderer.highlightDifferences(base: base, change: change, threshold: 30, tint: true)
        print("  diff: \(diff?.regions.count ?? -1) regions, \(String(format: "%.3f", (diff?.changedRatio ?? 0) * 100))%")
        let blue = CGColor(srgbRed: 0.18, green: 0.40, blue: 0.85, alpha: 1), red = CGColor(srgbRed: 0.84, green: 0.2, blue: 0.22, alpha: 1)
        write(Renderer.compose([.init(image: base, title: "BEFORE", subtitle: "EVIDENCE-1 · 2026-10-15 12:00:00", accent: blue),
                                .init(image: diff!.image, title: "AFTER — changes highlighted", subtitle: "EVIDENCE-2", accent: red)],
                               horizontal: true, connectors: false), dir.appendingPathComponent("05-diff.png"))
        write(Renderer.compose([.init(image: base, title: "STEP 1 — EVIDENCE-1", subtitle: "login", accent: blue),
                                .init(image: rendered, title: "STEP 2 — EVIDENCE-2", subtitle: "token", accent: blue),
                                .init(image: change, title: "STEP 3 — EVIDENCE-3", subtitle: "root", accent: red)],
                               horizontal: false, connectors: true), dir.appendingPathComponent("06-timeline.png"))
        write(Renderer.split(base: base, change: change, fraction: 0.5, baseLabel: "BEFORE", changeLabel: "AFTER"),
              dir.appendingPathComponent("07-split.png"))

        let sem = DispatchSemaphore(value: 0)
        Task.detached {
            let findings = await SensitiveDetector.detect(in: base, disabled: [])
            for f in findings { print("  sensitive: [\(f.category)] \(f.text)") }
            let redacted = Renderer.render(base, annotations: findings.map {
                Annotation(kind: .redact, start: $0.rect.origin, end: CGPoint(x: $0.rect.maxX, y: $0.rect.maxY),
                           color: .black, lineWidth: 4, fontSize: 20)
            }, crop: nil)
            write(redacted, dir.appendingPathComponent("08-auto-redaction.png"))
            sem.signal()
        }
        sem.wait()
    }

    private static func makeIcon(_ dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = size * scale
                guard let ctx = Renderer.makeContext(width: px, height: px) else { continue }
                let s = CGFloat(px)
                let r = CGRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
                let path = CGPath(roundedRect: r, cornerWidth: s * 0.18, cornerHeight: s * 0.18, transform: nil)
                ctx.addPath(path)
                ctx.clip()
                let colors = [CGColor(srgbRed: 0.10, green: 0.12, blue: 0.20, alpha: 1), CGColor(srgbRed: 0.20, green: 0.30, blue: 0.55, alpha: 1)] as CFArray
                let grad = CGGradient(colorsSpace: Renderer.srgb, colors: colors, locations: [0, 1])!
                ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
                ctx.resetClip()
                let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .semibold)
                    .applying(.init(paletteColors: [.white]))
                if let sym = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: nil)?.withSymbolConfiguration(cfg),
                   let cg = sym.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    let w = CGFloat(cg.width) * s * 0.5 / CGFloat(max(cg.width, cg.height))
                    let h = CGFloat(cg.height) * s * 0.5 / CGFloat(max(cg.width, cg.height))
                    ctx.draw(cg, in: CGRect(x: (s - w) / 2, y: (s - h) / 2, width: w, height: h))
                }
                ctx.setFillColor(CGColor(srgbRed: 0.95, green: 0.25, blue: 0.25, alpha: 1))
                ctx.fill(CGRect(x: s * 0.42, y: s * 0.47, width: s * 0.16, height: s * 0.06))
                let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
                if let img = ctx.makeImage(), let data = ExportService.encode(img, format: .png, dpi: nil) {
                    try? data.write(to: dir.appendingPathComponent(name))
                }
            }
        }
    }
}
