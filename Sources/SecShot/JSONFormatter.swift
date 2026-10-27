// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import Foundation

/// Pretty-prints JSON for code images while keeping key order and literal values exactly as written
/// (a JSONSerialization round-trip would reorder keys and rewrite numbers).
enum JSONFormatter {
    /// Returns the indented JSON, or `nil` when the text is not a valid JSON object or array.
    static func prettify(_ text: String, indent: Int = 2) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[",
              let data = trimmed.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else { return nil }

        var out = ""
        var level = 0
        var inString = false
        var escaped = false
        let chars = Array(trimmed)
        var i = 0
        func newline() { out += "\n" + String(repeating: " ", count: level * indent) }

        while i < chars.count {
            let c = chars[i]
            if inString {
                out.append(c)
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                i += 1
                continue
            }
            switch c {
            case "\"":
                inString = true
                out.append(c)
            case "{", "[":
                // Keep empty containers compact: {} and [].
                var j = i + 1
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                if j < chars.count, chars[j] == (c == "{" ? "}" : "]") {
                    out.append(c); out.append(chars[j])
                    i = j + 1
                    continue
                }
                out.append(c)
                level += 1
                newline()
            case "}", "]":
                level = max(0, level - 1)
                newline()
                out.append(c)
            case ",":
                out.append(c)
                newline()
            case ":":
                out += ": "
            case " ", "\t", "\n", "\r":
                break
            default:
                out.append(c)
            }
            i += 1
        }
        return out
    }

    /// Formats a standalone JSON document, or the JSON body of an HTTP request/response.
    static func format(_ code: String, language: CodeLanguage) -> String {
        let text = CodeHighlighter.normalize(code)
        let lines = text.components(separatedBy: "\n")
        let lang = language == .auto ? CodeHighlighter.detect(lines) : language
        switch lang {
        case .json:
            return prettify(text) ?? code
        case .http:
            guard let blank = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }),
                  blank + 1 < lines.count else { return code }
            let head = lines[..<blank].joined(separator: "\n")
            let body = lines[(blank + 1)...].joined(separator: "\n")
            guard let pretty = prettify(body) else { return code }
            return head + "\n\n" + pretty
        default:
            return code
        }
    }
}
