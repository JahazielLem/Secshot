// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import AppKit

// MARK: - Themes

struct CodeTheme: Equatable {
    var name: String
    var isLight = false
    var background: NSColor
    var foreground: NSColor
    var comment: NSColor
    var keyword: NSColor
    var string: NSColor
    var number: NSColor
    var function: NSColor
    var type: NSColor
    var attribute: NSColor
    var variable: NSColor
    var headerName: NSColor
    var prompt: NSColor
    var lineNumber: NSColor
    var output: NSColor

    var punctuation: NSColor { foreground.withAlphaComponent(0.7) }
    var highlight: NSColor { isLight ? NSColor(white: 0, alpha: 0.06) : NSColor(white: 1, alpha: 0.08) }
    var success: NSColor { isLight ? hex(0x1A7F37) : hex(0x3FB950) }
    var warning: NSColor { isLight ? hex(0x9A6700) : hex(0xE3B341) }
    var danger: NSColor { isLight ? hex(0xCF222E) : hex(0xF85149) }
    var info: NSColor { isLight ? hex(0x0969DA) : hex(0x58A6FF) }
    var redirect: NSColor { isLight ? hex(0x1B7C83) : hex(0x39C5CF) }

    func color(for kind: TokenKind) -> NSColor {
        switch kind {
        case .comment: return comment
        case .keyword: return keyword
        case .string: return string
        case .number: return number
        case .function: return function
        case .type: return type
        case .attribute: return attribute
        case .variable: return variable
        case .punctuation: return punctuation
        case .headerName: return headerName
        case .prompt: return prompt
        case .output: return output
        case .statusSuccess: return success
        case .statusRedirect: return redirect
        case .statusClientError: return warning
        case .statusServerError: return danger
        }
    }

