// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import Foundation

/// One request/response pair imported from Burp Suite, a HAR file or a raw HTTP file.
struct HTTPExchange: Identifiable, Hashable {
    let id = UUID()
    var index: Int
    var source: String
    var time: String
    var method: String
    var url: String
    var host: String
    var path: String
    var status: Int?
    var mime: String
    var request: Data
    var response: Data?
    var comment: String

    var statusText: String { status.map(String.init) ?? "—" }
    var responseLength: Int { response?.count ?? 0 }
    var shortLabel: String { "#\(index) \(method) \(path.count > 48 ? String(path.prefix(47)) + "…" : path)" }
}

enum TrafficImportError: LocalizedError {
    case unreadable, tooLarge, unsupported, empty

    var errorDescription: String? {
        switch self {
        case .unreadable: return "The file could not be read."
        case .tooLarge: return "The file is larger than 300 MB."
        case .unsupported: return "Unsupported format. Use Burp Suite “Save items” XML, a HAR file, or a raw HTTP request/response (.txt / .http)."
        case .empty: return "No HTTP items were found in the file."
        }
    }
}

enum TrafficImporter {
    struct Result {
        var exchanges: [HTTPExchange]
        var format: String
    }

    static func load(_ url: URL, startIndex: Int) throws -> Result {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard size <= 300 * 1024 * 1024 else { throw TrafficImportError.tooLarge }
        guard let data = try? Data(contentsOf: url) else { throw TrafficImportError.unreadable }
        let head = String(decoding: data.prefix(4096), as: UTF8.self)
        let result: Result
        if head.contains("<items") || head.hasPrefix("<?xml") {
            result = Result(exchanges: try BurpXMLParser.parse(data, startIndex: startIndex), format: "Burp Suite XML")
        } else if head.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"), head.contains("\"log\"") {
            result = Result(exchanges: try HARParser.parse(data, startIndex: startIndex), format: "HAR")
        } else if let raw = RawHTTPParser.parse(data, name: url.lastPathComponent, index: startIndex) {
            result = Result(exchanges: [raw], format: "Raw HTTP")
        } else {
            throw TrafficImportError.unsupported
        }
        guard !result.exchanges.isEmpty else { throw TrafficImportError.empty }
        return result
    }
}

// MARK: - Burp Suite "Save items" XML

/// Parses Burp's item export. External entities are never resolved (no XXE from untrusted files).
final class BurpXMLParser: NSObject, XMLParserDelegate {
    private var items: [HTTPExchange] = []
    private var current: [String: String] = [:]
    private var currentBase64: [String: Bool] = [:]
    private var hostIP = ""
    private var text = ""
    private var inItem = false
    private var index: Int

    private init(startIndex: Int) { index = startIndex }

