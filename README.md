<div align="center">

# SecShot

**Evidence screenshots for security assessments on macOS.**

Capture, redact, annotate, compare and export screenshots for penetration testing reports,
with the speed of the native macOS screenshot tool and the workflow of a dedicated capture suite.

[![CI](https://github.com/JahazielLem/Secshot/actions/workflows/ci.yml/badge.svg)](https://github.com/JahazielLem/Secshot/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/JahazielLem/Secshot?sort=semver)](https://github.com/JahazielLem/Secshot/releases/latest)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)

[Features](#features) ·
[Installation](#installation) ·
[Usage](#usage) ·
[Security model](#security-model) ·
[Building from source](#building-from-source) ·
[License](#license)

<img src="docs/images/02-annotated.png" alt="Annotated evidence with pixelation, hardened blur, solid redaction, arrows and callouts" width="820">

</div>

---

## Why SecShot?

A security assessment produces dozens or hundreds of screenshots. They usually end up on the
Desktop with generic names, contain client secrets in plain sight and have no way to prove they
were not tampered with. SecShot solves that workflow end to end:

- **Consistent evidence naming:** `EVIDENCE-1`, `EVIDENCE-2`, … with no manual renaming.
- **Built-in redaction**, including automatic OCR-based detection of tokens, passwords and keys.
- **Integrity:** every capture is hashed (SHA-256) at capture time, and exports ship with a manifest.
- **Before/after evidence:** side-by-side comparisons, pixel-level diffs and attack-chain timelines.
- **Report-ready output:** macOS-style shadows, metadata-free files, and drag-and-drop into your report.

## Features

### Capture
| | |
|---|---|
| **Region / Window / Full screen** | Uses the native macOS capture engine, so selection behaves exactly like ⌘⇧4. |
| **Global hotkeys** | ⌃⇧4 region · ⌃⇧5 window · ⌃⇧3 full screen · ⌃⇧2 toggle capture bar. |
| **Floating capture bar** | A ⌘⇧5-style toolbar that docks to any screen edge or floats anywhere, and can be turned on and off. |
| **Timer** | 5 s and 10 s delays to capture menus and hover states. |
| **Menu bar icon** | Every capture action is one click away. |

### Library
- History grouped by day, with search across names and report notes.
- **Naming convention**: set a prefix (e.g. `EVIDENCE-`, `FINDING-`) and each new capture is numbered automatically. Every prefix keeps its own counter, with optional zero padding (`001`).
- Rename, apply the convention to a selection in chronological order, import images, move to Trash.
- Drag any capture straight into Word, Pages, Dradis, etc. The final rendered image is exported on the fly.

### Editor (non-destructive)
- Rectangle, ellipse, arrow, line, text and callouts, highlighter, numbered steps, and crop.
- Move and delete annotations, unlimited undo/redo, and single-key tool shortcuts.
- The original PNG is never modified. Edits are stored separately and flattened on export.

### Security-focused tooling
- **Solid redaction**, **pixelation** and **hardened blur** (pixelates before blurring, so the text cannot be recovered by deblurring).
- **Automatic sensitive-data detection** with on-device OCR (Apple Vision): JWTs, AWS access keys, passwords/tokens/API keys, session cookies, long hex and Base64 secrets, private keys, emails, IPv4/MAC addresses and payment cards. You can choose which categories are detected.
- **Metadata stripping:** exports are re-encoded without EXIF, GPS or author data.
- **Chain of custody:** SHA-256 of every original capture, plus an `evidence-manifest.csv` and `evidence-report.md` on batch export.

<p align="center">
  <img src="docs/images/08-auto-redaction.png" alt="Automatic redaction of detected secrets" width="640">
</p>

### Comparison & timeline
- Choose a **BASE** and a **CHANGE** capture, or capture straight into either slot.
- Layouts: **side by side**, **stacked**, **highlighted differences** (pixel diff with boxed regions and a change percentage) and an interactive **before/after slider**.
- **Timeline** mode chains N captures into a numbered, timestamped attack narrative.
- Results are saved back to the library as new evidence, following the naming convention.

<p align="center">
  <img src="docs/images/05-diff.png" alt="Before/after comparison with highlighted differences" width="820">
</p>

<details>
<summary><b>More examples</b>: timeline, slider and macOS shadow</summary>
<br>
<p align="center">
  <img src="docs/images/06-timeline.png" alt="Timeline of three steps" width="480">
  <img src="docs/images/07-split.png" alt="Before/after slider export" width="640">
  <img src="docs/images/04-shadow.png" alt="macOS-style shadow decoration" width="640">
</p>
</details>

### Output
- macOS-style window shadow and rounded corners, which you can toggle; transparent or white background.
- PNG or JPEG, optional 144 DPI tagging so Retina captures paste at the right size.
- Copy to clipboard, export a single image, or batch export with manifest.

> The images above were generated by SecShot's own rendering engine (`--selftest`) using fake data.

## Installation

### Download (recommended)

1. Download the latest **`SecShot-x.y.z.dmg`** from the [Releases page](https://github.com/JahazielLem/Secshot/releases/latest).
2. Open the DMG and drag **SecShot** into **Applications**.
3. Launch SecShot. macOS will ask for **Screen Recording** permission:
   *System Settings → Privacy & Security → Screen Recording → enable SecShot*, then relaunch the app.

> [!IMPORTANT]
> Builds that are not notarized by Apple are blocked by Gatekeeper on first launch.
> Open *System Settings → Privacy & Security* and click **Open Anyway**, or run:
> ```bash
> xattr -dr com.apple.quarantine /Applications/SecShot.app
> ```

**Verify the download** using the `SHA256SUMS.txt` file published with each release:

```bash
shasum -a 256 -c SHA256SUMS.txt
```

### Requirements

- macOS 14 Sonoma or later
- Apple Silicon or Intel

## Usage

### Hotkeys

| Shortcut | Action |
|---|---|
| ⌃⇧4 | Capture a region |
| ⌃⇧5 | Capture a window / app |
| ⌃⇧3 | Capture the full screen |
| ⌃⇧2 | Show / hide the floating capture bar |
| ⌘1 / ⌘2 | Open the Library / Comparison window |
| ⌘, | Settings |

### Editor shortcuts

| Key | Tool | Key | Tool |
|---|---|---|---|
| `V` | Select / move | `N` | Numbered step |
| `R` | Rectangle | `P` | Pixelate |
| `A` | Arrow | `B` | Hardened blur |
| `T` | Text | `X` | Solid redaction |
| `H` | Highlighter | `C` | Crop |
| `⌫` | Delete selection | `⌘Z` / `⇧⌘Z` | Undo / Redo |

`⌘E` exports and `⇧⌘C` copies the final image.

### Typical workflow

1. Set your prefix in the sidebar (for example `EVIDENCE-`).
2. Capture with a hotkey or the capture bar; the editor opens on the new capture.
3. Click **Detect & Redact Sensitive Data**, review the result, and add arrows, callouts and notes.
4. For a change you exploited, open **Compare**, capture the BASE and the CHANGE, and save the diff.
5. Select the evidence and choose **Export with Manifest…** to get the images, the CSV manifest and a Markdown report.

### Launch at login

Enable *Settings → General → Open SecShot at login*. At login, SecShot starts in the background
with only the capture bar (if enabled), the menu bar icon and the hotkeys, and no windows.

## Security model

- **Everything stays local.** SecShot makes no network connections. Captures live in
  `~/Pictures/SecShot` alongside a `library.json` index.
- **Originals are preserved.** The unedited PNG and its SHA-256 are kept for chain of custody, and
  exports are always flattened, so no redacted pixels survive in layers.
- **Choose the right redaction.** Pixelation and blur reduce legibility; for passwords, tokens and
  private keys use **solid redaction**, which is irreversible.
- **Review automatic redaction.** OCR-based detection is a safety net, not a guarantee. Always
  review the output before sharing it.
- The capture bar is excluded from screenshots and hidden while a capture is in progress.

## Building from source

Only the **Xcode Command Line Tools** are required; the full Xcode app is not needed.

```bash
git clone https://github.com/JahazielLem/Secshot.git
```

```bash
cd Secshot && ./build.sh
```

The app is written to `build/SecShot.app`.

### Install locally as a regular app

```bash
scripts/create-signing-cert.sh
```

```bash
scripts/install.sh
```

`create-signing-cert.sh` runs once. It creates a local code-signing identity so macOS keeps the
Screen Recording permission across rebuilds (ad-hoc signatures lose it every time).
`install.sh` builds, copies the app to `/Applications` and registers it with Launchpad and Spotlight.

### Build options

| Variable | Default | Description |
|---|---|---|
| `VERSION` | `0.1.0` | App version |
| `BUILD_NUMBER` | `1` | Build number |
| `UNIVERSAL` | `0` | `1` builds a universal arm64 + x86_64 binary (requires Xcode) |
| `SIGN_IDENTITY` | auto | Signing identity; `Developer ID Application: …` enables hardened runtime and notarization |

### Self-test

```bash
build/SecShot.app/Contents/MacOS/SecShot --selftest /tmp/secshot-selftest
```

Renders sample annotations, decorations, diffs, timelines and automatic redaction without
needing screen access. CI runs it on every push.

### Project layout

```
Sources/SecShot/
├── SecShotApp.swift        App entry point, menu bar item, commands
├── CaptureBar.swift        Floating ⌘⇧5-style capture bar
├── CaptureService.swift    Region / window / full-screen capture
├── LibraryStore.swift      Persistence, history and naming convention
├── Renderer.swift          Flattening, redaction, shadow, composites, diff
├── SensitiveDetector.swift OCR + secret patterns
├── ExportService.swift     Metadata-free export, clipboard, manifest
├── HotKeys.swift           Global hotkeys (Carbon)
├── LoginItem.swift         Background launch at login
└── Views/                  Library, editor, comparison and settings UI
```

See [docs/DESIGN.md](docs/DESIGN.md) for the design rationale and roadmap.

## Releasing

Releases are built by GitHub Actions ([`release.yml`](.github/workflows/release.yml)) when a
version tag is pushed:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

The workflow builds a universal binary, runs the self-test, packages a DMG and a ZIP with
SHA-256 checksums and publishes the GitHub release. Third-party actions are pinned by commit,
and signing secrets only ever exist in a temporary keychain that is deleted afterwards.

To ship builds that install without Gatekeeper warnings, add these repository secrets
(*Settings → Secrets and variables → Actions*). An
[Apple Developer Program](https://developer.apple.com/programs/) membership is required:

| Secret | Value |
|---|---|
| `MACOS_CERT_P12` | *Developer ID Application* certificate and private key as a base64 `.p12` (`base64 -i cert.p12 \| pbcopy`) |
| `MACOS_CERT_PASSWORD` | Password of the `.p12` |
| `MACOS_SIGN_IDENTITY` | e.g. `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_ID` | Apple ID of the developer account |
| `APPLE_TEAM_ID` | 10-character Team ID |
| `APPLE_APP_PASSWORD` | App-specific password from appleid.apple.com |

Without these secrets the release is still published, but it is ad-hoc signed.

## Roadmap

- Report export to DOCX / PDF templates
- Scrolling capture and screen recording (video / GIF)
- Magnifier callouts and curved arrows
- Per-engagement projects with encrypted-at-rest libraries
- RFC 3161 trusted timestamps for evidence
- Configurable hotkeys
- Windows and Linux ports

## Contributing

Issues and pull requests are welcome. Please run `./build.sh` and the self-test before opening a
pull request, and keep all user-facing text in English.

## License

SecShot is free software: you can redistribute it and/or modify it under the terms of the
**GNU General Public License v3.0 or later**. See [LICENSE](LICENSE) for the full text.

This project was developed with AI assistance; source files carry a `Made by AI` notice.