    /// Themes shipped with SecShot. Custom and imported themes live in `CodeThemeLibrary`.
    static let builtIn: [CodeTheme] = [
        CodeTheme(name: "Terminal", background: hex(0x0C0C0C), foreground: hex(0xE6E6E6), comment: hex(0x6A737D),
                  keyword: hex(0xFF7AB2), string: hex(0xA6E22E), number: hex(0xFD971F), function: hex(0x5FD7FF),
                  type: hex(0xE6DB74), attribute: hex(0xC792EA), variable: hex(0xF78C6C), headerName: hex(0x5FD7FF),
                  prompt: hex(0x50FA7B), lineNumber: hex(0x4D4D4D), output: hex(0xBDBDBD)),
        CodeTheme(name: "Hacker Green", background: hex(0x000000), foreground: hex(0x33FF66), comment: hex(0x1E7A3A),
                  keyword: hex(0x9CFFB5), string: hex(0xC6FFD6), number: hex(0x66FF99), function: hex(0x00FF7F),
                  type: hex(0x7CFC00), attribute: hex(0x5CE68A), variable: hex(0xB2FF59), headerName: hex(0x00E676),
                  prompt: hex(0x00FF7F), lineNumber: hex(0x145A28), output: hex(0x29CC55)),
        CodeTheme(name: "Dracula", background: hex(0x282A36), foreground: hex(0xF8F8F2), comment: hex(0x6272A4),
                  keyword: hex(0xFF79C6), string: hex(0xF1FA8C), number: hex(0xBD93F9), function: hex(0x50FA7B),
                  type: hex(0x8BE9FD), attribute: hex(0x50FA7B), variable: hex(0xFFB86C), headerName: hex(0x8BE9FD),
                  prompt: hex(0x50FA7B), lineNumber: hex(0x6272A4), output: hex(0xD6D6D0)),
        CodeTheme(name: "One Dark", background: hex(0x282C34), foreground: hex(0xABB2BF), comment: hex(0x5C6370),
                  keyword: hex(0xC678DD), string: hex(0x98C379), number: hex(0xD19A66), function: hex(0x61AFEF),
                  type: hex(0xE5C07B), attribute: hex(0xD19A66), variable: hex(0xE06C75), headerName: hex(0xE06C75),
                  prompt: hex(0x98C379), lineNumber: hex(0x4B5263), output: hex(0x9DA5B4)),
        CodeTheme(name: "Monokai", background: hex(0x272822), foreground: hex(0xF8F8F2), comment: hex(0x75715E),
                  keyword: hex(0xF92672), string: hex(0xE6DB74), number: hex(0xAE81FF), function: hex(0xA6E22E),
                  type: hex(0x66D9EF), attribute: hex(0xA6E22E), variable: hex(0xFD971F), headerName: hex(0x66D9EF),
                  prompt: hex(0xA6E22E), lineNumber: hex(0x75715E), output: hex(0xCFCFC2)),
        CodeTheme(name: "Nord", background: hex(0x2E3440), foreground: hex(0xD8DEE9), comment: hex(0x616E88),
                  keyword: hex(0x81A1C1), string: hex(0xA3BE8C), number: hex(0xB48EAD), function: hex(0x88C0D0),
                  type: hex(0x8FBCBB), attribute: hex(0x8FBCBB), variable: hex(0xD08770), headerName: hex(0x88C0D0),
                  prompt: hex(0xA3BE8C), lineNumber: hex(0x4C566A), output: hex(0xC0C8D6)),
        CodeTheme(name: "Solarized Dark", background: hex(0x002B36), foreground: hex(0x93A1A1), comment: hex(0x586E75),
                  keyword: hex(0x859900), string: hex(0x2AA198), number: hex(0xD33682), function: hex(0x268BD2),
                  type: hex(0xB58900), attribute: hex(0xCB4B16), variable: hex(0x6C71C4), headerName: hex(0x268BD2),
                  prompt: hex(0x859900), lineNumber: hex(0x586E75), output: hex(0x839496)),
        CodeTheme(name: "GitHub Light", isLight: true, background: hex(0xFFFFFF), foreground: hex(0x24292F), comment: hex(0x6E7781),
                  keyword: hex(0xCF222E), string: hex(0x0A3069), number: hex(0x0550AE), function: hex(0x8250DF),
                  type: hex(0x953800), attribute: hex(0x116329), variable: hex(0x953800), headerName: hex(0x0550AE),
                  prompt: hex(0x116329), lineNumber: hex(0x8C959F), output: hex(0x57606A)),
        // Catppuccin (https://catppuccin.com, MIT) — official palette values.
        CodeTheme(name: "Catppuccin Mocha", background: hex(0x1E1E2E), foreground: hex(0xCDD6F4), comment: hex(0x6C7086),
                  keyword: hex(0xCBA6F7), string: hex(0xA6E3A1), number: hex(0xFAB387), function: hex(0x89B4FA),
                  type: hex(0xF9E2AF), attribute: hex(0x94E2D5), variable: hex(0xF38BA8), headerName: hex(0x74C7EC),
                  prompt: hex(0xA6E3A1), lineNumber: hex(0x45475A), output: hex(0xA6ADC8)),
        CodeTheme(name: "Catppuccin Macchiato", background: hex(0x24273A), foreground: hex(0xCAD3F5), comment: hex(0x6E738D),
                  keyword: hex(0xC6A0F6), string: hex(0xA6DA95), number: hex(0xF5A97F), function: hex(0x8AADF4),
                  type: hex(0xEED49F), attribute: hex(0x8BD5CA), variable: hex(0xED8796), headerName: hex(0x7DC4E4),
                  prompt: hex(0xA6DA95), lineNumber: hex(0x494D64), output: hex(0xA5ADCB)),
        CodeTheme(name: "Catppuccin Frappé", background: hex(0x303446), foreground: hex(0xC6D0F5), comment: hex(0x737994),
                  keyword: hex(0xCA9EE6), string: hex(0xA6D189), number: hex(0xEF9F76), function: hex(0x8CAAEE),
                  type: hex(0xE5C890), attribute: hex(0x81C8BE), variable: hex(0xE78284), headerName: hex(0x85C1DC),
                  prompt: hex(0xA6D189), lineNumber: hex(0x51576D), output: hex(0xA5ADCE)),
        CodeTheme(name: "Catppuccin Latte", isLight: true, background: hex(0xEFF1F5), foreground: hex(0x4C4F69), comment: hex(0x9CA0B0),
                  keyword: hex(0x8839EF), string: hex(0x40A02B), number: hex(0xFE640B), function: hex(0x1E66F5),
                  type: hex(0xDF8E1D), attribute: hex(0x179299), variable: hex(0xD20F39), headerName: hex(0x209FB5),
                  prompt: hex(0x40A02B), lineNumber: hex(0xBCC0CC), output: hex(0x6C6F85)),
    ]

    static func named(_ name: String) -> CodeTheme { CodeThemeLibrary.theme(named: name) }

    /// Editable color roles, in display order (used by import, export and the theme editor).
    static let roles: [(key: String, label: String, path: WritableKeyPath<CodeTheme, NSColor>)] = [
        ("background", "Background", \.background), ("foreground", "Text", \.foreground),
        ("comment", "Comments", \.comment), ("keyword", "Keywords", \.keyword),
        ("string", "Strings / URLs", \.string), ("number", "Numbers", \.number),
        ("function", "Functions / commands", \.function), ("type", "Types / HTTP version", \.type),
        ("attribute", "Attributes / flags / directives", \.attribute), ("variable", "Variables / constants", \.variable),
        ("headerName", "HTTP header names", \.headerName), ("prompt", "Terminal prompt", \.prompt),
        ("output", "Terminal output", \.output), ("lineNumber", "Line numbers", \.lineNumber),
    ]
}

