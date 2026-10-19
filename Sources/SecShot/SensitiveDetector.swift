// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import Foundation
import Vision

struct SensitiveFinding {
    let rect: CGRect      // pixels, top-left origin
    let category: String
    let text: String
}

/// Sensitive-data detection using OCR (Vision) plus patterns typical of a pentest.
/// Patterns also match common Spanish keywords (contraseña, clave).
enum SensitiveDetector {
    static let categories: [(String, String)] = [
        ("Private key", #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#),
        ("JWT", #"eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{4,}"#),
        ("AWS Access Key", #"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"#),
        ("Credential / token", #"(?i)\b(?:password|passwd|pwd|pass|contrase(?:ñ|n)a|clave|secret|api[_\- ]?key|access[_\- ]?token|token|bearer|authorization)\b\s*[:=]?\s*\S{3,}"#),
        ("Cookie / session", #"(?i)\b(?:session(?:id)?|sessid|phpsessid|jsessionid|sid|cookie|set-cookie)\s*[=:]\s*[^\s;,]{6,}"#),
        ("Hash / hex secret", #"\b[a-fA-F0-9]{32,}\b"#),
        ("Long Base64", #"\b[A-Za-z0-9+/]{40,}={0,2}"#),
        ("Email", #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#),
        ("IPv4 address", #"\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b"#),
        ("MAC address", #"\b(?:[0-9A-Fa-f]{2}[:\-]){5}[0-9A-Fa-f]{2}\b"#),
        ("Payment card", #"\b(?:\d{4}[ \-]?){3}\d{1,4}\b"#),
    ]

    private static let compiled: [(String, NSRegularExpression)] = categories.compactMap { name, pattern in
        (try? NSRegularExpression(pattern: pattern)).map { (name, $0) }
    }

    static func detect(in image: CGImage, disabled: Set<String>) async -> [SensitiveFinding] {
        await Task.detached(priority: .userInitiated) { () -> [SensitiveFinding] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false   // never "correct" tokens or hashes
            request.recognitionLanguages = ["es-ES", "en-US"]
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do { try handler.perform([request]) } catch { return [] }

            let W = CGFloat(image.width), H = CGFloat(image.height)
            var findings: [SensitiveFinding] = []
            for obs in request.results ?? [] {
                guard let cand = obs.topCandidates(1).first else { continue }
                let s = cand.string
                let ns = s as NSString
                for (name, re) in compiled where !disabled.contains(name) {
                    for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                        guard let range = Range(m.range, in: s),
                              let box = try? cand.boundingBox(for: range)?.boundingBox else { continue }
                        let rect = CGRect(x: box.minX * W, y: (1 - box.maxY) * H,
                                          width: box.width * W, height: box.height * H).insetBy(dx: -4, dy: -3)
                        if findings.contains(where: { overlapRatio($0.rect, rect) > 0.8 }) { continue }
                        findings.append(SensitiveFinding(rect: rect.integral, category: name, text: ns.substring(with: m.range)))
                    }
                }
            }
            return findings
        }.value
    }

    private static func overlapRatio(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        guard !i.isNull else { return 0 }
        let smaller = min(a.width * a.height, b.width * b.height)
        return smaller > 0 ? (i.width * i.height) / smaller : 0
    }
}
