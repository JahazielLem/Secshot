// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import AppKit
import SwiftUI

// MARK: - Preferences

enum Prefs {
    static let namePrefix = "namePrefix"
    static let digits = "counterDigits"
    static let shadow = "shadowEnabled"
    static let cornerRadius = "cornerRadius"
    static let transparentBG = "transparentBackground"
    static let playSound = "playSound"
    static let hideDuringCapture = "hideDuringCapture"
    static let openEditor = "openEditorAfterCapture"
    static let copyAfterCapture = "copyAfterCapture"
    static let exportFormat = "exportFormat"
    static let retinaDPI = "retinaDPI"
    static let defaultRedaction = "defaultRedaction"
    static let disabledDetectors = "disabledDetectors"
    static let captureBar = "captureBarEnabled"
    static let captureBarPosition = "captureBarPosition"
    static let captureBarTimer = "captureBarTimer"
    static let captureBarX = "captureBarX"
    static let captureBarY = "captureBarY"

    static func register() {
        UserDefaults.standard.register(defaults: [
            namePrefix: "EVIDENCE-",
            digits: 0,
            shadow: true,
            cornerRadius: 10.0,
            transparentBG: true,
            playSound: false,
            hideDuringCapture: true,
            openEditor: true,
            copyAfterCapture: false,
            exportFormat: "png",
            retinaDPI: true,
            defaultRedaction: AnnotationKind.pixelate.rawValue,
            disabledDetectors: "",
            captureBar: true,
            captureBarPosition: "bottom",
            captureBarTimer: 0,
        ])
    }
}

// MARK: - Serializable color

struct RGBAColor: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .systemRed
        r = ns.redComponent; g = ns.greenComponent; b = ns.blueComponent; a = ns.alphaComponent
    }

    static let red = RGBAColor(r: 0.93, g: 0.16, b: 0.20)
    static let black = RGBAColor(r: 0, g: 0, b: 0)

    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    func withAlpha(_ alpha: Double) -> RGBAColor { RGBAColor(r: r, g: g, b: b, a: alpha) }
}

// MARK: - Annotations

enum AnnotationKind: String, Codable, CaseIterable {
    case rectangle, ellipse, arrow, line, text, highlight, step, pixelate, blur, redact

    var isRedaction: Bool { self == .pixelate || self == .blur || self == .redact }

    var label: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .text: return "Text"
        case .highlight: return "Highlighter"
        case .step: return "Numbered step"
        case .pixelate: return "Pixelate"
        case .blur: return "Hardened blur"
        case .redact: return "Solid redaction"
        }
    }
}

struct Annotation: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: AnnotationKind
    /// Image pixel coordinates, top-left origin.
    var start: CGPoint
    var end: CGPoint
    var color: RGBAColor
    var lineWidth: Double
    var fontSize: Double
    var text: String = ""
    var number: Int = 0
    var filled: Bool = false

    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    mutating func offset(by d: CGSize) {
        start.x += d.width; start.y += d.height
        end.x += d.width; end.y += d.height
    }
}

enum EditorTool: String, CaseIterable, Identifiable {
    case select, rectangle, ellipse, arrow, line, text, highlight, step, pixelate, blur, redact, crop

    var id: String { rawValue }
    var kind: AnnotationKind? { AnnotationKind(rawValue: rawValue) }

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .text: return "textformat"
        case .highlight: return "highlighter"
        case .step: return "1.circle.fill"
        case .pixelate: return "squareshape.split.3x3"
        case .blur: return "drop.halffull"
        case .redact: return "rectangle.fill"
        case .crop: return "crop"
        }
    }

    var label: String {
        switch self {
        case .select: return "Select / move (V)"
        case .crop: return "Crop (C)"
        default: return kind?.label ?? rawValue
        }
    }
}

// MARK: - Capture

struct CaptureItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var fileName: String
    var createdAt: Date
    var mode: String
    /// SHA-256 of the original PNG at capture time (evidence integrity).
    var sha256: String
    var pixelWidth: Int
    var pixelHeight: Int
    var annotations: [Annotation] = []
    var crop: CGRect?
    var notes: String = ""

    var modeLabel: String {
        switch mode {
        case "region": return "Region"
        case "window": return "Window"
        case "fullscreen": return "Full screen"
        case "comparison": return "Comparison"
        case "timeline": return "Timeline"
        case "import": return "Imported"
        case "derived": return "Derived"
        default: return mode
        }
    }

    var isEdited: Bool { !annotations.isEmpty || crop != nil }
}

enum Fmt {
    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEEE, MMMM d, yyyy"
        return f
    }()

    static func dayTitle(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return day.string(from: date)
    }
}

/// The Command Line Tools do not ship the `SwiftUIMacros` plugin that newer SDKs use for `@State`.
/// This alias points at the classic property wrapper so the app builds without Xcode.
typealias ViewState<Value> = SwiftUI.State<Value>