    static func parse(_ data: Data, startIndex: Int) throws -> [HTTPExchange] {
        // Burp declares XML 1.1, which the system parser may reject; the content is 1.0-compatible.
        var xml = data
        if let s = String(data: data.prefix(64), encoding: .utf8), s.hasPrefix("<?xml version=\"1.1\"") {
            xml = Data("<?xml version=\"1.0\"".utf8) + data.dropFirst("<?xml version=\"1.1\"".utf8.count)
        }
        let delegate = BurpXMLParser(startIndex: startIndex)
        let parser = XMLParser(data: xml)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate
        guard parser.parse() || !delegate.items.isEmpty else { throw TrafficImportError.unsupported }
        return delegate.items
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        text = ""
        if name == "item" {
            inItem = true
            current = [:]
            currentBase64 = [:]
            hostIP = ""
        } else if inItem {
            if name == "request" || name == "response" { currentBase64[name] = attributes["base64"] == "true" }
            if name == "host" { hostIP = attributes["ip"] ?? "" }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard inItem else { return }
        if name == "item" {
            inItem = false
            let request = decode(current["request"], base64: currentBase64["request"] ?? false) ?? Data()
            let response = decode(current["response"], base64: currentBase64["response"] ?? false)
            let url = current["url"] ?? ""
            let host = current["host"] ?? URL(string: url)?.host ?? ""
            let firstLine = String(decoding: request.prefix(512), as: UTF8.self).components(separatedBy: "\n").first ?? ""
            let method = current["method"].flatMap { $0.isEmpty ? nil : $0 } ?? (firstLine.split(separator: " ").first.map(String.init) ?? "")
            items.append(HTTPExchange(index: index, source: "Burp", time: current["time"] ?? "", method: method,
                                      url: url, host: host, path: current["path"] ?? URL(string: url)?.path ?? "",
                                      status: Int(current["status"] ?? ""), mime: current["mimetype"] ?? "",
                                      request: request, response: response, comment: current["comment"] ?? ""))
            index += 1
        } else {
            current[name] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        text = ""
    }

    private func decode(_ value: String?, base64: Bool) -> Data? {
        guard let value, !value.isEmpty else { return nil }
        if base64 { return Data(base64Encoded: value, options: .ignoreUnknownCharacters) }
        return Data(value.utf8)
    }
}

// MARK: - HAR (browser DevTools, Caido, ZAP…)

enum HARParser {
    static func parse(_ data: Data, startIndex: Int) throws -> [HTTPExchange] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let log = json["log"] as? [String: Any],
              let entries = log["entries"] as? [[String: Any]] else { throw TrafficImportError.unsupported }
        var out: [HTTPExchange] = []
        for (k, e) in entries.enumerated() {
            guard let req = e["request"] as? [String: Any] else { continue }
            let method = req["method"] as? String ?? "GET"
            let urlString = req["url"] as? String ?? ""
            let url = URL(string: urlString)
            let version = normalizeVersion(req["httpVersion"] as? String)
            var target = url?.path ?? "/"
            if target.isEmpty { target = "/" }
            if let q = url?.query { target += "?" + q }
            var head = "\(method) \(target) \(version)\r\n"
            let headers = (req["headers"] as? [[String: Any]] ?? []).compactMap { h -> (String, String)? in
                guard let n = h["name"] as? String, !n.hasPrefix(":") else { return nil }
                return (n, h["value"] as? String ?? "")
            }
            if !headers.contains(where: { $0.0.lowercased() == "host" }), let host = url?.host { head += "Host: \(host)\r\n" }
            for (n, v) in headers { head += "\(n): \(v)\r\n" }
            var request = Data((head + "\r\n").utf8)
            if let body = (req["postData"] as? [String: Any])?["text"] as? String { request.append(Data(body.utf8)) }

            var response: Data?
            var status: Int?
            var mime = ""
            if let res = e["response"] as? [String: Any] {
                status = res["status"] as? Int
                var rhead = "\(normalizeVersion(res["httpVersion"] as? String)) \(status ?? 0) \(res["statusText"] as? String ?? "")\r\n"
                for h in res["headers"] as? [[String: Any]] ?? [] {
                    guard let n = h["name"] as? String, !n.hasPrefix(":") else { continue }
                    rhead += "\(n): \(h["value"] as? String ?? "")\r\n"
                }
                var r = Data((rhead + "\r\n").utf8)
                if let content = res["content"] as? [String: Any] {
                    mime = content["mimeType"] as? String ?? ""
                    if let t = content["text"] as? String {
                        if (content["encoding"] as? String) == "base64", let d = Data(base64Encoded: t) { r.append(d) }
                        else { r.append(Data(t.utf8)) }
                    }
                }
                response = r
            }
            out.append(HTTPExchange(index: startIndex + k, source: "HAR", time: e["startedDateTime"] as? String ?? "",
                                    method: method, url: urlString, host: url?.host ?? "", path: target,
                                    status: status, mime: mime, request: request, response: response,
                                    comment: e["comment"] as? String ?? ""))
        }
        return out
    }

    private static func normalizeVersion(_ v: String?) -> String {
        let s = (v ?? "").uppercased()
        if s.isEmpty || s == "UNKNOWN" { return "HTTP/1.1" }
        if s.hasPrefix("H2") || s.hasPrefix("HTTP/2") { return "HTTP/2" }
        if s.hasPrefix("H3") || s.hasPrefix("HTTP/3") { return "HTTP/3" }
        return s.hasPrefix("HTTP/") ? s : "HTTP/1.1"
    }
}

// MARK: - Raw HTTP file

enum RawHTTPParser {
    static func parse(_ data: Data, name: String, index: Int) -> HTTPExchange? {
        let text = String(decoding: data.prefix(2048), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let first = text.components(separatedBy: .newlines).first ?? ""
        if first.range(of: #"^HTTP/\d(\.\d)?\s+\d{3}"#, options: .regularExpression) != nil {
            let status = Int(first.split(separator: " ").dropFirst().first ?? "")
            return HTTPExchange(index: index, source: "Raw", time: "", method: "", url: "", host: "", path: name,
                                status: status, mime: "", request: Data(), response: data, comment: "")
        }
        let parts = first.split(separator: " ")
        guard parts.count >= 3, parts[2].hasPrefix("HTTP/") else { return nil }
        let host = text.components(separatedBy: .newlines)
            .first { $0.lowercased().hasPrefix("host:") }?
            .dropFirst(5).trimmingCharacters(in: .whitespaces) ?? ""
        return HTTPExchange(index: index, source: "Raw", time: "", method: String(parts[0]), url: "", host: host,
                            path: String(parts[1]), status: nil, mime: "", request: data, response: nil, comment: "")
    }
}

// MARK: - Turning messages into code-snippet text

enum TrafficFormatter {
    struct Options {
        var redact = true
        var marker = "[REDACTED]"
        var bodyLineLimit = 40
    }

