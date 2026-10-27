// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import Foundation

/// Content of the Code Snippet section. Shared so other sections and integrations (HTTP Traffic,
/// future importers) can open snippets, comparisons and timelines, and so text survives switching
/// sections. Kept in memory only.
@MainActor
final class CodeStudioModel: ObservableObject {
    static let shared = CodeStudioModel()

    @Published var code = CodeSamples.httpResponse
    @Published var title = ""
    @Published var highlightLines = ""
    @Published var base = CodeSamples.compareBefore
    @Published var change = CodeSamples.compareAfter
    @Published var baseLabel = "ORIGINAL REQUEST"
    @Published var changeLabel = "TAMPERED REQUEST"
    @Published var showDiff = true
    @Published var steps: [CodeStep] = CodeSamples.timelineSteps
    @Published var selectedStep: UUID?

    private func prepare(_ mode: CodeShotMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: "code.mode")
        // Imported traffic is HTTP: let detection pick it instead of a previously forced language.
        UserDefaults.standard.set(CodeLanguage.auto.rawValue, forKey: "code.language")
    }

    func openSingle(code: String, title: String) {
        prepare(.single)
        self.code = code
        self.title = title
        highlightLines = ""
    }

    func openCompare(base: String, change: String, baseLabel: String, changeLabel: String, diff: Bool) {
        prepare(.compare)
        self.base = base
        self.change = change
        self.baseLabel = baseLabel
        self.changeLabel = changeLabel
        showDiff = diff
    }

    func openTimeline(_ steps: [CodeStep]) {
        prepare(.timeline)
        self.steps = steps
        selectedStep = steps.first?.id
    }
}