func hex(_ v: Int, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
}

// MARK: - Frames and backgrounds

enum CodeFrame: String, CaseIterable, Identifiable {
    case macOS, terminal, plain, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .macOS: return "macOS window"
        case .terminal: return "Terminal"
        case .plain: return "Background only"
        case .none: return "No frame"
        }
    }
    var hasTitleBar: Bool { self == .macOS || self == .terminal }
}

enum CodeBackground: String, CaseIterable, Identifiable {
    case none, ocean, sunset, candy, midnight, forest, steel, white, black
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Transparent"
        case .ocean: return "Ocean"
        case .sunset: return "Sunset"
        case .candy: return "Candy"
        case .midnight: return "Midnight"
        case .forest: return "Forest"
        case .steel: return "Steel"
        case .white: return "White"
        case .black: return "Black"
        }
    }
    var colors: [NSColor] {
        switch self {
        case .none: return []
        case .ocean: return [hex(0x00C6FF), hex(0x0072FF)]
        case .sunset: return [hex(0xFF5F6D), hex(0xFFC371)]
        case .candy: return [hex(0xA18CD1), hex(0xFBC2EB)]
        case .midnight: return [hex(0x0F2027), hex(0x2C5364)]
        case .forest: return [hex(0x134E5E), hex(0x71B280)]
        case .steel: return [hex(0x8E9EAB), hex(0xEEF2F3)]
        case .white: return [hex(0xFFFFFF)]
        case .black: return [hex(0x000000)]
        }
    }
}

// MARK: - HTTP security header analysis

struct HeaderFinding {
    enum Level { case good, warning, danger, info }
    var level: Level
    var header: String
    var message: String
}

enum HTTPSecurityAnalyzer {
    struct Result {
        var perLine: [Int: HeaderFinding.Level] = [:]
        var findings: [HeaderFinding] = []
    }

    static func analyze(_ code: HighlightedCode, redactionMarker: String = "") -> Result {
        guard code.language == .http else { return Result() }
        let lines = code.lines
        guard let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return Result() }
        let isResponse = lines[first].hasPrefix("HTTP/")
        let end = (code.httpBodyStart.map { $0 - 1 }) ?? lines.count

        var headers: [(line: Int, name: String, value: String)] = []
        if first + 1 < end {
            for n in (first + 1)..<end {
                let line = lines[n]
                guard let colon = line.dropFirst().firstIndex(of: ":") else { continue }
                let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                headers.append((n, name, value))
            }
        }
        var r = Result()
        func mark(_ line: Int, _ level: HeaderFinding.Level, _ header: String, _ msg: String?) {
            if let current = r.perLine[line] {
                r.perLine[line] = worse(current, level)
            } else {
                r.perLine[line] = level
            }
            if let msg { r.findings.append(HeaderFinding(level: level, header: header, message: msg)) }
        }
        let names = Set(headers.map(\.name))

        if !isResponse {
            for h in headers where ["cookie", "authorization", "proxy-authorization", "x-api-key"].contains(h.name)
                && (redactionMarker.isEmpty || !h.value.contains(redactionMarker)) {
                mark(h.line, .info, h.name, "Contains credentials: consider redacting before sharing.")
            }
            return r
        }

