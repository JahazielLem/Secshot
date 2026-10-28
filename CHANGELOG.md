# Changelog

> Made by AI

## 0.4.0

### Added
- **Text Capture (OCR)** — press **⌘⇧2** from any app, select an area, and its text is recognized
  on-device (Apple Vision) and copied to the clipboard as **Plain text**, **Markdown** or **CSV**.
  - Tables are detected from aligned columns: Markdown tables, tab-separated plain text (pastes as
    columns in spreadsheets) or CSV rows. Grid lines read as `|` are cleaned from cells.
  - Markdown output keeps bullet and numbered lists and turns larger text into headings.
  - A notice confirms what was copied; the captured image is never written to disk.
  - New **Text** section (⌘6): detected text boxes over the image, editable output, format switch,
    OCR from an image file or the clipboard, recent captures (in memory) and "Add Image to Library".
  - Settings: default format, recognition language, language correction (turn it off for code,
    hashes and tokens), notice and open-after-capture options.
  - Tables are rebuilt as a grid: columns from the cells' left edges, rows anchored on the first
    column. Wrapped (multi-line) cells — common in PDFs and Word documents — become a single cell, and
    roughly aligned columns (proportional fonts, space padding) are kept apart.
  - When no text is found only a notice is shown; nothing is copied or added to the history.
- **Copy to clipboard per capture type** (*Settings → Copy to Clipboard*): region, window,
  full-screen, comparison/timeline and text captures each have their own switch. The previous single
  “copy after capturing” setting is migrated to the three screenshot modes.
- `--ocr <image> [plain|markdown|csv]` and `--ocr-sample` command-line helpers.

## 0.3.0

### Added
- **HTTP Traffic** section (⌘5, ⌃⇧8 from anywhere, ⇧⌘I to import): import Burp Suite “Save items”
  XML, HAR files (browser DevTools, Caido, ZAP) and raw HTTP requests/responses, then turn them into
  a snippet, a before/after comparison of two requests or responses, or a timeline.
  - Credentials (cookies, `Authorization`, API keys, password/token fields) are redacted by default.
  - JSON bodies are pretty-printed and long bodies are cut to a configurable number of lines.
  - Burp XML is parsed with external entities disabled (no XXE); imported traffic stays in memory only.
- `--traffic` command-line helper to list items from an export and compare two of them.

### Changed
- **Single main window** with a navigation rail (Library, Compare, Code, Traffic) instead of one
  window per feature. Settings and per-image editors keep their own windows.
- Code Snippet content now lives in a shared model, so other sections can open snippets and text is
  kept when switching sections.

### Fixed
- The permission alert and repair could run from a bare binary started in a terminal, and the repair
  fell back to a hard-coded bundle identifier. Both now only act inside the installed app bundle.
- Unknown command-line options now print the available options and exit instead of launching the app.

## 0.2.1

### Fixed
- Minified JSON (standalone or as an HTTP body) was drawn as a single wrapped line. Code Snippet now
  pretty-prints it with indentation, preserving key order and literal values, so comparisons diff
  field by field. Can be turned off with **Format JSON**.

## 0.2.0

### Added
- **Code Snippet window** (⌘4, ⌃⇧6 from anywhere): styled images of code, terminal sessions and
  HTTP traffic.
  - Syntax highlighting for HTTP, JSON, shell sessions, Python, JavaScript/TypeScript, C-like
    languages, SQL and XML/HTML, with auto-detection.
  - 12 built-in themes, including the four Catppuccin flavors; 4 window frames; gradient, solid or
    transparent backgrounds.
  - **HTTP security-header analysis** with per-header markers and a findings summary.
  - **Compare** mode with a line diff and intra-line emphasis, and **Timeline** mode; optional arrows.
  - **Redact** (⇧⌘R or right-click): replaces the selection with a configurable marker such as
    `[REDACTED]`, highlighted in the image.
  - Import VS Code and TextMate themes, edit any theme's colors, export themes as JSON.
- **External Images** tab in Comparison & Timeline (⌘3): compare or chain images not taken with
  SecShot without adding them to the evidence library.
- **Focus spotlight** (S) and **zoom / magnifier** (Z) editor tools; both read the redacted image, so
  secrets are never revealed or enlarged.
- Shortcuts: ⌃⇧7 opens Comparison & Timeline from anywhere; in Code Snippet ⌥⌘1/2/3 switch modes,
  ⇧⌘C copies the image, ⌘E exports and ⌘S saves as evidence; ⇧⌘C copies the comparison result.
- Command-line helpers: `--codeshot`, `--codecompare`, `--codetimeline`, `--permission-status`,
  `--login-status`.

### Fixed
- Launch at login was blocked by macOS ("Launch Constraint Violation") because login agents require
  an Apple Team ID. SecShot now uses the main-app login item, detects the login launch itself and
  migrates the old registration automatically.
- An index written by a newer version is no longer overwritten when it cannot be read; a backup copy
  is kept instead.

## 0.1.0

- Initial release: region, window and full-screen capture; evidence library with naming convention;
  non-destructive editor with redaction and OCR-based secret detection; before/after comparison with
  pixel diff; timelines; macOS-style shadow; metadata-free export with SHA-256 manifest; floating
  capture bar; GitHub Actions CI and release pipeline.
