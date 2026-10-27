// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Imported HTTP traffic. Kept in memory only: it is never written to disk by SecShot.
@MainActor
final class TrafficStore: ObservableObject {
    static let shared = TrafficStore()

    @Published private(set) var exchanges: [HTTPExchange] = []
    @Published var selection: Set<HTTPExchange.ID> = []
    @Published var status = ""
    @Published var importing = false
    @Published var error: String?

    func importWithPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.xml, .json, .plainText, .data]
        panel.message = "Choose a Burp Suite “Save items” XML, a HAR file or raw HTTP requests/responses."
        panel.prompt = "Import"
        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls)
    }

    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        importing = true
        let start = (exchanges.map(\.index).max() ?? 0) + 1
        Task {
            let (items, summaries, errors) = await Task.detached(priority: .userInitiated) { () -> ([HTTPExchange], [String], [String]) in
                var items: [HTTPExchange] = []
                var summaries: [String] = []
                var errors: [String] = []
                var next = start
                for url in urls {
                    do {
                        let r = try TrafficImporter.load(url, startIndex: next)
                        items += r.exchanges
                        next += r.exchanges.count
                        summaries.append("\(r.exchanges.count) from \(url.lastPathComponent) (\(r.format))")
                    } catch {
                        errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                return (items, summaries, errors)
            }.value
            exchanges += items
            importing = false
            status = summaries.isEmpty ? "" : "Imported " + summaries.joined(separator: ", ")
            if !errors.isEmpty { error = errors.joined(separator: "\n") }
            if selection.isEmpty, let first = items.first { selection = [first.id] }
        }
    }

    func clear() {
        exchanges = []
        selection = []
        status = "Traffic cleared from memory."
    }

    func remove(_ ids: Set<HTTPExchange.ID>) {
        exchanges.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
    }
}

enum MessagePart { case request, response, both }

/// Imported requests: pick one for a snippet, two for a comparison, or several for a timeline.
struct TrafficView: View {
    @ObservedObject private var traffic = TrafficStore.shared
    @ObservedObject private var studio = CodeStudioModel.shared
    @ObservedObject private var nav = AppNavigation.shared
    @AppStorage("traffic.redact") private var redact = true
    @AppStorage("traffic.bodyLines") private var bodyLines = 40
    @AppStorage(Prefs.redactionText) private var marker = "[REDACTED]"
    @ViewState private var search = ""
    @ViewState private var showResponse = false
    @ViewState private var dropTargeted = false