        for h in headers {
            let v = h.value.lowercased()
            switch h.name {
            case "content-security-policy", "content-security-policy-report-only":
                var issues: [String] = []
                if h.name.hasSuffix("report-only") { issues.append("Report-Only: the policy is not enforced") }
                let unsafe = ["'unsafe-inline'", "'unsafe-eval'", "'unsafe-hashes'"].filter { v.contains($0) }
                if !unsafe.isEmpty { issues.append("allows " + unsafe.joined(separator: ", ")) }
                // Broad script sources: check script-src, or default-src when script-src is absent.
                let directives = Dictionary(v.split(separator: ";").compactMap { part -> (String, [String])? in
                    let words = part.split(separator: " ").map(String.init)
                    guard let name = words.first else { return nil }
                    return (name, Array(words.dropFirst()))
                }, uniquingKeysWith: { a, _ in a })
                let scriptSources = directives["script-src"] ?? directives["default-src"] ?? []
                let broad = scriptSources.filter { ["*", "https:", "http:", "data:", "blob:"].contains($0) }
                if !broad.isEmpty { issues.append("script sources too broad (" + broad.joined(separator: ", ") + ")") }
                if issues.isEmpty { mark(h.line, .good, h.name, nil) } else { mark(h.line, .warning, h.name, issues.joined(separator: "; ") + ".") }
            case "strict-transport-security":
                let age = v.range(of: #"max-age=(\d+)"#, options: .regularExpression)
                    .flatMap { Int(v[$0].dropFirst("max-age=".count)) } ?? 0
                var issues: [String] = []
                if age < 31_536_000 { issues.append("max-age \(age) is below 1 year (31536000)") }
                if !v.contains("includesubdomains") { issues.append("missing includeSubDomains") }
                if issues.isEmpty { mark(h.line, .good, h.name, nil) } else { mark(h.line, .warning, h.name, issues.joined(separator: "; ") + ".") }
            case "x-content-type-options":
                v == "nosniff" ? mark(h.line, .good, h.name, nil) : mark(h.line, .warning, h.name, "Should be \"nosniff\".")
            case "x-frame-options":
                ["deny", "sameorigin"].contains(v) ? mark(h.line, .good, h.name, nil)
                    : mark(h.line, .warning, h.name, "Use DENY or SAMEORIGIN.")
            case "referrer-policy":
                ["unsafe-url", "no-referrer-when-downgrade"].contains(v)
                    ? mark(h.line, .warning, h.name, "\"\(h.value)\" can leak full URLs.") : mark(h.line, .good, h.name, nil)
            case "permissions-policy", "cross-origin-opener-policy", "cross-origin-resource-policy", "cross-origin-embedder-policy":
                mark(h.line, .good, h.name, nil)
            case "access-control-allow-origin":
                if v == "*" {
                    let creds = headers.contains { $0.name == "access-control-allow-credentials" && $0.value.lowercased() == "true" }
                    mark(h.line, creds ? .danger : .warning, h.name,
                         creds ? "Wildcard origin with credentials." : "Wildcard origin: any site can read the response.")
                }
            case "set-cookie":
                var missing: [String] = []
                if !v.contains("secure") { missing.append("Secure") }
                if !v.contains("httponly") { missing.append("HttpOnly") }
                if !v.contains("samesite") { missing.append("SameSite") }
                let cookie = String(h.value.prefix { $0 != "=" })
                if missing.isEmpty { mark(h.line, .good, h.name, nil) }
                else { mark(h.line, .warning, "set-cookie \(cookie)", "missing " + missing.joined(separator: ", ") + ".") }
            case "server", "x-powered-by", "x-aspnet-version", "x-aspnetmvc-version", "x-generator":
                mark(h.line, .info, h.name, "Discloses software: \"\(h.value)\".")
            default:
                break
            }
        }

        // Missing recommended headers.
        let cspValue = headers.first { $0.name == "content-security-policy" }?.value.lowercased() ?? ""
        var missing: [String] = []
        if !names.contains("strict-transport-security") { missing.append("Strict-Transport-Security") }
        if !names.contains("content-security-policy") {
            missing.append(names.contains("content-security-policy-report-only")
                           ? "Content-Security-Policy (only Report-Only is present)" : "Content-Security-Policy")
        }
        if !names.contains("x-content-type-options") { missing.append("X-Content-Type-Options") }
        if !names.contains("x-frame-options") && !cspValue.contains("frame-ancestors") { missing.append("X-Frame-Options or CSP frame-ancestors") }
        if !names.contains("referrer-policy") { missing.append("Referrer-Policy") }
        if !names.contains("permissions-policy") { missing.append("Permissions-Policy") }
        for m in missing { r.findings.append(HeaderFinding(level: .danger, header: "missing", message: m)) }

        // Most severe first.
        let order: [HeaderFinding.Level: Int] = [.danger: 0, .warning: 1, .info: 2, .good: 3]
        r.findings.sort { (order[$0.level] ?? 9) < (order[$1.level] ?? 9) }
        return r
    }

    private static func worse(_ a: HeaderFinding.Level, _ b: HeaderFinding.Level) -> HeaderFinding.Level {
        let rank: [HeaderFinding.Level: Int] = [.good: 0, .info: 1, .warning: 2, .danger: 3]
        return (rank[a] ?? 0) >= (rank[b] ?? 0) ? a : b
    }
}

// MARK: - Options

struct CodeShotOptions: Equatable {
    var code: String
    var language: CodeLanguage = .auto
    var theme: CodeTheme = CodeTheme.builtIn[2]
    var frame: CodeFrame = .macOS
    var background: CodeBackground = .ocean
    var padding: Double = 48
    var fontSize: Double = 14
    var lineNumbers = true
    var title = ""
    var highlightLines = ""
    var maxColumns = 100
    var securityAnalysis = true
    /// Diff marks per line index (0-based), used by comparisons.
    var lineMarks: [Int: DiffMark] = [:]
    /// Changed character ranges inside modified lines.
    var emphasis: [Int: [NSRange]] = [:]
    /// Redaction marker (e.g. "[REDACTED]") drawn as a red badge wherever it appears.
    var redactionMarker = "[REDACTED]"
    var shadow = true
    var scale: CGFloat = 2

