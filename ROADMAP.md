# SecShot Roadmap

> Made by AI

Ideas collected while building SecShot, seen from the perspective of a security analyst who has
to turn penetration tests and vulnerability assessments into clear, defensible reports.
Items are grouped by theme and roughly ordered by impact inside each group.

**Suggested next iteration:** 1 + 5 + 9 — import from Burp/HAR, finding templates with export,
and redaction inside code text. Together they cover the full loop: capture → clean evidence → report.

## Integrations with pentest tooling

1. ✅ *(0.3.0: Burp XML and HAR import)* **Import from Burp Suite and Caido.** Read Burp's "Save items" XML or `.har` files and build the
   request/response comparison or the flow timeline automatically. Biggest time saver.
2. ✅ *(0.3.0)* **Browser DevTools HAR import** to document complete flows (login → token → action) in one click.
3. **Export to reporting platforms:** Dradis, PlexTrac, Ghostwriter, SysReptor and DefectDojo,
   uploading each piece of evidence to the right finding through their APIs.
4. **Copy as command:** turn an HTTP request into a `curl` command or a Python (`requests`) script
   that reproduces it.

## Report generation

5. **Finding templates:** title, CVSS 4.0, CWE/OWASP mapping, description, impact, reproduction
   steps, remediation and attached evidence, exportable to DOCX, PDF and Markdown with custom templates.
6. **Built-in CVSS calculator**, with the vector and score stamped on the evidence footer.
7. **Per-client projects:** separate library, naming prefix (e.g. `ACME-2026-`) and template per
   engagement, with an encrypted-at-rest library to honor NDAs.
8. **Automatic evidence footer:** timestamp, target/URL, tester and hash as a subtle watermark or
   strip, for chain of custody.

## Evidence quality and safety

9. **Automatic redaction inside code text** (before rendering): tokens, cookies, `Authorization`,
   passwords — keeping a hash so redacted values can still be correlated.
10. **Consistent pseudonymization** of real names across a whole report (domains, IPs, emails), useful
    for talks or sharing with third parties.
11. **RFC 3161 trusted timestamps and a signed manifest** for engagements that may end in legal processes.
12. **Locale-aware PII detection** (e.g. CURP, RFC, Luhn-validated cards, phone numbers) per client country.

## Automated analysis

13. **More HTTP analyzers:** cookie prefixes (`__Host-` / `__Secure-`), reflected CORS origins,
    disclosed versions matched against known CVEs, JWT decoding (`alg: none`, weak signatures, long expiry).
14. **Explain the diff:** in a comparison, draft text such as "After changing the `role` parameter the
    server returned 200 and granted administrator privileges", ready for the reproduction steps.
15. **Context-aware capture:** record the active browser/Burp URL and window title as evidence metadata.

## Workflow

16. **Short GIF/video recording** of a flow (e.g. an XSS firing) with the same redaction and focus tools.
17. **Scrolling capture** for long pages or responses.
18. **Configurable hotkeys** and Shortcuts.app / AppleScript actions for scripting.
19. ◐ *(0.4.0: text capture to plain text / Markdown / CSV)* **OCR to code:** turn a terminal screenshot into an editable, styled code snippet.
20. **Retest mode:** link a finding's original evidence with the retest evidence and generate the
    remediation before/after automatically.

## Platform

21. **Windows and Linux ports**, likely with a shared Rust core and a Tauri UI (Wayland capture and
    global hotkeys require the XDG desktop portals).
22. **Developer ID signing and notarization** so releases install without Gatekeeper warnings.
