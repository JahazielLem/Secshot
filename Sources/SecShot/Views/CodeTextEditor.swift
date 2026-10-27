// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import AppKit
import SwiftUI

/// Replaces selected text in the code editors with a redaction marker such as `[REDACTED]`.
@MainActor
enum CodeRedactor {
    static let presets = ["[REDACTED]", "[REDACTED-SECRET]", "********", "█████", "<redacted>", "{{REDACTED}}"]

    static var marker: String {
        let s = UserDefaults.standard.string(forKey: Prefs.redactionText) ?? "[REDACTED]"
        return s.isEmpty ? "[REDACTED]" : s
    }

    /// The code editor the user last typed or selected in.
    static weak var activeTextView: NSTextView?

    /// Redacts every selected range in the active editor. Undo restores the original text.
    @discardableResult
    static func redactSelection(in textView: NSTextView? = nil) -> Bool {
        guard let tv = textView ?? activeTextView else { return false }
        let ranges = tv.selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        guard !ranges.isEmpty else { return false }
        let token = marker
        guard tv.shouldChangeText(inRanges: ranges.map { NSValue(range: $0) },
                                  replacementStrings: Array(repeating: token, count: ranges.count)) else { return false }
        tv.textStorage?.beginEditing()
        for r in ranges.sorted(by: { $0.location > $1.location }) {
            tv.textStorage?.replaceCharacters(in: r, with: token)
        }
        tv.textStorage?.endEditing()
        tv.didChangeText()
        if let first = ranges.min(by: { $0.location < $1.location }) {
            tv.setSelectedRange(NSRange(location: first.location, length: (token as NSString).length))
        }
        return true
    }
}

/// Plain-text code editor (NSTextView) with selection access, used so selections can be redacted.
struct CodeTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.backgroundColor = .textBackgroundColor
        tv.delegate = context.coordinator
        tv.string = text
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView, tv.string != text else { return }
        // External change (sample, paste button, swap…): replace the text keeping it undoable.
        let full = NSRange(location: 0, length: (tv.string as NSString).length)
        if tv.shouldChangeText(in: full, replacementString: text) {
            tv.textStorage?.replaceCharacters(in: full, with: text)
            tv.didChangeText()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeTextEditor

        init(_ parent: CodeTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            if parent.text != tv.string { parent.text = tv.string }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            MainActor.assumeIsolated { CodeRedactor.activeTextView = tv }
        }

        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            let item = NSMenuItem(title: "Redact Selection", action: #selector(redact(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = view
            item.isEnabled = view.selectedRange().length > 0
            menu.insertItem(item, at: 0)
            menu.insertItem(.separator(), at: 1)
            return menu
        }

        @objc func redact(_ sender: NSMenuItem) {
            let view = sender.representedObject as? NSTextView
            MainActor.assumeIsolated { _ = CodeRedactor.redactSelection(in: view) }
        }
    }
}
