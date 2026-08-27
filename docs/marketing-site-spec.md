# Yanmo Marketing Site Product Spec

## Goal

Build a small, polished marketing website for Yanmo that explains what the app does and gives visitors a direct download for the latest notarized macOS DMG.

Primary outcome: a Mac user understands Yanmo within 30 seconds and can download the app with confidence.

## Product Summary

Yanmo is a native macOS Markdown editor with a live preview. It is built for people who write Markdown files directly and want a fast, local, Mac-like editor rather than a web-first writing tool.

Positioning:

> A native Markdown editor for macOS, with a focused editor, live preview, local file workflows, templates, themes, and clean HTML/PDF export.

## Target Audience

- Developers writing docs, READMEs, notes, changelogs, and specs.
- Technical writers who prefer plain Markdown files.
- Mac users who want a local-first document editor with native controls.
- People who need quick preview and export without adopting a larger knowledge-base app.

## Core Message

Yanmo should feel practical, calm, and trustworthy. The site should avoid overclaiming. It should communicate:

- Native macOS app, not an Electron/web wrapper.
- Local-first Markdown editing.
- Live preview with secure local image handling.
- Export to HTML and PDF.
- Built-in themes and templates.
- Free direct download for macOS 13+.

## Page Structure

Single-page site for the first version.

### 1. Hero

Purpose: explain the app and provide the main download action.

Content:

- Product name: `Yanmo`
- Headline: `A native Markdown editor for macOS`
- Supporting copy: `Write Markdown in a focused editor, preview it live, and export clean HTML or PDF without leaving your Mac.`
- Primary CTA: `Download for macOS`
- Secondary CTA: `View release notes` or `GitHub`
- Trust note under CTA: `Version 0.7 · macOS 13+ · Notarized Developer ID`

Visual:

- Use a real screenshot of the Yanmo app as the first-viewport visual.
- Prefer a desktop screenshot showing editor + preview split view.
- Do not use abstract gradients or stock imagery as the primary product visual.

### 2. Feature Band

Purpose: make the value clear without long reading.

Feature cards or compact rows:

- `Live Preview`: see rendered Markdown as you type.
- `Native Editing`: AppKit text editing with find, undo, spell check, and IME-friendly behavior.
- `Local Images`: drag images into documents and keep assets next to the Markdown file.
- `Themes`: switch between built-in preview themes.
- `Templates`: start common documents from reusable templates.
- `Export`: save Markdown as HTML or PDF.

### 3. Workflow Section

Purpose: show that Yanmo fits normal file-based work.

Recommended layout:

1. Open or create a `.md` file.
2. Write in the editor while preview updates.
3. Drag images in when needed.
4. Export to HTML or PDF.

Keep this section practical and concise. Use product screenshots or short UI crops if available.

### 4. Security / Local-First Section

Purpose: build confidence for a downloaded Mac app.

Copy points:

- Files stay where the user saves them.
- Dragged images are saved into an `Assets/` folder next to the document.
- Local preview uses the app's `yanmo-asset://` scheme rather than raw `file://` links.
- Download is signed and notarized by Apple Developer ID.

Avoid making privacy claims broader than the app supports. Do not say "no network access ever" because WebKit preview may naturally load remote content referenced by a document.

### 5. Download Section

Purpose: repeat the CTA near the end and include concrete compatibility details.

Fields:

- Latest version: `0.7`
- Build: `4`
- Platform: `macOS 13 Ventura or later`
- Architecture: `Apple Silicon and Intel`
- Package: `DMG`
- Signing: `Notarized Developer ID`

Primary button:

- Label: `Download Yanmo 0.7`
- URL source: latest published DMG URL.
- Current local artifact: `/Users/wang39/Developer/Yanmo/build/Release-20260724-yanmo/Yanmo-0.7.dmg`

Optional links:

- `Release notes`
- `Report an issue`

### 6. Footer

Include:

- Product name and copyright.
- Download link.
- Support/contact link.
- Privacy policy link if the app/site collects analytics or emails.
- GitHub link if the repository is public.

## Visual Direction

Tone:

- Quiet, native, focused, practical.
- Should feel like a Mac productivity tool, not a SaaS landing page.

Layout:

- Single-page responsive layout.
- First viewport should clearly show the product name, what it does, and a real product screenshot.
- Use full-width sections with constrained content width.
- Keep cards reserved for feature items only.

Palette:

- Base: near-white / system background.
- Text: high-contrast neutral.
- Accent: restrained blue or graphite; avoid a one-note blue/purple gradient-heavy page.
- Use subtle borders and shadows, closer to macOS surfaces than marketing decoration.

Typography:

- System font stack: `-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif`.
- H1 should be large but not oversized.
- Body copy should be readable and direct.

Imagery:

- Required: one high-quality screenshot of Yanmo's split editor/preview mode.
- Recommended: two smaller screenshot crops for templates/themes/export.
- Avoid stock photos and abstract illustrations.

## Functional Requirements

- Download button points to the latest notarized DMG.
- Download URL should be configurable in one place.
- Show version and minimum macOS requirement near the CTA.
- Site must work without JavaScript for core content and download.
- Responsive at desktop, tablet, and mobile sizes.
- All links must have visible focus states.
- CTA must be reachable above the fold on desktop and mobile.
- No app-specific password, Apple ID credentials, or notarization secrets in the site source.

## Release Requirements

Before updating the public download link:

1. Build Release archive.
2. Sign app with `Developer ID Application: Beijing Wisemind Technologies Co., Ltd (S3J499CH5F)`.
3. Package as DMG.
4. Sign DMG.
5. Notarize with `xcrun notarytool`.
6. Staple with `xcrun stapler staple`.
7. Verify with:

```sh
spctl --assess --type open --context context:primary-signature --verbose=4 Yanmo-<version>.dmg
```

Expected:

```text
accepted
source=Notarized Developer ID
```

## SEO

Primary title:

`Yanmo - Native Markdown Editor for macOS`

Meta description:

`Yanmo is a native macOS Markdown editor with live preview, themes, templates, local image handling, and HTML/PDF export.`

Suggested keywords:

- macOS Markdown editor
- native Markdown editor
- Markdown live preview
- Markdown PDF export
- Markdown HTML export

Open Graph:

- `og:title`: `Yanmo - Native Markdown Editor for macOS`
- `og:description`: same as meta description
- `og:image`: product screenshot or branded social preview
- `og:type`: `website`

## Analytics

Track only minimal product metrics:

- Page views.
- Download button clicks.
- External link clicks.

If analytics are added, include a privacy note and avoid collecting document content, filenames, or local paths.

## Non-Goals For V1

- User accounts.
- Payment or licensing.
- Blog.
- Documentation portal.
- Auto-update feed.
- App Store landing page.
- Multi-page marketing funnel.

## Open Questions

- Where will the DMG be hosted: GitHub Releases, static hosting, or object storage?
- Should the site include a public GitHub link?
- What support email or issue tracker should be shown?
- Is Yanmo free permanently, or should copy avoid pricing commitments?
- Should the site be bilingual, or English-only for v1?

## Acceptance Criteria

- A visitor can identify Yanmo as a native macOS Markdown editor within the first viewport.
- The page includes a visible, working DMG download CTA.
- The page states version, macOS requirement, and notarization status.
- The page uses real product visuals.
- The site is usable on mobile and desktop.
- No secrets or local-only credentials are present in source.
- Downloaded DMG passes Gatekeeper verification after publishing.