    private var filtered: [HTTPExchange] {
        guard !search.isEmpty else { return traffic.exchanges }
        return traffic.exchanges.filter { e in
            [e.method, e.host, e.path, e.statusText, e.mime, e.comment, "#\(e.index)"]
                .contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    private var selected: [HTTPExchange] {
        traffic.exchanges.filter { traffic.selection.contains($0.id) }.sorted { $0.index < $1.index }
    }

    private var formatOptions: TrafficFormatter.Options {
        TrafficFormatter.Options(redact: redact, marker: marker.isEmpty ? "[REDACTED]" : marker, bodyLineLimit: bodyLines)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if traffic.exchanges.isEmpty {
                emptyState
            } else {
                HSplitView {
                    table.frame(minWidth: 520)
                    detail.frame(minWidth: 420, idealWidth: 520)
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            traffic.importFiles(urls)
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .alert("Import", isPresented: Binding(get: { traffic.error != nil }, set: { if !$0 { traffic.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(traffic.error ?? "") }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Button { traffic.importWithPanel() } label: { Label("Import…", systemImage: "square.and.arrow.down") }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .help("Import Burp Suite XML, HAR or raw HTTP files (⇧⌘I)")
            if traffic.importing { ProgressView().controlSize(.small) }
            Text(traffic.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            TextField("Filter: host, path, status, #id…", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 230)
            Toggle("Redact credentials", isOn: $redact)
                .help("Cookies, Authorization, API keys and password/token fields are replaced with \(marker) when sent to Code")
            Stepper("Body: \(bodyLines == 0 ? "all" : "\(bodyLines)") lines", value: $bodyLines, in: 0...400, step: 10)
                .help("Maximum body lines per message (0 = no limit)")
                .fixedSize()
            Button(role: .destructive) { traffic.clear() } label: { Image(systemName: "trash") }
                .disabled(traffic.exchanges.isEmpty)
                .help("Clear imported traffic from memory")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.left.arrow.right.square").font(.system(size: 52)).foregroundStyle(.secondary)
            Text("Import HTTP traffic").font(.title2.bold())
            Text("Drop a file here or click Import.").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Label("**Burp Suite:** Proxy › HTTP history (or Repeater/Logger), select the requests → right-click → **Save items** (XML).", systemImage: "1.circle")
                Label("**Browser / Caido / ZAP:** export a **HAR** file.", systemImage: "2.circle")
                Label("**Raw:** a .txt or .http file with a request or a response.", systemImage: "3.circle")
            }
            .font(.callout)
            .frame(maxWidth: 560, alignment: .leading)
            Button { traffic.importWithPanel() } label: { Label("Import…", systemImage: "square.and.arrow.down") }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            Text("Imported traffic stays in memory only. XML is parsed with external entities disabled.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Table

    private var table: some View {
        Table(filtered, selection: $traffic.selection) {
            TableColumn("#") { e in Text("\(e.index)").monospacedDigit().foregroundStyle(.secondary) }
                .width(min: 30, ideal: 40, max: 60)
            TableColumn("Method") { e in Text(e.method).font(.system(.body, design: .monospaced)).bold() }
                .width(min: 50, ideal: 64, max: 90)
            TableColumn("Host") { e in Text(e.host).lineLimit(1) }
                .width(min: 80, ideal: 130)
            TableColumn("Path") { e in Text(e.path).font(.system(.body, design: .monospaced)).lineLimit(1) }
                .width(min: 120, ideal: 210)
            TableColumn("Status") { e in Text(e.statusText).monospacedDigit().foregroundStyle(statusColor(e.status)) }
                .width(min: 44, ideal: 52, max: 70)
            TableColumn("Type") { e in Text(e.mime).lineLimit(1).foregroundStyle(.secondary) }
                .width(min: 40, ideal: 60, max: 140)
            TableColumn("Length") { e in
                Text(ByteCountFormatter.string(fromByteCount: Int64(e.responseLength), countStyle: .file))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 62, max: 100)
            TableColumn("Comment") { e in Text(e.comment).lineLimit(1).foregroundStyle(.secondary) }
                .width(min: 60, ideal: 90)
        }
        .contextMenu(forSelectionType: HTTPExchange.ID.self) { ids in
            if !ids.isEmpty {
                Button("Remove from List", role: .destructive) { traffic.remove(ids) }
            }
        } primaryAction: { ids in
            if ids.count == 1 { snippet(.request) }
        }
    }

    private func statusColor(_ status: Int?) -> Color {
        guard let s = status else { return .secondary }
        switch s {
        case 200..<300: return .green
        case 300..<400: return .teal
        case 400..<500: return .orange
        default: return .red
        }
    }

    // MARK: Detail

    private var detail: some View {
        VStack(spacing: 0) {
            actionBar
            Divider()
            if selected.count == 1, let e = selected.first {
                VStack(spacing: 0) {
                    Picker("", selection: $showResponse) {
                        Text("Request").tag(false)
                        Text("Response").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(8)
                    ScrollView([.vertical, .horizontal]) {
                        Text(TrafficFormatter.text(showResponse ? e.response : e.request, formatOptions).prefix(60_000))
                            .font(.system(size: 11.5, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                }
            } else if selected.count > 1 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(selected.count) items selected").font(.headline)
                        ForEach(selected) { e in
                            HStack {
                                Text("#\(e.index)").monospacedDigit().foregroundStyle(.secondary)
                                Text("\(e.method) \(e.path)").font(.system(.callout, design: .monospaced)).lineLimit(1)
                                Spacer()
                                Text(e.statusText).foregroundStyle(statusColor(e.status))
                            }
                        }
                    }
                    .padding(12)
                }
            } else {
                Text("Select a request to preview it.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Menu {
                    Button("Request") { snippet(.request) }
                    Button("Response") { snippet(.response) }
                    Button("Request and Response Side by Side") { snippet(.both) }
                } label: { Label("Snippet", systemImage: "chevron.left.forwardslash.chevron.right") }
                    .disabled(selected.count != 1)
                Menu {
                    Button("Compare Requests") { compare(.request) }
                    Button("Compare Responses") { compare(.response) }
                } label: { Label("Compare", systemImage: "rectangle.split.2x1") }
                    .disabled(selected.count != 2)
                Menu {
                    Button("Requests") { timeline(.request) }
                    Button("Responses") { timeline(.response) }
                    Button("Requests and Responses") { timeline(.both) }
                } label: { Label("Timeline", systemImage: "list.number") }
                    .disabled(selected.count < 2)
            }
            .fixedSize()
            Text(hint).font(.caption).foregroundStyle(.secondary)
        }
        .controlSize(.small)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hint: String {
        switch selected.count {
        case 0: return "Select 1 item for a snippet, 2 to compare them, or more for a timeline (⌘-click)."
        case 1: return "Double-click a row to open its request in Code."
        case 2: return "Compare highlights the exact lines and values that changed."
        default: return "The timeline follows the order of the # column."
        }
    }

    // MARK: Actions

    private func text(_ data: Data?) -> String { TrafficFormatter.text(data, formatOptions) }

    private func responseLabel(_ e: HTTPExchange) -> String {
        "#\(e.index) " + (TrafficFormatter.firstLine(e.response).split(separator: " ").dropFirst().joined(separator: " "))
    }

    private func snippet(_ part: MessagePart) {
        guard let e = selected.first else { return }
        switch part {
        case .request:
            studio.openSingle(code: text(e.request), title: "\(e.method) \(e.host)\(e.path)")
        case .response:
            studio.openSingle(code: text(e.response), title: "Response · \(e.method) \(e.host)\(e.path)")
        case .both:
            studio.openCompare(base: text(e.request), change: text(e.response),
                               baseLabel: "REQUEST #\(e.index)", changeLabel: "RESPONSE #\(e.index)", diff: false)
        }
        nav.section = .code
    }

    private func compare(_ part: MessagePart) {
        guard selected.count == 2 else { return }
        let a = selected[0], b = selected[1]
        if part == .response {
            studio.openCompare(base: text(a.response), change: text(b.response),
                               baseLabel: responseLabel(a), changeLabel: responseLabel(b), diff: true)
        } else {
            studio.openCompare(base: text(a.request), change: text(b.request),
                               baseLabel: a.shortLabel, changeLabel: b.shortLabel, diff: true)
        }
        nav.section = .code
    }

    private func timeline(_ part: MessagePart) {
        var steps: [CodeStep] = []
        for e in selected {
            if part != .response { steps.append(CodeStep(title: e.shortLabel, code: text(e.request))) }
            if part != .request, e.response != nil {
                steps.append(CodeStep(title: part == .both ? "Response \(responseLabel(e))" : responseLabel(e) + " · \(e.path)",
                                      code: text(e.response)))
            }
        }
        studio.openTimeline(steps)
        nav.section = .code
    }
}
