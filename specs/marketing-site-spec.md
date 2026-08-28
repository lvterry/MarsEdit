# Yanmo Landing Page Spec

## Goal

Give visitors one clear explanation of Yanmo, a direct public-beta download,
and a real view of the app.

## Scope

The first release is one responsive page hosted by GitHub Pages from `main:/docs`
at `https://yanmo.app`.

The page includes only:

- Product description.
- Public-beta download.
- Three app screenshots.
- Footer credit.

No trial limit, payment gate, account, analytics, feedback form, navigation, or
additional marketing sections are included.

## Content

Description:

> Yanmo is a native Markdown editor for macOS, with a focused editor, live
> preview, local file workflows, templates, themes, and clean HTML/PDF export.

Primary action:

- Label: `Download public beta`
- Target: `https://github.com/lvterry/Yanmo/releases/download/v0.9/Yanmo-0.9.dmg`
- Note: `Version 0.9 · macOS 13 or later`

Footer:

> Made by Jellyrbt. All rights reserved.

## Layout

Desktop uses a two-column hero:

- Left: description and download action.
- Right: screenshot carousel.
- Bottom: centered footer.

The page stacks into one column when the content no longer fits. The description
and download remain first in source and visual order.

## Screenshots

The carousel contains real captures of:

1. Split editor and live preview.
2. Editor-only mode.
3. Preview-only mode.

Controls use three dots below the screenshot. The carousel advances every five
seconds with a 240 ms crossfade. It pauses during pointer or keyboard interaction
and while the page is hidden. Reduced-motion users get no autoplay or crossfade.

## Visual Direction

- Typeface: self-hosted Source Sans Pro, regular and semibold WOFF2.
- Palette: near-white background, dark neutral text, muted footer.
- Product screenshot: subtle border, rounded corners, restrained shadow.
- One visually primary action.
- No gradients, stock imagery, or visible page frame.

## Accessibility and Performance

- Download and carousel controls have visible focus states.
- Dot controls are 1.75 rem square with 44 × 44 px hit areas and descriptive
  accessible names.
- Hidden screenshots leave the tab order and accessibility tree.
- Left and right arrows move between carousel controls.
- Core copy and download remain usable without JavaScript.
- Font and first screenshot are preloaded.
- Screenshots declare dimensions to prevent layout shift.
- Hover styles apply only to hover-capable pointers.
- Reduced-motion preferences disable autoplay, crossfade, and pressed translation.

## Hosting

- Site files live in `docs/`.
- Product documents live in `specs/`.
- `docs/CNAME` remains `yanmo.app`.
- `docs/appcast.xml` remains at the site root for Sparkle updates.
- Font redistribution retains its OFL license in `docs/assets/fonts/OFL.txt`.

## Acceptance Criteria

- The first view identifies Yanmo as a native macOS Markdown editor.
- The public-beta button downloads Yanmo 0.9.
- All three screenshot controls work with pointer and keyboard input.
- The slideshow advances automatically and pauses during interaction.
- The layout works without horizontal overflow on desktop and mobile.
- Source Sans Pro renders from local WOFF2 files.
- `index.html` and `appcast.xml` remain reachable from the Pages root.
