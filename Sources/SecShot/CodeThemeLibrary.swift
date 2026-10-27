// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import AppKit

/// SecShot's own theme format: a small JSON file with hex colors per role.
///
/// ```json
/// { "name": "My Theme", "type": "dark",
///   "colors": { "background": "#1E1E2E", "foreground": "#CDD6F4", "keyword": "#CBA6F7", … } }
/// ```
struct CodeThemeFile: Codable {
    var name: String
    var type: String?
    var colors: [String: String]
}

enum ThemeImportError: LocalizedError {
    case unreadable, unsupported, noColors

    var errorDescription: String? {
        switch self {
        case .unreadable: return "The file could not be read."
        case .unsupported: return "Unsupported theme format. Use a SecShot, VS Code (.json) or TextMate (.tmTheme) theme."
        case .noColors: return "The theme does not define an editor background and foreground."
        }
    }
}

/// Built-in themes plus custom/imported themes stored in
/// `~/Library/Application Support/SecShot/Themes`.
enum CodeThemeLibrary {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SecShot/Themes", isDirectory: true)
    }

    static func custom() -> [CodeTheme] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let file = try? JSONDecoder().decode(CodeThemeFile.self, from: data) else { return nil }
                return CodeTheme(file: file)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func all() -> [CodeTheme] { CodeTheme.builtIn + custom() }

    static func isCustom(_ name: String) -> Bool { !CodeTheme.builtIn.contains { $0.name == name } }

    static func theme(named name: String) -> CodeTheme {
        CodeTheme.builtIn.first { $0.name == name }
            ?? custom().first { $0.name == name }
            ?? CodeTheme.builtIn[2]
    }

    // MARK: Save / delete / export

    private static func fileURL(for name: String) -> URL {
        let safe = name.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined(separator: "_")
        return directory.appendingPathComponent("\(safe).json")
    }

    /// Saves a custom theme. Built-in names get a " (Custom)" suffix so they are never shadowed.
    @discardableResult
    static func save(_ theme: CodeTheme) throws -> CodeTheme {
        var t = theme
        if !isCustom(t.name) { t.name += " (Custom)" }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encode(t).write(to: fileURL(for: t.name), options: .atomic)
        return t
    }

    static func delete(_ name: String) {
        guard isCustom(name) else { return }
        try? FileManager.default.removeItem(at: fileURL(for: name))
    }

    static func encode(_ theme: CodeTheme) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(theme.file)
    }

    // MARK: Import

    /// Imports a SecShot, VS Code (JSON / JSONC) or TextMate (.tmTheme) theme and saves it.
    static func importTheme(from url: URL) throws -> CodeTheme {
        try save(parseTheme(at: url))
    }

    /// Reads a theme file without saving it.
    static func parseTheme(at url: URL) throws -> CodeTheme {
        guard let data = try? Data(contentsOf: url) else { throw ThemeImportError.unreadable }
        let fallbackName = url.deletingPathExtension().lastPathComponent
        let theme: CodeTheme
        if ["tmtheme", "plist", "xml"].contains(url.pathExtension.lowercased()) {
            theme = try fromTextMate(data, fallbackName: fallbackName)
        } else if let file = try? JSONDecoder().decode(CodeThemeFile.self, from: data), file.colors["background"] != nil {
            theme = CodeTheme(file: file)
        } else {
            theme = try fromVSCode(data, fallbackName: fallbackName)
        }
        return theme
    }

    /// TextMate scope candidates for each SecShot role, most specific first.
    private static let scopeMap: [(role: String, scopes: [String])] = [
        ("comment", ["comment"]),
        ("keyword", ["keyword.control", "keyword", "storage.type", "storage"]),
        ("string", ["string.quoted", "string"]),
        ("number", ["constant.numeric", "constant"]),
        ("function", ["entity.name.function", "support.function", "meta.function-call"]),
        ("type", ["entity.name.type", "entity.name.class", "support.type", "support.class", "storage.type"]),
        ("attribute", ["entity.other.attribute-name", "support.type.property-name", "variable.parameter"]),
        ("variable", ["variable.other.constant", "constant.language", "variable.language", "variable"]),
        ("headerName", ["support.type.property-name", "entity.name.tag", "entity.name.type"]),
        ("prompt", ["markup.inserted", "string", "entity.name.function"]),
    ]

    private static func resolve(_ rules: [(scopes: [String], color: String)]) -> [String: String] {
        var out: [String: String] = [:]
        for (role, candidates) in scopeMap {
            for candidate in candidates {
                // TextMate selector semantics: a rule for "keyword" also applies to "keyword.control".
                let match = rules
                    .flatMap { r in r.scopes.map { (scope: $0, color: r.color) } }
                    .filter { candidate == $0.scope || candidate.hasPrefix($0.scope + ".") }
                    .max { $0.scope.count < $1.scope.count }
                if let match { out[role] = match.color; break }
            }
        }
        return out
    }

    private static func fromVSCode(_ data: Data, fallbackName: String) throws -> CodeTheme {
        guard let text = String(data: data, encoding: .utf8),
              let json = try? JSONSerialization.jsonObject(with: Data(stripJSONC(text).utf8)) as? [String: Any] else {
            throw ThemeImportError.unsupported
        }
        let colors = json["colors"] as? [String: Any] ?? [:]
        var rules: [(scopes: [String], color: String)] = []
        for entry in json["tokenColors"] as? [[String: Any]] ?? [] {
            guard let settings = entry["settings"] as? [String: Any], let fg = settings["foreground"] as? String else { continue }
            let scopes: [String]
            if let s = entry["scope"] as? String { scopes = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
            else { scopes = entry["scope"] as? [String] ?? [] }
            rules.append((scopes, fg))
        }
        var map = resolve(rules)
        guard let bg = colors["editor.background"] as? String, let fg = colors["editor.foreground"] as? String
                ?? rules.first(where: { $0.scopes.isEmpty })?.color else { throw ThemeImportError.noColors }
        map["background"] = bg
        map["foreground"] = fg
        map["lineNumber"] = colors["editorLineNumber.foreground"] as? String
        map["output"] = colors["terminal.foreground"] as? String
        let type = (json["type"] as? String).map { $0.lowercased().contains("light") ? "light" : "dark" }
        return CodeTheme(file: CodeThemeFile(name: json["name"] as? String ?? fallbackName, type: type, colors: map.compactMapValues { $0 }))
    }

    private static func fromTextMate(_ data: Data, fallbackName: String) throws -> CodeTheme {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let settings = plist["settings"] as? [[String: Any]] else { throw ThemeImportError.unsupported }
        var general: [String: Any] = [:]
        var rules: [(scopes: [String], color: String)] = []
        for item in settings {
            guard let s = item["settings"] as? [String: Any] else { continue }
            if let scope = item["scope"] as? String {
                if let fg = s["foreground"] as? String {
                    rules.append((scope.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }, fg))
                }
            } else {
                general = s
            }
        }
        var map = resolve(rules)
        guard let bg = general["background"] as? String, let fg = general["foreground"] as? String else { throw ThemeImportError.noColors }
        map["background"] = bg
        map["foreground"] = fg
        map["lineNumber"] = general["gutterForeground"] as? String
        return CodeTheme(file: CodeThemeFile(name: plist["name"] as? String ?? fallbackName, type: nil, colors: map))
    }

    /// Removes // and /* */ comments and trailing commas (VS Code themes are JSONC).
    static func stripJSONC(_ text: String) -> String {
        var out = ""
        var chars = Array(text)
        var i = 0
        var inString = false
        while i < chars.count {
            let c = chars[i]
            if inString {
                out.append(c)
                if c == "\\", i + 1 < chars.count { out.append(chars[i + 1]); i += 2; continue }
                if c == "\"" { inString = false }
                i += 1
                continue
            }
            if c == "\"" { inString = true; out.append(c); i += 1; continue }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                i += 2
                while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i += 2
                continue
            }
            out.append(c)
            i += 1
        }
        chars = []
        return out.replacingOccurrences(of: #",(\s*[}\]])"#, with: "$1", options: .regularExpression)
    }
}

