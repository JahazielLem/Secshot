// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import Foundation

enum CodeLanguage: String, CaseIterable, Identifiable {
    case auto, http, json, shell, python, javascript, clike, sql, xml, plain

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto-detect"
        case .http: return "HTTP request / response"
        case .json: return "JSON"
        case .shell: return "Terminal / Shell"
        case .python: return "Python"
        case .javascript: return "JavaScript / TypeScript"
        case .clike: return "C / C++ / Java / Go / C# / PHP"
        case .sql: return "SQL"
        case .xml: return "XML / HTML"
        case .plain: return "Plain text"
        }
    }
}

enum TokenKind {
    case comment, keyword, string, number, function, type, attribute, variable, punctuation
    case headerName, prompt, output
    case statusSuccess, statusRedirect, statusClientError, statusServerError
}

struct CodeToken {
    var range: NSRange
    var kind: TokenKind
}

struct HighlightedCode {
    var lines: [String]
    var tokens: [[CodeToken]]
    var language: CodeLanguage
    /// HTTP only: index of the first body line (after the blank line), if any.
    var httpBodyStart: Int?
}

/// Small regex-based highlighter. It favors robustness over completeness: unknown text is
/// simply left in the default color.
enum CodeHighlighter {
    private struct Rule {
        let regex: NSRegularExpression
        let kind: TokenKind?   // nil = consume without coloring

        init(_ pattern: String, _ kind: TokenKind?, caseInsensitive: Bool = false) {
            regex = try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
            self.kind = kind
        }
    }

    // MARK: Public

