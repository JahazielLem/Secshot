# Changelog

> Made by AI

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
