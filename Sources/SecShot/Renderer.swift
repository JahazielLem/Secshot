// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Rendering engine: annotation flattening, redaction, decoration, composites and diff.
enum Renderer {
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    static let ciContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: max(1, width), height: max(1, height), bitsPerComponent: 8,
                  bytesPerRow: 0, space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// Runs `body` with a flipped context (top-left origin) and an NSGraphicsContext for text.
    static func withFlipped(_ ctx: CGContext, height: CGFloat, _ body: () -> Void) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: height)
        ctx.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        body()
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
    }

    /// Draws an image into a flipped context without turning it upside down.
    static func drawImage(_ ctx: CGContext, _ img: CGImage, in r: CGRect) {
        ctx.saveGState()
        ctx.translateBy(x: r.minX, y: r.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(origin: .zero, size: r.size))
        ctx.restoreGState()
    }

    // MARK: - Annotation flattening

    static func render(_ base: CGImage, annotations: [Annotation], crop: CGRect?) -> CGImage {
        let w = base.width, h = base.height
        guard let ctx = makeContext(width: w, height: h) else { return base }
        let full = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.draw(base, in: full)

        // 1) Redactions first (over the original pixels) so arrows and text stay on top.
        let source = CIImage(cgImage: base)
        for a in annotations where a.kind.isRedaction {
            let r = a.rect.intersection(full).integral
            guard r.width >= 2, r.height >= 2 else { continue }
            let cgRect = CGRect(x: r.minX, y: CGFloat(h) - r.maxY, width: r.width, height: r.height)
            switch a.kind {
            case .redact:
                ctx.setFillColor(a.color.withAlpha(1).cgColor)
                ctx.fill(cgRect)
            case .pixelate, .blur:
                if let patch = redactedPatch(source, rect: cgRect, kind: a.kind) {
                    ctx.draw(patch, in: cgRect)
                }
            default: break
            }
        }

        // 2) Focus spotlights. They work on the already-redacted image, so a redaction in the
        //    dimmed surroundings can never be undone by the blur.
        let spots = annotations.filter { $0.kind == .spotlight && $0.rect.width > 4 && $0.rect.height > 4 }
        if !spots.isEmpty, let current = ctx.makeImage(), let lit = applySpotlights(current, spots) {
            ctx.saveGState()
            ctx.setBlendMode(.copy)
            ctx.draw(lit, in: full)
            ctx.restoreGState()
        }

        // 3) Magnifiers (also from the redacted image, so secrets are never enlarged).
        for m in annotations where m.kind == .magnify {
            drawMagnifier(m, in: ctx, size: CGSize(width: w, height: h))
        }

        // 4) Shapes and text.
        withFlipped(ctx, height: CGFloat(h)) {
            for a in annotations where !a.kind.isRedaction { draw(a, in: ctx) }
        }

        guard var img = ctx.makeImage() else { return base }
        if let crop {
            let cr = crop.intersection(full).integral
            if cr.width > 4, cr.height > 4, let cropped = img.cropping(to: cr) { img = cropped }
        }
        return img
    }

    /// Large-block pixelation. "Blur" pixelates first to destroy high-frequency detail
    /// (a plain Gaussian blur over text can be reversed).
    static func redactedPatch(_ src: CIImage, rect: CGRect, kind: AnnotationKind) -> CGImage? {
        let minSide = min(rect.width, rect.height)
        let clamped = src.clampedToExtent()
        let px = CIFilter.pixellate()
        px.inputImage = clamped
        px.center = rect.origin
        var output: CIImage?
        if kind == .pixelate {
            px.scale = Float(max(12, minSide / 2.5))
            output = px.outputImage
        } else {
            px.scale = Float(max(8, minSide / 5))
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = px.outputImage?.clampedToExtent()
            blur.radius = Float(max(12, minSide / 2))
            output = blur.outputImage
        }
        guard let out = output?.cropped(to: rect) else { return nil }
        return ciContext.createCGImage(out, from: rect)
    }

    // MARK: - Focus spotlight

    /// Keeps the spotlight shapes untouched and blurs + darkens everything else, with a soft edge.
    static func applySpotlights(_ img: CGImage, _ spots: [Annotation]) -> CGImage? {
        let W = img.width, H = img.height
        let extent = CGRect(x: 0, y: 0, width: W, height: H)
        let ref = CGFloat(max(W, H))
        let current = CIImage(cgImage: img)

        let dim = CGFloat(min(0.9, max(0, spots.map(\.spotlightDim).max() ?? 0.55)))
        let blur = CGFloat(spots.map(\.spotlightBlur).max() ?? 0.5)
        var surroundings = current
        if blur > 0.01 {
            surroundings = current.clampedToExtent()
                .applyingGaussianBlur(sigma: Double(ref * 0.012 * blur))
                .cropped(to: extent)
        }
        let k = 1 - dim
        surroundings = surroundings.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0),
        ])

        // Mask: white shapes on black (Core Graphics uses a bottom-left origin here).
        guard let mctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        mctx.setFillColor(CGColor(gray: 0, alpha: 1))
        mctx.fill(extent)
        mctx.setFillColor(CGColor(gray: 1, alpha: 1))
        for s in spots {
            let r = s.rect
            let cg = CGRect(x: r.minX, y: CGFloat(H) - r.maxY, width: r.width, height: r.height)
            if s.spotlightShape == "rectangle" {
                let radius = min(r.width, r.height) * 0.08
                mctx.addPath(CGPath(roundedRect: cg, cornerWidth: radius, cornerHeight: radius, transform: nil))
            } else {
                mctx.addEllipse(in: cg)
            }
            mctx.fillPath()
        }
        guard let maskCG = mctx.makeImage() else { return nil }
        let mask = CIImage(cgImage: maskCG).clampedToExtent()
            .applyingGaussianBlur(sigma: Double(ref * 0.006))
            .cropped(to: extent)

        let out = current.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: surroundings,
            kCIInputMaskImageKey: mask,
        ])
        return ciContext.createCGImage(out, from: extent)
    }

    /// Outline drawn around a spotlight when "Outline" is enabled.
    static func strokeSpotlight(_ a: Annotation, in ctx: CGContext) {
        guard a.filled else { return }
        ctx.setStrokeColor(a.color.cgColor)
        ctx.setLineWidth(max(2, a.lineWidth * 0.6))
        if a.spotlightShape == "rectangle" {
            let radius = min(a.rect.width, a.rect.height) * 0.08
            ctx.addPath(CGPath(roundedRect: a.rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.strokePath()
        } else {
            ctx.strokeEllipse(in: a.rect)
        }
    }

    // MARK: - Magnifier

    /// Enlarges `source` by `factor`. Pixel-perfect mode keeps every source pixel as a crisp
    /// block (ideal for screenshots and text); smooth mode uses Lanczos resampling.
    static func enlarge(_ source: CGImage, factor: CGFloat, smooth: Bool) -> CGImage? {
        let w = Int((CGFloat(source.width) * factor).rounded())
        let h = Int((CGFloat(source.height) * factor).rounded())
        guard w > 0, h > 0 else { return nil }
        if smooth {
            let f = CIFilter.lanczosScaleTransform()
            f.inputImage = CIImage(cgImage: source)
            f.scale = Float(factor)
            f.aspectRatio = 1
            guard let out = f.outputImage else { return nil }
            let r = CGRect(x: 0, y: 0, width: w, height: h)
            return ciContext.createCGImage(out.cropped(to: r), from: r)
        }
        guard let ctx = makeContext(width: w, height: h) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Effective zoom and frame of the enlarged copy, kept fully inside the image. The zoom is
    /// only reduced when the enlarged copy would not fit at all.
    static func magnifierFrame(_ m: Annotation, imageSize: CGSize) -> (factor: CGFloat, rect: CGRect) {
        let src = m.rect
        guard src.width > 0, src.height > 0 else { return (1, m.magnifiedRect) }
        let margin = CGFloat(max(4, m.lineWidth * 1.5))   // room for the border
        let room = CGSize(width: max(1, imageSize.width - margin * 2), height: max(1, imageSize.height - margin * 2))
        let factor = min(CGFloat(m.zoomFactor), room.width / src.width, room.height / src.height)
        let size = CGSize(width: src.width * factor, height: src.height * factor)
        var origin = m.dest ?? CGPoint(x: src.maxX + 24, y: src.minY)
        origin.x = min(max(origin.x, margin), imageSize.width - margin - size.width)
        origin.y = min(max(origin.y, margin), imageSize.height - margin - size.height)
        return (factor, CGRect(origin: origin, size: size))
    }

    static func drawMagnifier(_ m: Annotation, in ctx: CGContext, size: CGSize) {
        let full = CGRect(origin: .zero, size: size)
        let src = m.rect.intersection(full).integral
        let (factor, dst) = magnifierFrame(m, imageSize: size)
        guard src.width >= 4, src.height >= 4,
              let current = ctx.makeImage(),
              let patch = current.cropping(to: src),
              let big = enlarge(patch, factor: factor, smooth: m.smoothZoom) else { return }
        let color = m.color.cgColor
        let lw = CGFloat(max(2, m.lineWidth * 0.6))

        withFlipped(ctx, height: size.height) {
            // Connector lines between the facing sides of the source and the enlarged copy.
            let dx = dst.midX - src.midX, dy = dst.midY - src.midY
            let pairs: [(CGPoint, CGPoint)]
            if abs(dx) >= abs(dy) {
                let sx = dx > 0 ? src.maxX : src.minX, tx = dx > 0 ? dst.minX : dst.maxX
                pairs = [(CGPoint(x: sx, y: src.minY), CGPoint(x: tx, y: dst.minY)),
                         (CGPoint(x: sx, y: src.maxY), CGPoint(x: tx, y: dst.maxY))]
            } else {
                let sy = dy > 0 ? src.maxY : src.minY, ty = dy > 0 ? dst.minY : dst.maxY
                pairs = [(CGPoint(x: src.minX, y: sy), CGPoint(x: dst.minX, y: ty)),
                         (CGPoint(x: src.maxX, y: sy), CGPoint(x: dst.maxX, y: ty))]
            }
            ctx.saveGState()
            ctx.setStrokeColor(m.color.withAlpha(0.75).cgColor)
            ctx.setLineWidth(lw * 0.7)
            ctx.setLineDash(phase: 0, lengths: [lw * 3, lw * 2])
            for (a, b) in pairs { ctx.move(to: a); ctx.addLine(to: b) }
            ctx.strokePath()
            ctx.restoreGState()

            // Source outline.
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lw)
            ctx.stroke(src)

            // Enlarged copy with a drop shadow and border.
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -lw * 2), blur: lw * 6, color: CGColor(gray: 0, alpha: 0.45))
            ctx.setFillColor(.white)
            ctx.fill(dst)
            ctx.restoreGState()
            ctx.saveGState()
            ctx.interpolationQuality = m.smoothZoom ? .high : .none
            drawImage(ctx, big, in: dst)
            ctx.restoreGState()
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lw * 1.5)
            ctx.stroke(dst.insetBy(dx: -lw * 0.75, dy: -lw * 0.75))

            // Zoom badge, just outside the enlarged copy (above it, or below if there is no room).
            let label = NSAttributedString(string: String(format: "%.1f×", factor), attributes: [
                .font: NSFont.systemFont(ofSize: max(12, lw * 5), weight: .bold),
                .foregroundColor: NSColor.white,
            ])
            let ls = label.size()
            let bw = ls.width + lw * 3, bh = ls.height + lw
            let gap = lw * 2
            let by = dst.minY - bh - gap >= 0 ? dst.minY - bh - gap : min(dst.maxY + gap, size.height - bh)
            let badge = CGRect(x: max(0, dst.maxX - bw), y: by, width: bw, height: bh)
            ctx.setFillColor(m.color.withAlpha(0.9).cgColor)
            ctx.addPath(CGPath(roundedRect: badge, cornerWidth: badge.height / 2, cornerHeight: badge.height / 2, transform: nil))
            ctx.fillPath()
            label.draw(at: CGPoint(x: badge.minX + lw * 1.5, y: badge.minY + lw * 0.5))
        }
    }

    // MARK: - Shapes

    static func textAttributes(_ a: Annotation) -> [NSAttributedString.Key: Any] {
        let font = NSFont.systemFont(ofSize: a.fontSize, weight: .bold)
        if a.filled {
            return [.font: font, .foregroundColor: NSColor.white]
        }
        return [.font: font, .foregroundColor: a.color.nsColor,
                .strokeColor: NSColor.white, .strokeWidth: -2.5]
    }

    static func textSize(_ a: Annotation) -> CGSize {
        let str = NSAttributedString(string: a.text.isEmpty ? " " : a.text, attributes: textAttributes(a))
        let r = str.boundingRect(with: CGSize(width: 100_000, height: 100_000), options: [.usesLineFragmentOrigin])
        return CGSize(width: ceil(r.width), height: ceil(r.height))
    }

    /// Bounds in image coordinates (used for selection and hit testing).
    static func bounds(_ a: Annotation, imageSize: CGSize? = nil) -> CGRect {
        switch a.kind {
        case .text:
            let r = CGRect(origin: a.start, size: textSize(a))
            return a.filled ? r.insetBy(dx: -a.fontSize * 0.4, dy: -a.fontSize * 0.25) : r
        case .step:
            let d = a.fontSize * 1.5
            return CGRect(x: a.start.x - d / 2, y: a.start.y - d / 2, width: d, height: d)
        case .line, .arrow:
            return a.rect.insetBy(dx: -(a.lineWidth + 8), dy: -(a.lineWidth + 8))
        case .magnify:
            let frame = imageSize.map { magnifierFrame(a, imageSize: $0).rect } ?? a.magnifiedRect
            return a.rect.union(frame)
        default:
            return a.rect
        }
    }

    static func strokeArrow(_ ctx: CGContext, from s: CGPoint, to e: CGPoint, width lw: CGFloat, color: CGColor) {
        let angle = atan2(e.y - s.y, e.x - s.x)
        let head = max(lw * 4, 16)
        let spread = CGFloat.pi / 7
        let p1 = CGPoint(x: e.x - head * cos(angle - spread), y: e.y - head * sin(angle - spread))
        let p2 = CGPoint(x: e.x - head * cos(angle + spread), y: e.y - head * sin(angle + spread))
        let shaftEnd = CGPoint(x: e.x - head * 0.8 * cos(angle), y: e.y - head * 0.8 * sin(angle))
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(lw)
        ctx.setLineCap(.round)
        ctx.move(to: s)
        ctx.addLine(to: shaftEnd)
        ctx.strokePath()
        ctx.move(to: e)
        ctx.addLine(to: p1)
        ctx.addLine(to: p2)
        ctx.closePath()
        ctx.fillPath()
    }

    static func draw(_ a: Annotation, in ctx: CGContext) {
        let color = a.color.cgColor
        let lw = CGFloat(a.lineWidth)
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        let shadow = { ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 5, color: CGColor(gray: 0, alpha: 0.35)) }

        switch a.kind {
        case .rectangle:
            shadow()
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lw)
            ctx.stroke(a.rect)
        case .ellipse:
            shadow()
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lw)
            ctx.strokeEllipse(in: a.rect)
        case .line:
            shadow()
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lw)
            ctx.move(to: a.start)
            ctx.addLine(to: a.end)
            ctx.strokePath()
        case .arrow:
            shadow()
            strokeArrow(ctx, from: a.start, to: a.end, width: lw, color: color)
        case .highlight:
            ctx.setBlendMode(.multiply)
            ctx.setFillColor(a.color.withAlpha(0.45).cgColor)
            ctx.fill(a.rect)
        case .text:
            let str = NSAttributedString(string: a.text, attributes: textAttributes(a))
            let size = textSize(a)
            if a.filled {
                let bg = bounds(a)
                shadow()
                ctx.setFillColor(color)
                ctx.addPath(CGPath(roundedRect: bg, cornerWidth: a.fontSize * 0.3, cornerHeight: a.fontSize * 0.3, transform: nil))
                ctx.fillPath()
                ctx.setShadow(offset: .zero, blur: 0, color: nil)
            }
            str.draw(with: CGRect(origin: a.start, size: size), options: [.usesLineFragmentOrigin])
        case .step:
            let r = bounds(a)
            shadow()
            ctx.setFillColor(color)
            ctx.fillEllipse(in: r)
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.setStrokeColor(.white)
            ctx.setLineWidth(max(2, a.fontSize * 0.08))
            ctx.strokeEllipse(in: r.insetBy(dx: 1, dy: 1))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: a.fontSize * 0.85, weight: .heavy),
                .foregroundColor: NSColor.white,
            ]
            let s = NSAttributedString(string: "\(a.number)", attributes: attrs)
            let sz = s.size()
            s.draw(at: CGPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2))
        case .spotlight:
            strokeSpotlight(a, in: ctx)
        default:
            break
        }
    }

    // MARK: - macOS-style decoration

    static func decorate(_ img: CGImage, shadow: Bool, cornerRadius: CGFloat, background: CGColor?) -> CGImage {
        guard shadow || cornerRadius > 0 else { return img }
        let w = CGFloat(img.width), h = CGFloat(img.height)
        let pad: CGFloat = shadow ? max(32, (min(w, h) * 0.06).rounded()) : 0
        let W = Int(w + pad * 2), H = Int(h + pad * 2)
        guard let ctx = makeContext(width: W, height: H) else { return img }
        if let background {
            ctx.setFillColor(background)
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        }
        let rect = CGRect(x: pad, y: pad, width: w, height: h)
        let radius = min(cornerRadius * 2, min(w, h) / 4)   // 2x captures: scale the radius
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        ctx.saveGState()
        if shadow {
            ctx.setShadow(offset: CGSize(width: 0, height: -pad * 0.3), blur: pad * 0.8,
                          color: CGColor(gray: 0, alpha: 0.5))
        }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(path)
        ctx.clip()
        ctx.draw(img, in: rect)
        ctx.endTransparencyLayer()
        ctx.restoreGState()

        if shadow {
            // Subtle border like macOS windows.
            ctx.addPath(path)
            ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.18))
            ctx.setLineWidth(max(1, w / 1800))
            ctx.strokePath()
        }
        return ctx.makeImage() ?? img
    }

    static func flatten(_ img: CGImage, background: CGColor) -> CGImage? {
        guard let ctx = makeContext(width: img.width, height: img.height) else { return nil }
        let r = CGRect(x: 0, y: 0, width: img.width, height: img.height)
        ctx.setFillColor(background)
        ctx.fill(r)
        ctx.draw(img, in: r)
        return ctx.makeImage()
    }

    // MARK: - Composites (comparison / timeline)

    struct Panel {
        var image: CGImage
        var title: String
        var subtitle: String
        var accent: CGColor
    }

    static func drawText(_ s: String, in r: CGRect, font: NSFont, color: NSColor) {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
        str.draw(with: r, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    static func compose(_ panels: [Panel], horizontal: Bool, connectors: Bool) -> CGImage? {
        guard !panels.isEmpty else { return nil }
        let maxW = CGFloat(panels.map(\.image.width).max() ?? 1)
        let maxH = CGFloat(panels.map(\.image.height).max() ?? 1)
        let font = max(18, (max(maxW, maxH) * 0.02).rounded())
        let header = (font * 2.9).rounded()
        let margin = (font * 1.4).rounded()
        let gap = connectors ? (font * 3.4).rounded() : margin
        let minPanelW = font * 18

        var frames: [CGRect] = []
        var cursor = margin
        for p in panels {
            let w = max(CGFloat(p.image.width), minPanelW), h = CGFloat(p.image.height)
            if horizontal {
                frames.append(CGRect(x: cursor, y: margin, width: w, height: header + h))
                cursor += w + gap
            } else {
                frames.append(CGRect(x: margin, y: cursor, width: max(maxW, minPanelW), height: header + h))
                cursor += header + h + gap
            }
        }
        cursor -= gap
        let W = horizontal ? cursor + margin : max(maxW, minPanelW) + margin * 2
        let H = horizontal ? header + maxH + margin * 2 : cursor + margin

        guard let ctx = makeContext(width: Int(W), height: Int(H)) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: 0.95, green: 0.95, blue: 0.96, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

        withFlipped(ctx, height: H) {
            for (i, p) in panels.enumerated() {
                let f = frames[i]
                let iw = CGFloat(p.image.width), ih = CGFloat(p.image.height)
                let headerRect = CGRect(x: f.minX, y: f.minY, width: f.width, height: header)
                let radius = font * 0.45

                // Card shadow
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: -font * 0.15), blur: font * 0.8, color: CGColor(gray: 0, alpha: 0.18))
                ctx.setFillColor(.white)
                ctx.addPath(CGPath(roundedRect: f, cornerWidth: radius, cornerHeight: radius, transform: nil))
                ctx.fillPath()
                ctx.restoreGState()

                // Header
                ctx.saveGState()
                ctx.addPath(CGPath(roundedRect: f, cornerWidth: radius, cornerHeight: radius, transform: nil))
                ctx.clip()
                ctx.setFillColor(p.accent)
                ctx.fill(headerRect)
                ctx.restoreGState()

                let inset = font * 0.7
                drawText(p.title, in: CGRect(x: f.minX + inset, y: f.minY + font * 0.35, width: f.width - inset * 2, height: font * 1.3),
                         font: .systemFont(ofSize: font, weight: .bold), color: .white)
                drawText(p.subtitle, in: CGRect(x: f.minX + inset, y: f.minY + font * 1.65, width: f.width - inset * 2, height: font * 1.1),
                         font: .systemFont(ofSize: font * 0.72, weight: .medium), color: NSColor.white.withAlphaComponent(0.88))

                let imgRect = CGRect(x: f.minX + (f.width - iw) / 2, y: f.minY + header, width: iw, height: ih)
                drawImage(ctx, p.image, in: imgRect)

                if connectors, i < panels.count - 1 {
                    let next = frames[i + 1]
                    let arrowColor = CGColor(gray: 0.45, alpha: 1)
                    if horizontal {
                        let y = f.minY + header + min(ih, CGFloat(panels[i + 1].image.height)) / 2
                        strokeArrow(ctx, from: CGPoint(x: f.maxX + gap * 0.18, y: y),
                                    to: CGPoint(x: next.minX - gap * 0.18, y: y), width: font * 0.22, color: arrowColor)
                    } else {
                        let x = f.midX
                        strokeArrow(ctx, from: CGPoint(x: x, y: f.maxY + gap * 0.18),
                                    to: CGPoint(x: x, y: next.minY - gap * 0.18), width: font * 0.22, color: arrowColor)
                    }
                }
            }
        }
        return ctx.makeImage()
    }

    // MARK: - Slider (split)

    static func drawBadge(_ text: String, at p: CGPoint, alignRight: Bool, font: CGFloat, color: CGColor, in ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: font, weight: .bold), .foregroundColor: NSColor.white]
        let s = NSAttributedString(string: text, attributes: attrs)
        let sz = s.size()
        let padX = font * 0.6, padY = font * 0.3
        let w = sz.width + padX * 2, h = sz.height + padY * 2
        let r = CGRect(x: alignRight ? p.x - w : p.x, y: p.y, width: w, height: h)
        ctx.setFillColor(color)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: h / 2, cornerHeight: h / 2, transform: nil))
        ctx.fillPath()
        s.draw(at: CGPoint(x: r.minX + padX, y: r.minY + padY))
    }

    static func split(base: CGImage, change: CGImage, fraction: CGFloat, baseLabel: String, changeLabel: String) -> CGImage? {
        let W = CGFloat(max(base.width, change.width)), H = CGFloat(max(base.height, change.height))
        guard let ctx = makeContext(width: Int(W), height: Int(H)) else { return nil }
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let x = (W * fraction).rounded()
        let font = max(16, (max(W, H) * 0.016).rounded())
        withFlipped(ctx, height: H) {
            drawImage(ctx, base, in: CGRect(x: 0, y: 0, width: CGFloat(base.width), height: CGFloat(base.height)))
            ctx.saveGState()
            ctx.clip(to: CGRect(x: x, y: 0, width: W - x, height: H))
            ctx.setFillColor(.white)
            ctx.fill(CGRect(x: x, y: 0, width: W - x, height: H))
            drawImage(ctx, change, in: CGRect(x: 0, y: 0, width: CGFloat(change.width), height: CGFloat(change.height)))
            ctx.restoreGState()

            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: font * 0.4, color: CGColor(gray: 0, alpha: 0.6))
            ctx.setFillColor(.white)
            ctx.fill(CGRect(x: x - max(2, font / 8), y: 0, width: max(4, font / 4), height: H))
            ctx.restoreGState()

            drawBadge(baseLabel, at: CGPoint(x: font * 0.8, y: font * 0.8), alignRight: false, font: font,
                      color: CGColor(srgbRed: 0.18, green: 0.40, blue: 0.85, alpha: 0.95), in: ctx)
            drawBadge(changeLabel, at: CGPoint(x: W - font * 0.8, y: font * 0.8), alignRight: true, font: font,
                      color: CGColor(srgbRed: 0.85, green: 0.20, blue: 0.22, alpha: 0.95), in: ctx)
        }
        return ctx.makeImage()
    }

    // MARK: - Difference detection

    struct DiffResult {
        var image: CGImage
        var regions: [CGRect]
        var changedRatio: Double
    }

    private static func rgba(_ img: CGImage, width W: Int, height H: Int) -> [UInt8] {
        var buf = [UInt8](repeating: 255, count: W * H * 4)
        buf.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(data: ptr.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                                      space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.setFillColor(.white)
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            ctx.draw(img, in: CGRect(x: 0, y: H - img.height, width: img.width, height: img.height))
        }
        return buf
    }

    /// Compares `change` against `base` (top-left aligned) and highlights the modified regions.
    static func highlightDifferences(base: CGImage, change: CGImage, threshold: Int, tint: Bool) -> DiffResult? {
        let W = max(base.width, change.width), H = max(base.height, change.height)
        let a = rgba(base, width: W, height: H)
        var out = rgba(change, width: W, height: H)
        let cell = 8
        let gw = (W + cell - 1) / cell, gh = (H + cell - 1) / cell
        var counts = [Int32](repeating: 0, count: gw * gh)
        var changed = 0

        a.withUnsafeBufferPointer { pa in
            out.withUnsafeMutableBufferPointer { pb in
                for y in 0..<H {
                    let row = y * W
                    let crow = (y / cell) * gw
                    for x in 0..<W {
                        let i = (row + x) * 4
                        let dr = abs(Int(pa[i]) - Int(pb[i]))
                        let dg = abs(Int(pa[i + 1]) - Int(pb[i + 1]))
                        let db = abs(Int(pa[i + 2]) - Int(pb[i + 2]))
                        if max(dr, max(dg, db)) > threshold {
                            changed += 1
                            counts[crow + x / cell] += 1
                            if tint {
                                pb[i] = UInt8((Int(pb[i]) + 255 * 2) / 3)
                                pb[i + 1] = UInt8(Int(pb[i + 1]) / 3)
                                pb[i + 2] = UInt8(Int(pb[i + 2]) / 3)
                            }
                        }
                    }
                }
            }
        }

        // Changed cells (ignoring 1-pixel noise), dilated to group nearby text.
        let grid = counts.map { $0 >= 2 }
        let d = 2
        var dil = [Bool](repeating: false, count: gw * gh)
        for cy in 0..<gh {
            for cx in 0..<gw where grid[cy * gw + cx] {
                for yy in max(0, cy - d)...min(gh - 1, cy + d) {
                    for xx in max(0, cx - d)...min(gw - 1, cx + d) { dil[yy * gw + xx] = true }
                }
            }
        }
        var visited = [Bool](repeating: false, count: gw * gh)
        var regions: [CGRect] = []
        for start in 0..<(gw * gh) where dil[start] && !visited[start] {
            var stack = [start]
            visited[start] = true
            var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
            while let c = stack.popLast() {
                let cx = c % gw, cy = c / gw
                if grid[c] {
                    minX = min(minX, cx); maxX = max(maxX, cx)
                    minY = min(minY, cy); maxY = max(maxY, cy)
                }
                for (nx, ny) in [(cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)]
                where nx >= 0 && ny >= 0 && nx < gw && ny < gh {
                    let n = ny * gw + nx
                    if dil[n] && !visited[n] { visited[n] = true; stack.append(n) }
                }
            }
            if maxX >= 0 {
                let r = CGRect(x: minX * cell, y: minY * cell, width: (maxX - minX + 1) * cell, height: (maxY - minY + 1) * cell)
                regions.append(r.insetBy(dx: -6, dy: -6).intersection(CGRect(x: 0, y: 0, width: W, height: H)))
            }
        }
        regions.sort { $0.width * $0.height > $1.width * $1.height }
        if regions.count > 150 { regions = Array(regions.prefix(150)) }

        let image: CGImage? = out.withUnsafeMutableBytes { ptr -> CGImage? in
            guard let ctx = CGContext(data: ptr.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                                      space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            let lw = CGFloat(max(3, W / 500))
            withFlipped(ctx, height: CGFloat(H)) {
                ctx.setStrokeColor(CGColor(srgbRed: 0.95, green: 0.1, blue: 0.15, alpha: 1))
                ctx.setLineWidth(lw)
                for r in regions { ctx.stroke(r) }
            }
            return ctx.makeImage()
        }
        guard let image else { return nil }
        return DiffResult(image: image, regions: regions, changedRatio: Double(changed) / Double(W * H))
    }
}