    /// Parses "1, 4-6" into line numbers (1-based).
    var highlightedLineSet: Set<Int> {
        var set = Set<Int>()
        for part in highlightLines.split(whereSeparator: { $0 == "," || $0 == " " }) {
            let bounds = part.split(separator: "-").compactMap { Int($0) }
            if bounds.count == 1 { set.insert(bounds[0]) }
            else if bounds.count == 2, bounds[0] <= bounds[1], bounds[1] - bounds[0] < 10_000 { set.formUnion(bounds[0]...bounds[1]) }
        }
        return set
    }
}

// MARK: - Renderer

enum CodeShotRenderer {
    struct Output {
        var image: CGImage
        var language: CodeLanguage
        var findings: [HeaderFinding]
    }

    static func defaultTitle(for code: HighlightedCode) -> String {
        switch code.language {
        case .http:
            let first = code.lines.first { !$0.isEmpty } ?? ""
            return first.hasPrefix("HTTP/") ? "HTTP Response" : "HTTP Request"
        case .shell: return "Terminal"
        case .json: return "response.json"
        case .python: return "script.py"
        case .javascript: return "script.js"
        case .sql: return "query.sql"
        case .xml: return "document.xml"
        case .clike: return "source"
        default: return ""
        }
    }

    static func render(_ o: CodeShotOptions) -> Output? {
        let code = CodeHighlighter.highlight(o.code, language: o.language)
        let theme = o.theme
        let analysis = o.securityAnalysis ? HTTPSecurityAnalyzer.analyze(code, redactionMarker: o.redactionMarker) : .init()
        let s = o.scale
        let font = NSFont.monospacedSystemFont(ofSize: o.fontSize * s, weight: .regular)
        let boldFont = NSFont.monospacedSystemFont(ofSize: o.fontSize * s, weight: .semibold)
        let charW = ("M" as NSString).size(withAttributes: [.font: font]).width

        // Geometry
        let longest = code.lines.map { $0.count }.max() ?? 1
        let cols = max(24, min(max(o.maxColumns, 24), max(longest, 24)))
        let codeW = ceil(CGFloat(cols) * charW)
        let digits = String(max(code.lines.count, 1)).count
        let gutterW = o.lineNumbers ? CGFloat(digits + 2) * charW : 0
        let showDiff = !o.lineMarks.isEmpty
        let hasMarkers = showDiff || !analysis.perLine.isEmpty
        let markerW: CGFloat = hasMarkers ? (showDiff ? 18 : 10) * s : 0
        let pad: CGFloat = (o.frame == .none ? 16 : 22) * s
        let titleH: CGFloat = o.frame.hasTitleBar ? 34 * s : 0

        // Lines
        let highlighted = o.highlightedLineSet
        var blocks: [(attr: NSAttributedString, height: CGFloat)] = []
        let lineHeightMultiple: CGFloat = 1.25
        let emptyHeight = ceil(NSAttributedString(string: " ", attributes: [.font: font, .paragraphStyle: paragraph(lineHeightMultiple, 0)])
            .boundingRect(with: CGSize(width: codeW, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
        for (n, line) in code.lines.enumerated() {
            // Wrapped HTTP header values are indented under the value.
            var indent: CGFloat = 0
            if code.language == .http, (code.httpBodyStart.map { n < $0 } ?? true),
               let colon = line.firstIndex(of: ":"), line.first != " " {
                indent = CGFloat(min(line.distance(from: line.startIndex, to: colon) + 2, 24)) * charW
            }
            let attr = NSMutableAttributedString(string: line, attributes: [
                .font: font, .foregroundColor: theme.foreground, .paragraphStyle: paragraph(lineHeightMultiple, indent),
            ])
            for t in code.tokens[n] where NSMaxRange(t.range) <= attr.length {
                attr.addAttribute(.foregroundColor, value: theme.color(for: t.kind), range: t.range)
                if t.kind == .headerName || t.kind == .prompt || t.kind == .statusSuccess || t.kind == .statusClientError
                    || t.kind == .statusServerError || t.kind == .statusRedirect {
                    attr.addAttribute(.font, value: boldFont, range: t.range)
                }
            }
            if !o.redactionMarker.isEmpty {
                let ns = line as NSString
                var search = NSRange(location: 0, length: ns.length)
                while true {
                    let r = ns.range(of: o.redactionMarker, options: [], range: search)
                    guard r.location != NSNotFound, r.length > 0 else { break }
                    attr.addAttributes([.foregroundColor: theme.danger, .font: boldFont,
                                        .backgroundColor: theme.danger.withAlphaComponent(theme.isLight ? 0.12 : 0.2)], range: r)
                    let next = NSMaxRange(r)
                    search = NSRange(location: next, length: ns.length - next)
                }
            }
            if let mark = o.lineMarks[n] {
                let c = mark == .added ? theme.success : theme.danger
                for r in o.emphasis[n] ?? [] where NSMaxRange(r) <= attr.length {
                    attr.addAttribute(.backgroundColor, value: c.withAlphaComponent(theme.isLight ? 0.28 : 0.38), range: r)
                }
            }
            let h = line.isEmpty ? emptyHeight
                : ceil(attr.boundingRect(with: CGSize(width: codeW, height: .greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
            blocks.append((attr, max(h, emptyHeight)))
        }

        // Findings footer
        let footer = footerText(analysis.findings, theme: theme, scale: s, fontSize: o.fontSize)
        let footerW = markerW + gutterW + codeW
        let footerH: CGFloat = footer.map {
            ceil($0.boundingRect(with: CGSize(width: footerW, height: .greatestFiniteMagnitude),
                                 options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + pad
        } ?? 0

        let windowW = ceil(pad * 2 + markerW + gutterW + codeW)
        let windowH = ceil(titleH + pad * 2 + blocks.reduce(0) { $0 + $1.height } + footerH)
        let hasBackground = o.background != .none
        let outer: CGFloat = hasBackground ? CGFloat(o.padding) * s : (o.shadow && o.frame != .none ? 28 * s : 0)
        let W = Int(windowW + outer * 2), H = Int(windowH + outer * 2)
        guard W > 0, H > 0, W < 16_000, H < 30_000, let ctx = Renderer.makeContext(width: W, height: H) else { return nil }

        Renderer.withFlipped(ctx, height: CGFloat(H)) {
            let full = CGRect(x: 0, y: 0, width: W, height: H)
            // Outer background
            let bg = o.background.colors
            if bg.count == 1 {
                ctx.setFillColor(bg[0].cgColor)
                ctx.fill(full)
            } else if bg.count > 1,
                      let g = CGGradient(colorsSpace: Renderer.srgb, colors: bg.map(\.cgColor) as CFArray, locations: nil) {
                ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: full.maxX, y: full.maxY), options: [])
            }

            let win = CGRect(x: outer, y: outer, width: windowW, height: windowH)
            let radius: CGFloat = o.frame == .none ? 0 : (o.frame == .terminal ? 8 : 12) * s
            let path = CGPath(roundedRect: win, cornerWidth: radius, cornerHeight: radius, transform: nil)

            // Window body with shadow
            ctx.saveGState()
            if o.shadow && o.frame != .none {
                ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 30 * s, color: CGColor(gray: 0, alpha: 0.45))
            }
            ctx.addPath(path)
            ctx.setFillColor(theme.background.cgColor)
            ctx.fillPath()
            ctx.restoreGState()

            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()

            // Title bar
            if o.frame.hasTitleBar {
                let bar = CGRect(x: win.minX, y: win.minY, width: win.width, height: titleH)
                let barColor: NSColor = o.frame == .terminal
                    ? (theme.isLight ? hex(0xE5E5E5) : hex(0x2A2A2A))
                    : theme.background.blended(withFraction: 0.08, of: theme.isLight ? .black : .white) ?? theme.background
                ctx.setFillColor(barColor.cgColor)
                ctx.fill(bar)
                ctx.setFillColor((theme.isLight ? NSColor(white: 0, alpha: 0.1) : NSColor(white: 0, alpha: 0.35)).cgColor)
                ctx.fill(CGRect(x: bar.minX, y: bar.maxY - s, width: bar.width, height: s))
                let lights = [hex(0xFF5F57), hex(0xFEBC2E), hex(0x28C840)]
                for (k, c) in lights.enumerated() {
                    let d = 12 * s
                    ctx.setFillColor(c.cgColor)
                    ctx.fillEllipse(in: CGRect(x: bar.minX + 14 * s + CGFloat(k) * 20 * s, y: bar.midY - d / 2, width: d, height: d))
                }
                let title = o.title.isEmpty ? defaultTitle(for: code) : o.title
                let titleFont = o.frame == .terminal
                    ? NSFont.monospacedSystemFont(ofSize: 12 * s, weight: .medium)
                    : NSFont.systemFont(ofSize: 12.5 * s, weight: .semibold)
                let t = NSAttributedString(string: title, attributes: [
                    .font: titleFont, .foregroundColor: theme.foreground.withAlphaComponent(0.65),
                ])
                let ts = t.size()
                let maxTitleW = bar.width - 100 * s * 2
                t.draw(with: CGRect(x: bar.midX - min(ts.width, maxTitleW) / 2, y: bar.midY - ts.height / 2,
                                    width: min(ts.width, maxTitleW), height: ts.height),
                       options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            }

            // Code
            var y = win.minY + titleH + pad
            let codeX = win.minX + pad + markerW + gutterW
            for (n, block) in blocks.enumerated() {
                let lineNo = n + 1
                if highlighted.contains(lineNo) {
                    ctx.setFillColor(theme.highlight.cgColor)
                    ctx.fill(CGRect(x: win.minX, y: y, width: win.width, height: block.height))
                    ctx.setFillColor(theme.keyword.withAlphaComponent(0.9).cgColor)
                    ctx.fill(CGRect(x: win.minX, y: y, width: 3 * s, height: block.height))
                }
                if let mark = o.lineMarks[n] {
                    let c = mark == .added ? theme.success : theme.danger
                    ctx.setFillColor(c.withAlphaComponent(theme.isLight ? 0.10 : 0.15).cgColor)
                    ctx.fill(CGRect(x: win.minX, y: y, width: win.width, height: block.height))
                    let sign = NSAttributedString(string: mark == .added ? "+" : "−", attributes: [.font: boldFont, .foregroundColor: c])
                    let ss = sign.size()
                    sign.draw(at: CGPoint(x: win.minX + pad + (markerW - ss.width) / 2 - 2 * s, y: y + (emptyHeight - ss.height) / 2))
                }
                if !showDiff, let level = analysis.perLine[n] {
                    ctx.setFillColor(color(level, theme).cgColor)
                    let mark = CGRect(x: win.minX + pad, y: y + 3 * s, width: 4 * s, height: block.height - 6 * s)
                    ctx.addPath(CGPath(roundedRect: mark, cornerWidth: 2 * s, cornerHeight: 2 * s, transform: nil))
                    ctx.fillPath()
                }
                if o.lineNumbers {
                    let num = NSAttributedString(string: "\(lineNo)", attributes: [
                        .font: font, .foregroundColor: highlighted.contains(lineNo) ? theme.foreground : theme.lineNumber,
                        .paragraphStyle: paragraph(lineHeightMultiple, 0, alignment: .right),
                    ])
                    num.draw(with: CGRect(x: win.minX + pad + markerW, y: y, width: gutterW - charW * 1.5, height: block.height),
                             options: [.usesLineFragmentOrigin, .usesFontLeading])
                }
                block.attr.draw(with: CGRect(x: codeX, y: y, width: codeW, height: block.height),
                                options: [.usesLineFragmentOrigin, .usesFontLeading])
                y += block.height
            }

            // Footer
            if let footer {
                y += pad * 0.5
                ctx.setFillColor(theme.foreground.withAlphaComponent(0.12).cgColor)
                ctx.fill(CGRect(x: win.minX + pad, y: y, width: win.width - pad * 2, height: max(1, s * 0.75)))
                y += pad * 0.5
                footer.draw(with: CGRect(x: win.minX + pad, y: y, width: footerW, height: footerH),
                            options: [.usesLineFragmentOrigin, .usesFontLeading])
            }
            ctx.restoreGState()

            // Subtle border
            if o.frame != .none {
                ctx.addPath(path)
                ctx.setStrokeColor((theme.isLight ? NSColor(white: 0, alpha: 0.12) : NSColor(white: 1, alpha: 0.1)).cgColor)
                ctx.setLineWidth(s)
                ctx.strokePath()
            }
        }
        guard let image = ctx.makeImage() else { return nil }
        return Output(image: image, language: code.language, findings: analysis.findings)
    }

    private static func paragraph(_ multiple: CGFloat, _ headIndent: CGFloat, alignment: NSTextAlignment = .left) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = multiple
        p.headIndent = headIndent
        p.lineBreakMode = .byWordWrapping
        p.alignment = alignment
        return p
    }

    static func color(_ level: HeaderFinding.Level, _ theme: CodeTheme) -> NSColor {
        switch level {
        case .good: return theme.success
        case .warning: return theme.warning
        case .danger: return theme.danger
        case .info: return theme.info
        }
    }

    private static func footerText(_ findings: [HeaderFinding], theme: CodeTheme, scale s: CGFloat, fontSize: Double) -> NSAttributedString? {
        guard !findings.isEmpty else { return nil }
        let size = max(10, fontSize * 0.85) * s
        let regular = NSFont.systemFont(ofSize: size)
        let bold = NSFont.systemFont(ofSize: size, weight: .semibold)
        let mono = NSFont.monospacedSystemFont(ofSize: size, weight: .semibold)
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = 1.3
        p.headIndent = size * 1.4
        p.paragraphSpacing = size * 0.25
        let out = NSMutableAttributedString(string: "SECURITY HEADERS\n", attributes: [
            .font: NSFont.systemFont(ofSize: size * 0.85, weight: .bold),
            .foregroundColor: theme.foreground.withAlphaComponent(0.55), .kern: size * 0.08, .paragraphStyle: p,
        ])
        for (k, f) in findings.enumerated() {
            let c = color(f.level, theme)
            out.append(NSAttributedString(string: "● ", attributes: [.font: regular, .foregroundColor: c, .paragraphStyle: p]))
            if f.header == "missing" {
                out.append(NSAttributedString(string: "Missing ", attributes: [.font: bold, .foregroundColor: c, .paragraphStyle: p]))
                out.append(NSAttributedString(string: f.message, attributes: [.font: mono, .foregroundColor: theme.foreground, .paragraphStyle: p]))
            } else {
                out.append(NSAttributedString(string: f.header, attributes: [.font: mono, .foregroundColor: theme.headerName, .paragraphStyle: p]))
                out.append(NSAttributedString(string: " — " + f.message, attributes: [.font: regular, .foregroundColor: theme.foreground, .paragraphStyle: p]))
            }
            if k < findings.count - 1 { out.append(NSAttributedString(string: "\n", attributes: [.font: regular, .paragraphStyle: p])) }
        }
        return out
    }
}

// MARK: - Samples

enum CodeSamples {
    static let httpResponse = """
    HTTP/1.1 200 OK
    Date: Mon, 28 Sep 2026 17:55:08 GMT
    Content-Type: application/json
    Cache-Control: no-store
    Content-Security-Policy-Report-Only: default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' https://cdn.example.com; object-src 'none'; frame-ancestors 'none'
    Strict-Transport-Security: max-age=15552000; includeSubDomains
    X-Content-Type-Options: nosniff
    X-Frame-Options: DENY
    Referrer-Policy: strict-origin-when-cross-origin
    Set-Cookie: session=2f9c1e7a; Path=/; HttpOnly
    Server: nginx/1.18.0

    {"ok":true,"user":{"id":1337,"role":"admin"},"token":null}
    """

    static let httpRequest = """
    POST /api/v1/login HTTP/1.1
    Host: app.example.com
    User-Agent: Mozilla/5.0
    Content-Type: application/json
    Cookie: session=2f9c1e7a
    Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.e30.signature

    {"username":"admin","password":"********"}
    """

    static let shell = """
    $ nmap -sV -p 22,80,443 10.10.20.15
    Starting Nmap 7.95 ( https://nmap.org )
    PORT    STATE SERVICE VERSION
    22/tcp  open  ssh     OpenSSH 8.9p1
    80/tcp  open  http    nginx 1.18.0
    443/tcp open  https   nginx 1.18.0
    $ curl -sk https://10.10.20.15/admin | grep -i "token"
    <input type="hidden" name="csrf_token" value="a1b2c3">
    """

    static let json = """
    {
      "id": 1337,
      "email": "admin@example.com",
      "roles": ["admin", "billing"],
      "mfa": false,
      "lastLogin": null
    }
    """

    static let python = """
    import requests

    def check_idor(base, session, ids):
        # Request objects owned by other users
        for i in ids:
            r = session.get(f"{base}/api/orders/{i}", timeout=10)
            if r.status_code == 200:
                print(f"[+] Order {i} is readable")
    """

    static let compareBefore = """
    POST /api/v1/users/1337/profile HTTP/1.1
    Host: app.example.com
    Content-Type: application/json
    Cookie: session=2f9c1e7a

    {"name":"Alice","email":"alice@example.com","role":"user"}
    """

    static let compareAfter = """
    POST /api/v1/users/1337/profile HTTP/1.1
    Host: app.example.com
    Content-Type: application/json
    Cookie: session=2f9c1e7a

    {"name":"Alice","email":"alice@example.com","role":"admin"}
    """

    static let timelineSteps: [CodeStep] = [
        CodeStep(title: "Log in as a regular user", code: """
        POST /api/v1/login HTTP/1.1
        Host: app.example.com
        Content-Type: application/json

        {"username":"alice","password":"********"}
        """),
        CodeStep(title: "Role tampering accepted", code: """
        HTTP/1.1 200 OK
        Content-Type: application/json

        {"id":1337,"role":"admin"}
        """),
        CodeStep(title: "Admin endpoint reachable", code: """
        $ curl -s -b "session=2f9c1e7a" https://app.example.com/admin/users | jq length
        4821
        """),
    ]

    /// Small multi-language sample used by the theme editor preview.
    static let themePreview = """
    $ curl -s https://api.example.com/v1/users?id=42 | jq .role
    "admin"
    # Python
    def check(user_id: int) -> bool:
        return session.get(f"/api/{user_id}").status_code == 200
    HTTP/1.1 403 Forbidden
    {"error": "forbidden", "retry": false, "code": 4031}
    """

    static let all: [(String, String)] = [
        ("HTTP response", httpResponse), ("HTTP request", httpRequest),
        ("Terminal session", shell), ("JSON", json), ("Python", python),
    ]
}
