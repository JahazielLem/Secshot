# SecShot — Design Notes

> Made by AI

SecShot is a screenshot tool for macOS built for writing security assessment reports
(penetration tests, audits, bug bounty). It combines the immediacy of the native macOS
screenshot tool with a capture suite workflow: history, editor and export.

## 1. Problem analysis

A security assessment produces dozens or hundreds of screenshots. These are the recurring
problems and how SecShot addresses them:

| Problem | Impact on the report | SecShot's answer |
|---|---|---|
| Generic file names (`Screenshot 2026-…png`) | Manual renaming before referencing evidence | Automatic, persistent `PREFIX-N` convention with one counter per prefix |
| Captures scattered on the Desktop | Lost evidence, no chronological order | Library with per-day history, search and notes |
| Sensitive data in evidence (tokens, passwords, cookies, internal IPs, emails) | Client data leaks when the report is shared | Solid redaction, pixelation and hardened blur, plus automatic OCR detection |
| "Cosmetic" blur | A light blur over text can be reversed or read | Blur pixelates first; solid redaction is recommended for secrets; exports are always flattened |
| Metadata in exported files | May leak host, user or software | Exports are re-encoded without EXIF (DPI only, optionally) |
| Showing a change (before/after an exploit, bypass or escalation) | Two loose images without context | Comparison mode: side by side, stacked, slider and pixel diff with highlighted regions |
| Narrating an attack chain | Many images without sequence | Timeline mode: numbered, timestamped steps with arrows |
| Integrity / chain of custody | Hard to prove evidence was not altered | SHA-256 of the original at capture time, plus a CSV manifest and Markdown report on export |
| Report aesthetics | Flat screenshots | macOS-style shadow decoration that can be toggled |

## 2. Technical decisions

- **Swift + SwiftUI/AppKit**, native app for macOS 14+, built with Swift Package Manager
  (only the Command Line Tools are required). `build.sh` produces `SecShot.app`.
- **Capture engine:** `/usr/sbin/screencapture`, the same tool the system uses. This preserves
  the native UX: region selection, window selection and full screen. Captures are taken without
  a shadow (`-o`); the shadow is added at export time so the toggle is consistent.
- **Non-destructive editing:** the original PNG and its hash stay intact. Annotations, crops and
  redactions are stored as data (`library.json`) and flattened on export.
- **Rendering:** Core Graphics and Core Image (pixelation, blur), plus Vision (OCR) for
  sensitive-data detection. Everything runs on-device.
- **Global hotkeys:** Carbon `RegisterEventHotKey`, which needs no Accessibility permission.
- **Launch at login:** a LaunchAgent bundled in the app and registered with `SMAppService`. It
  passes `--background`, so the app starts without windows.
- **Storage:** `~/Pictures/SecShot/` (images + `library.json`).

## 3. Architecture

```
Sources/SecShot/
├── SecShotApp.swift        App, AppDelegate, status menu, commands
├── WindowManager.swift     Windows (Library, Comparison, Settings)
├── CaptureBar.swift        Floating capture bar (dockable, toggleable)
├── HotKeys.swift           Global hotkeys (Carbon)
├── LoginItem.swift         Background launch at login
├── Models.swift            CaptureItem, Annotation, tools, preferences
├── LibraryStore.swift      Persistence, history, naming, rename, trash
├── CaptureService.swift    Region / window / full screen / timed capture
├── Renderer.swift          Flattening, redaction, shadow, composites, diff, split
├── SensitiveDetector.swift OCR + patterns (JWT, AWS keys, passwords, cookies, IP, email…)
├── ExportService.swift     Metadata-free PNG/JPEG, clipboard, batch + manifest
├── Hashing.swift           SHA-256
├── SelfTest.swift          --selftest and --make-icon command-line utilities
└── Views/
    ├── LibraryView.swift   History, gallery, multi-selection, context menu
    ├── EditorModel.swift   Editor state, undo/redo, detection
    ├── EditorView.swift    Canvas, tools, inspector
    ├── CompareView.swift   Comparison and timeline
    └── SettingsView.swift  Settings
```

## 4. Roadmap

- Report export to DOCX / PDF templates
- Scrolling capture and screen recording (video / GIF)
- Magnifier callouts and curved arrows
- Per-engagement projects with encrypted-at-rest libraries
- RFC 3161 trusted timestamps for evidence
- Configurable hotkeys
- Cross-platform port (Windows / Linux), likely with a shared Rust core and a Tauri UI.
  Wayland capture and global hotkeys need the XDG desktop portals.