    /// Readable text for a raw HTTP message: credential redaction, JSON pretty-printing and a body
    /// line limit so long responses stay legible in a report.
    static func text(_ data: Data?, _ o: Options) -> String {
        guard let data, !data.isEmpty else { return "" }
        let (headData, bodyData) = split(data)
        var head = (String(data: headData, encoding: .utf8) ?? String(decoding: headData, as: UTF8.self))
            .replacingOccurrences(of: "\r\n", with: "\n")
        if o.redact { head = redactHeaders(head, marker: o.marker) }
        guard let bodyData, !bodyData.isEmpty else { return head }

        var body: String
        if isBinary(bodyData) {
            body = "[binary body omitted — \(ByteCountFormatter.string(fromByteCount: Int64(bodyData.count), countStyle: .file))]"
        } else {
            body = (String(data: bodyData, encoding: .utf8) ?? String(data: bodyData, encoding: .isoLatin1) ?? "")
                .replacingOccurrences(of: "\r\n", with: "\n")
            if let pretty = JSONFormatter.prettify(body) { body = pretty }
            if o.redact { body = redactBody(body, marker: o.marker) }
            var lines = body.components(separatedBy: "\n")
            if o.bodyLineLimit > 0, lines.count > o.bodyLineLimit {
                let more = lines.count - o.bodyLineLimit
                lines = Array(lines.prefix(o.bodyLineLimit)) + ["… (\(more) more line\(more == 1 ? "" : "s"))"]
                body = lines.joined(separator: "\n")
            }
        }
        return head + "\n\n" + body
    }

    /// First line of a message, e.g. "HTTP/1.1 200 OK".
    static func firstLine(_ data: Data?) -> String {
        guard let data else { return "" }
        return String(decoding: data.prefix(256), as: UTF8.self).components(separatedBy: .newlines).first ?? ""
    }

    private static func split(_ data: Data) -> (Data, Data?) {
        for sep in [Data("\r\n\r\n".utf8), Data("\n\n".utf8)] {
            if let r = data.range(of: sep) {
                return (data[..<r.lowerBound], data[r.upperBound...])
            }
        }
        return (data, nil)
    }

    private static func isBinary(_ data: Data) -> Bool {
        let sample = data.prefix(2048)
        if sample.contains(0) { return true }
        return String(data: sample, encoding: .utf8) == nil && String(data: data, encoding: .utf8) == nil
            && sample.filter { $0 < 9 }.count > 4
    }

    // MARK: Redaction

    private static let secretHeaders: Set<String> = [
        "authorization", "proxy-authorization", "x-api-key", "api-key", "x-auth-token", "x-access-token",
        "x-amz-security-token", "x-csrf-token", "x-xsrf-token",
    ]

    static func redactHeaders(_ head: String, marker: String) -> String {
        head.components(separatedBy: "\n").map { line in
            guard let colon = line.firstIndex(of: ":"), line.first != " " else { return line }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            let lower = name.lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch lower {
            case "cookie":
                let cookies = value.split(separator: ";").map { pair -> String in
                    let p = pair.trimmingCharacters(in: .whitespaces)
                    guard let eq = p.firstIndex(of: "=") else { return p }
                    return "\(p[..<eq])=\(marker)"
                }
                return "\(name): " + cookies.joined(separator: "; ")
            case "set-cookie":
                var parts = value.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
                if let eq = parts.first?.firstIndex(of: "=") {
                    parts[0] = "\(parts[0][..<eq])=\(marker)"
                }
                return "\(name): " + parts.joined(separator: ";")
            case _ where secretHeaders.contains(lower):
                let words = value.split(separator: " ", maxSplits: 1)
                if words.count == 2, ["bearer", "basic", "digest", "token", "negotiate", "ntlm", "aws4-hmac-sha256"]
                    .contains(words[0].lowercased()) {
                    return "\(name): \(words[0]) \(marker)"
                }
                return "\(name): \(marker)"
            default:
                return line
            }
        }.joined(separator: "\n")
    }

    private static let secretKeys = "password|passwd|pwd|pass|secret|token|access_token|refresh_token|id_token|"
        + "api_key|apikey|client_secret|session|sessionid|otp|pin|cvv|card_number|ssn"

    static func redactBody(_ body: String, marker: String) -> String {
        let template = NSRegularExpression.escapedTemplate(for: marker)
        var out = body
        // JSON: "password": "…"
        if let json = try? NSRegularExpression(pattern: #"("(?:"# + secretKeys + #")"\s*:\s*)"(?:[^"\\]|\\.)*""#,
                                               options: [.caseInsensitive]) {
            out = json.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out),
                                                withTemplate: "$1\"" + template + "\"")
        }
        // Form / query: password=…&
        if let form = try? NSRegularExpression(pattern: #"((?:^|[&?])(?:"# + secretKeys + #")=)[^&\s]*"#,
                                               options: [.caseInsensitive, .anchorsMatchLines]) {
            out = form.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out),
                                                withTemplate: "$1" + template)
        }
        return out
    }
}