    static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: "    ")
    }

    static func highlight(_ text: String, language: CodeLanguage) -> HighlightedCode {
        var lines = normalize(text).components(separatedBy: "\n")
        while lines.count > 1, lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        let lang = language == .auto ? detect(lines) : language
        switch lang {
        case .http: return highlightHTTP(lines)
        case .shell: return HighlightedCode(lines: lines, tokens: highlightShell(lines), language: lang)
        default: return HighlightedCode(lines: lines, tokens: highlightLines(lines, rules: rules(for: lang), blockComments: usesBlockComments(lang)), language: lang)
        }
    }

    static func detect(_ lines: [String]) -> CodeLanguage {
        let first = lines.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?.trimmingCharacters(in: .whitespaces) ?? ""
        let all = lines.joined(separator: "\n")
        if first.range(of: #"^HTTP/\d(\.\d)?\s+\d{3}"#, options: .regularExpression) != nil { return .http }
        if first.range(of: #"^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|CONNECT|TRACE)\s+\S+\s+HTTP/\d"#, options: .regularExpression) != nil { return .http }
        if first.hasPrefix("{") || first.hasPrefix("[") { return .json }
        if first.hasPrefix("<") { return .xml }
        if lines.contains(where: { promptLength($0) != nil }) || first.hasPrefix("#!") { return .shell }
        if all.range(of: #"(?m)^\s*(SELECT|INSERT|UPDATE|DELETE|CREATE|ALTER|DROP)\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return .sql }
        if all.range(of: #"(?m)^\s*(def |class \w+.*:|import \w|from \w+ import)"#, options: .regularExpression) != nil { return .python }
        if all.range(of: #"\b(const|let|function|=>|console\.log|require\(|export )"#, options: .regularExpression) != nil { return .javascript }
        if all.range(of: #"(#include|public static|func \w+\(|package \w+|<\?php|std::)"#, options: .regularExpression) != nil { return .clike }
        return .plain
    }

    // MARK: Generic scanner

    private static func scan(_ line: String, from start: Int, rules: [Rule], into tokens: inout [CodeToken]) {
        let ns = line as NSString
        var i = start
        while i < ns.length {
            var advanced = false
            for rule in rules {
                if let m = rule.regex.firstMatch(in: line, options: [.anchored, .withoutAnchoringBounds],
                                                 range: NSRange(location: i, length: ns.length - i)),
                   m.range.length > 0 {
                    if let kind = rule.kind { tokens.append(CodeToken(range: m.range, kind: kind)) }
                    i = NSMaxRange(m.range)
                    advanced = true
                    break
                }
            }
            if !advanced { i += 1 }
        }
    }

    private static func highlightLines(_ lines: [String], rules: [Rule], blockComments: Bool) -> [[CodeToken]] {
        var inBlock = false
        let close = try! NSRegularExpression(pattern: #"\*/"#)
        return lines.map { line in
            var tokens: [CodeToken] = []
            var start = 0
            let ns = line as NSString
            if blockComments && inBlock {
                if let m = close.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                    tokens.append(CodeToken(range: NSRange(location: 0, length: NSMaxRange(m.range)), kind: .comment))
                    start = NSMaxRange(m.range)
                    inBlock = false
                } else {
                    return [CodeToken(range: NSRange(location: 0, length: ns.length), kind: .comment)]
                }
            }
            scan(line, from: start, rules: rules, into: &tokens)
            if blockComments, let last = tokens.last(where: { $0.kind == .comment }) {
                let text = ns.substring(with: last.range)
                if text.hasPrefix("/*") && !text.hasSuffix("*/") { inBlock = true }
            }
            return tokens
        }
    }

    // MARK: Language rules

    private static let stringRules = [
        Rule(#""(?:[^"\\]|\\.)*""#, .string),
        Rule(#"'(?:[^'\\]|\\.)*'"#, .string),
    ]
    private static let numberRule = Rule(#"\b(?:0x[0-9a-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"#, .number)
    private static let functionRule = Rule(#"\b[A-Za-z_]\w*(?=\s*\()"#, .function)
    private static let typeRule = Rule(#"\b[A-Z][A-Za-z0-9_]*\b"#, .type)
    private static let identRule = Rule(#"[A-Za-z_]\w*"#, nil)

    private static func keywords(_ words: String, caseInsensitive: Bool = false) -> Rule {
        Rule(#"\b(?:"# + words.split(separator: " ").joined(separator: "|") + #")\b"#, .keyword, caseInsensitive: caseInsensitive)
    }

    private static func usesBlockComments(_ lang: CodeLanguage) -> Bool {
        lang == .javascript || lang == .clike
    }

    private static func rules(for lang: CodeLanguage) -> [Rule] {
        switch lang {
        case .json:
            return [
                Rule(#""(?:[^"\\]|\\.)*"(?=\s*:)"#, .attribute),
                Rule(#""(?:[^"\\]|\\.)*""#, .string),
                Rule(#"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, .number),
                Rule(#"\b(?:true|false|null)\b"#, .keyword),
                Rule(#"[{}\[\],:]"#, .punctuation),
            ]
        case .python:
            return [Rule(#"#.*"#, .comment),
                    Rule(#"(?:"""|''').*?(?:"""|'''|$)"#, .string)] + stringRules + [
                    Rule(#"@[A-Za-z_][\w.]*"#, .attribute),
                    keywords("def class return if elif else for while in import from as with try except finally raise lambda pass break continue yield async await global nonlocal and or not is assert del"),
                    Rule(#"\b(?:None|True|False|self|cls)\b"#, .variable),
                    numberRule, functionRule, typeRule, identRule]
        case .javascript:
            return [Rule(#"//.*"#, .comment),
                    Rule(#"/\*(?:(?!\*/).)*(?:\*/)?"#, .comment)] + stringRules + [
                    Rule(#"`(?:[^`\\]|\\.)*`?"#, .string),
                    keywords("function const let var return if else for while do switch case break continue new class extends import from export default try catch finally throw typeof instanceof in of async await yield interface type implements enum readonly public private protected static get set"),
                    Rule(#"\b(?:true|false|null|undefined|this|NaN)\b"#, .variable),
                    numberRule, functionRule, typeRule, identRule]
        case .clike:
            return [Rule(#"//.*"#, .comment),
                    Rule(#"/\*(?:(?!\*/).)*(?:\*/)?"#, .comment),
                    Rule(#"^\s*#\s*\w+"#, .attribute)] + stringRules + [
                    Rule(#"\$[A-Za-z_]\w*"#, .variable),
                    keywords("if else for while do switch case break continue return goto struct union enum typedef sizeof static const volatile extern inline void int char short long float double unsigned signed bool auto class public private protected virtual override new delete this namespace using template typename try catch throw func package import var type go defer chan map range select interface fn let mut impl trait pub use mod match loop where echo function"),
                    Rule(#"\b(?:true|false|null|nil|nullptr|NULL)\b"#, .variable),
                    numberRule, functionRule, typeRule, identRule]
        case .sql:
            return [Rule(#"--.*"#, .comment),
                    Rule(#"'(?:[^']|'')*'"#, .string),
                    Rule(#""(?:[^"]|"")*""#, .attribute),
                    keywords("select from where insert into values update set delete join left right inner outer full cross on and or not null is as order by group having limit offset union all distinct like in between exists case when then else end create table drop alter add index primary key foreign references view database grant revoke truncate returning with", caseInsensitive: true),
                    numberRule, functionRule, identRule]
        case .xml:
            return [Rule(#"<!--.*?(?:-->|$)"#, .comment),
                    Rule(#"<\?[\w:-]+|\?>"#, .keyword),
                    Rule(#"</?[A-Za-z][\w:.-]*"#, .keyword),
                    Rule(#"[A-Za-z_:][\w:.-]*(?=\s*=)"#, .attribute)] + stringRules + [
                    Rule(#"/?>"#, .keyword),
                    Rule(#"&#?\w+;"#, .number)]
        default:
            return []
        }
    }

    // MARK: Shell

    /// Length of the prompt at the start of a terminal line (`$ `, `% `, `❯ `, `user@host:~$ `).
    static func promptLength(_ line: String) -> Int? {
        let pattern = #"^\s*(?:\(?[\w.-]+\)?\s*)?(?:[\w.-]+@[\w.-]+(?::?[^\s$#%>]*)?\s*)?(?:[$%❯➜»]|#(?=\s+\S)|>(?=\s))\s"#
        guard let r = line.range(of: pattern, options: .regularExpression) else { return nil }
        // A bare "# text" line is a comment unless it looks like a root prompt with a host.
        let prefix = String(line[r])
        if prefix.trimmingCharacters(in: .whitespaces) == "#" { return nil }
        return line.distance(from: line.startIndex, to: r.upperBound)
    }

    private static let shellCommandPrefixes: Set<String> = ["sudo", "time", "env", "nohup", "exec", "xargs", "watch", "doas"]

    private static func highlightShell(_ lines: [String]) -> [[CodeToken]] {
        let hasPrompts = lines.contains { promptLength($0) != nil }
        let comment = Rule(#"#.*"#, .comment)
        let rules: [Rule] = stringRules + [
            Rule(#"https?://[^\s'"]+"#, .string),
            Rule(#"\$\{[^}]*\}|\$\(|\$[A-Za-z_]\w*|\$[0-9@#?*!$]"#, .variable),
            Rule(#"(?<=\s)--?[A-Za-z0-9][\w-]*"#, .attribute),
            Rule(#"\|\||&&|[|;]"#, .keyword),
            Rule(#"\d*>>?|<<?|&>"#, .keyword),
            // Whole numbers, IPs and port lists (10.10.20.15, 22,80,443, 8.9p1 stays plain).
            Rule(#"(?<![\w.-])\d+(?:[.,:/]\d+)*(?![\w.-])"#, .number),
            Rule(#"[^\s'"$|;&<>#]+"#, nil),
        ]
        return lines.map { line in
            var tokens: [CodeToken] = []
            let ns = line as NSString
            var start = 0
            if hasPrompts {
                guard let p = promptLength(line) else {
                    // Command output.
                    return ns.length > 0 ? [CodeToken(range: NSRange(location: 0, length: ns.length), kind: .output)] : []
                }
                tokens.append(CodeToken(range: NSRange(location: 0, length: p), kind: .prompt))
                start = p
            }
            // Walk the line: the first word of each command is a command name.
            var i = start
            var expectCommand = true
            while i < ns.length {
                let ch = ns.character(at: i)
                if ch == 32 { i += 1; continue }   // space
                if ch == 35, i == 0 || ns.character(at: i - 1) == 32 {   // '#' comment
                    if let m = comment.regex.firstMatch(in: line, options: [.anchored, .withoutAnchoringBounds],
                                                        range: NSRange(location: i, length: ns.length - i)) {
                        tokens.append(CodeToken(range: m.range, kind: .comment))
                        break
                    }
                }
                if expectCommand,
                   let m = try! NSRegularExpression(pattern: #"[A-Za-z0-9_./~+-][^\s|;&<>()]*"#)
                    .firstMatch(in: line, options: [.anchored], range: NSRange(location: i, length: ns.length - i)) {
                    let word = ns.substring(with: m.range)
                    if word.contains("=") && !word.hasPrefix("=") {
                        tokens.append(CodeToken(range: m.range, kind: .variable))   // VAR=value prefix
                    } else {
                        tokens.append(CodeToken(range: m.range, kind: .function))
                        expectCommand = shellCommandPrefixes.contains(word)
                    }
                    i = NSMaxRange(m.range)
                    continue
                }
                var matched = false
                for rule in rules {
                    if let m = rule.regex.firstMatch(in: line, options: [.anchored, .withoutAnchoringBounds],
                                                     range: NSRange(location: i, length: ns.length - i)), m.range.length > 0 {
                        if let kind = rule.kind {
                            tokens.append(CodeToken(range: m.range, kind: kind))
                            let text = ns.substring(with: m.range)
                            if kind == .keyword && ["|", "||", "&&", ";"].contains(text) { expectCommand = true }
                        }
                        i = NSMaxRange(m.range)
                        matched = true
                        break
                    }
                }
                if !matched { i += 1 }
            }
            return tokens
        }
    }

    // MARK: HTTP

    private static let headerValueRules: [Rule] = [
        Rule(#"https?://[^\s;,'"]+"#, .string),
        Rule(#"'[^']*'"#, .keyword),
        Rule(#""(?:[^"\\]|\\.)*""#, .string),
        Rule(#"(?:(?<=:\s)|(?<=:)|(?<=;\s)|(?<=;)|(?<=,\s))[a-z][a-z0-9-]*(?=\s+\S|=)"#, .attribute),
        Rule(#"\b\d+(?:\.\d+)?\b"#, .number),
        Rule(#"[;,=]"#, .punctuation),
        Rule(#"[^\s;,='"]+"#, nil),
    ]

    private static func highlightHTTP(_ lines: [String]) -> HighlightedCode {
        let status = try! NSRegularExpression(pattern: #"^(HTTP/\d(?:\.\d)?)(\s+)(\d{3})(.*)$"#)
        let request = try! NSRegularExpression(pattern: #"^([A-Z]+)(\s+)(\S+)(\s+)(HTTP/\d(?:\.\d)?)\s*$"#)
        let header = try! NSRegularExpression(pattern: #"^(:?[!#$%&'*+.^_`|~0-9A-Za-z-]+)(:)(.*)$"#)

        var tokens: [[CodeToken]] = Array(repeating: [], count: lines.count)
        var bodyStart: Int?
        var firstLine: Int?
        for (n, line) in lines.enumerated() {
            let full = NSRange(location: 0, length: (line as NSString).length)
            if bodyStart != nil { break }
            if firstLine == nil {
                if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                firstLine = n
                if let m = status.firstMatch(in: line, range: full) {
                    let code = Int((line as NSString).substring(with: m.range(at: 3))) ?? 0
                    let kind: TokenKind = code >= 500 ? .statusServerError : code >= 400 ? .statusClientError
                        : code >= 300 ? .statusRedirect : .statusSuccess
                    tokens[n] = [CodeToken(range: m.range(at: 1), kind: .type),
                                 CodeToken(range: m.range(at: 3), kind: kind),
                                 CodeToken(range: m.range(at: 4), kind: kind)]
                    continue
                }
                if let m = request.firstMatch(in: line, range: full) {
                    tokens[n] = [CodeToken(range: m.range(at: 1), kind: .keyword),
                                 CodeToken(range: m.range(at: 3), kind: .string),
                                 CodeToken(range: m.range(at: 5), kind: .type)]
                    continue
                }
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                bodyStart = n + 1
                break
            }
            if let m = header.firstMatch(in: line, range: full) {
                var t = [CodeToken(range: m.range(at: 1), kind: .headerName),
                         CodeToken(range: m.range(at: 2), kind: .punctuation)]
                scan(line, from: m.range(at: 3).location, rules: headerValueRules, into: &t)
                tokens[n] = t
            }
        }

        if let b = bodyStart, b < lines.count {
            let body = Array(lines[b...])
            let bodyLang = detect(body)
            let lang: CodeLanguage = [.json, .xml].contains(bodyLang) ? bodyLang : .plain
            let bodyTokens = highlightLines(body, rules: rules(for: lang), blockComments: false)
            for (k, t) in bodyTokens.enumerated() { tokens[b + k] = t }
        }
        return HighlightedCode(lines: lines, tokens: tokens, language: .http, httpBodyStart: bodyStart)
    }
}