// MARK: - CodeTheme <-> file

extension CodeTheme {
    init(file: CodeThemeFile) {
        let base = CodeTheme.builtIn[2]
        let bg = parseHex(file.colors["background"]) ?? base.background
        let fg = parseHex(file.colors["foreground"]) ?? base.foreground
        let light = file.type.map { $0 == "light" } ?? (bg.usingColorSpace(.sRGB).map { luminance($0) > 0.5 } ?? false)
        self.init(name: file.name, isLight: light, background: bg, foreground: fg,
                  comment: fg.withAlphaComponent(0.5), keyword: fg, string: fg, number: fg, function: fg, type: fg,
                  attribute: fg, variable: fg, headerName: fg, prompt: fg,
                  lineNumber: fg.withAlphaComponent(0.35), output: fg.withAlphaComponent(0.8))
        for role in CodeTheme.roles {
            if let c = parseHex(file.colors[role.key]) { self[keyPath: role.path] = c }
        }
        // Sensible fallbacks for roles a theme did not define.
        if file.colors["headerName"] == nil { headerName = function }
        if file.colors["prompt"] == nil { prompt = string }
        if file.colors["attribute"] == nil { attribute = type }
    }

    var file: CodeThemeFile {
        var colors: [String: String] = [:]
        for role in CodeTheme.roles { colors[role.key] = hexString(self[keyPath: role.path]) }
        return CodeThemeFile(name: name, type: isLight ? "light" : "dark", colors: colors)
    }
}

func parseHex(_ string: String?) -> NSColor? {
    guard var s = string?.trimmingCharacters(in: .whitespaces), s.hasPrefix("#") else { return nil }
    s.removeFirst()
    if s.count == 3 || s.count == 4 { s = s.map { "\($0)\($0)" }.joined() }
    guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
    let hasAlpha = s.count == 8
    let r = CGFloat((v >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
    let g = CGFloat((v >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
    let b = CGFloat((v >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
    let a = hasAlpha ? CGFloat(v & 0xFF) / 255 : 1
    return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func hexString(_ color: NSColor) -> String {
    let c = color.usingColorSpace(.sRGB) ?? color
    let r = Int((c.redComponent * 255).rounded()), g = Int((c.greenComponent * 255).rounded())
    let b = Int((c.blueComponent * 255).rounded()), a = Int((c.alphaComponent * 255).rounded())
    return a < 255 ? String(format: "#%02X%02X%02X%02X", r, g, b, a) : String(format: "#%02X%02X%02X", r, g, b)
}

private func luminance(_ c: NSColor) -> CGFloat {
    0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
}
