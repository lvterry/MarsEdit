# Yanmo

Native macOS markdown editor with live preview. SwiftUI shell + AppKit text editing + WebKit preview. Targets macOS 13+, Swift 5.9. ~3K LOC.

## Build & run

The `.xcodeproj` is **generated** by [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`. Don't hand-edit the project file.

```sh
xcodegen generate          # after editing project.yml
open Yanmo.xcodeproj
xcodebuild -scheme Yanmo -destination 'platform=macOS' test   # run the test suite
```

Only third-party dependency: `swift-markdown` (Apple, SwiftPM, declared in `project.yml`). No CI.

Keep only `Yanmo.xcodeproj` at the repository root. Extra `.xcodeproj` directories make `xcodebuild -scheme Yanmo ...` ambiguous unless `-project Yanmo.xcodeproj` is supplied.

## Tests

XCTest target `YanmoTests` (`YanmoTests/`) covers pure-logic and security-sensitive modules: `FrontMatter`, `OutlineItem` parsing, `MarkdownRenderer` (sanitization + local-asset path resolution), and `TemplateStore` (seeding + listing). UI, AppKit, and WebKit layers are not unit-tested — verify those by running the app. When changing renderer sanitization or `LocalAssetSchemeHandler` containment, add a corresponding test.

**Run the test suite before committing any code change**, even ones that look UI-only — `MarkdownRenderer`, `FrontMatter`, and `OutlineItem` are imported widely and a refactor elsewhere can break them. Use `xcodebuild -scheme Yanmo -destination 'platform=macOS' test`. Don't commit on a red suite.

`YanmoTests` is hosted inside `Yanmo.app`, so the test target must use the same Apple Developer Team as the app target. Keep the test target signing settings in `project.yml` (`CODE_SIGN_IDENTITY: Apple Development`, `CODE_SIGN_STYLE: Automatic`, `DEVELOPMENT_TEAM: S3J499CH5F`) or the test bundle can fail to load with a Team ID mismatch.

## Layout

```
Yanmo/
├── App/             @main, DocumentGroup, menu commands
├── Document/        ReferenceFileDocument
├── Models/          AppSettings, Theme, ViewMode, OutlineItem, TemplateStore
├── Views/           SwiftUI views + NSViewRepresentable wrappers
├── Rendering/       Markdown → HTML, syntax highlighting, front matter, asset scheme
├── Export/          HTML and PDF exporters
├── Preferences/     Settings UI
├── Resources/Themes/     *.css for preview themes
└── Resources/Templates/  *.md seeds for File ▸ New from Template
```

## Data flow

```
text  ──>  MarkdownDocument  ──>  EditorView (NSTextView)
                              \
                               ──>  MarkdownRenderer  ──>  PreviewView (WKWebView)
                                                      \
                                                       ──>  HTMLExporter / PDFExporter
```

## File map

| File | Purpose |
| --- | --- |
| `App/YanmoApp.swift` | `@main`, DocumentGroup, menu commands |
| `Document/MarkdownDocument.swift` | Plain-text doc; UTF-8 with ISO-8859-1 fallback |
| `Models/AppSettings.swift` | `@AppStorage` singleton — font, theme, view mode, appearance |
| `Models/Theme.swift` | Six built-in themes; CSS lookup in `Resources/Themes/` |
| `Models/ViewMode.swift` | split / editor-only / preview-only — persisted; defers WKWebView init |
| `Models/OutlineItem.swift` | Heading parser for the sidebar |
| `Models/TemplateStore.swift` | User templates dir (`~/Library/Application Support/Yanmo/Templates/`), bundle-seeded on first launch |
| `Views/ContentView.swift` | Layout, outline, export dialogs, toasts |
| `Views/EditorView.swift` | **Largest file.** NSTextView wrapper, IME-safe, debounced highlight, image drag-drop |
| `Views/PreviewView.swift` | WKWebView; HTML shell loaded once, body injected via JS |
| `Views/OutlineSidebar.swift` · `ToolbarView.swift` · `StatusBarView.swift` | UI chrome |
| `Rendering/MarkdownRenderer.swift` | swift-markdown visitor → sanitized HTML |
| `Rendering/SyntaxHighlighter.swift` | Regex-based NSTextView attributes; skips fenced code & front matter |
| `Rendering/FrontMatter.swift` | Minimal YAML-like parser, `---` / `...` delimiters at doc start |
| `Rendering/LocalAssetSchemeHandler.swift` | `yanmo-asset://` → local file resolver (preview only) |
| `Export/HTMLExporter.swift` · `Export/PDFExporter.swift` | Render + theme CSS → file |
| `Preferences/PreferencesView.swift` | Settings UI |

## Conventions & gotchas

- **XcodeGen.** Edit `project.yml`, then re-run `xcodegen generate`. Never edit the `.xcodeproj` directly.
- **Signing.** `S3J499CH5F` is the current Apple Developer Team. Debug tests use Apple Development signing for the test bundle; direct-download releases use `Developer ID Application: Beijing Wisemind Technologies Co., Ltd (S3J499CH5F)`.
- **`DocumentSession` event flow.** Format actions, view-mode cycling, export, scroll-to-heading, and toasts flow through the per-window `DocumentSession` (typed `PassthroughSubject<Event, Never>`). Children get it via `@EnvironmentObject`; menu commands target the active window via `@FocusedValue(\.documentSession)` published from `ContentView` with `focusedSceneValue`. To find handlers, search `session.events.sink` and `.onReceive(session.events)`. Don't use `NotificationCenter` for app-internal events — that's reserved for AppKit system notifications (e.g. `NSWindow.didEndSheetNotification`).
- **NSTextView, not SwiftUI `TextEditor`.** Chosen for IME, find bar, performance. Don't replace.
- **Debounced, scoped syntax highlighting (~150ms).** Must skip fenced code blocks and front matter regions. During IME composition (`textView.hasMarkedText()`) highlighting and updates are deferred — preserve this when changing the editor.
- **Preview HTML shell loads once.** Subsequent updates inject the body via JS to preserve scroll position. Don't reload on every keystroke.
- **Local images use `yanmo-asset://`.** `LocalAssetSchemeHandler` resolves relative paths against the document directory. Don't emit raw `file://` URLs in rendered HTML — the CSP allows `yanmo-asset:` (see `MarkdownRenderer.assetCSPPolicy`).
- **HTML output is sanitized.** `javascript:` / `vbscript:` blocked; `data:` restricted to whitelisted image MIME types. Preserve sanitization when extending the renderer.
- **Adding a theme.** Drop a CSS file in `Yanmo/Resources/Themes/` and register it in `Theme.swift`.
- **Adding a built-in template.** Drop a `.md` file in `Yanmo/Resources/Templates/`. It seeds `~/Library/Application Support/Yanmo/Templates/` on first launch *only* — once the user directory exists, the bundle copy is ignored and users own the directory. Display name in the menu = filename without `.md`; no front matter is parsed for the label.
- **Settings.** Persisted via `@AppStorage` (UserDefaults). No iCloud sync.
- **Image drag-drop.** Dropped images are saved as PNG into a sibling `Assets/` folder next to the document, and a relative markdown reference (`Assets/<filename>`) is inserted.

## Design principles

Project-specific rules. Aligned with Apple HIG and macOS document-based app conventions, but written for *this* codebase — follow these for changes here.

### Event flow

- Every window owns one `DocumentSession` (`@StateObject` in `ContentView`). It exposes a typed `PassthroughSubject<Event, Never>` and is the single bus for app-internal events.
- New cross-view events: add a case to `DocumentSession.Event`. Don't introduce new `Notification.Name`s for app-internal flow.
- Menu commands target the **focused scene** via `@FocusedValue(\.documentSession)` — never broadcast. AppKit's responder chain handles the dispatch; we don't.
- Don't add singletons to "find" the active editor/document. Per-scene focus routing already does this; if you need scoping, derive it from the session.
- AppKit system notifications (`NSWindow.didEndSheetNotification`, etc.) stay on `NotificationCenter` — those are platform contracts, not our event flow.

### State ownership

- Per-document state (cursor, outline, toast, in-flight format action) lives on `ContentView` / `MarkdownDocument` / `DocumentSession`, scoped to one window.
- Cross-document settings (theme, font, view mode, appearance) live on `AppSettings` via `@AppStorage`. Global by design.
- Decision rule: if two open documents could legitimately differ on it, it's per-document. If it should be uniform, it's a setting.
- State derived from `text` (wordCount, outline) is cached on the model and invalidated in `text`'s `didSet`. **Don't** make the cache `@Published` — the source's `objectWillChange` is enough; a second publish is wasted work.

### Caching & hot paths

Two paths run dozens of times per second on multi-MB documents: per-keystroke highlighting (`EditorView.Coordinator.applySyntaxHighlighting`) and per-`body`-recompute reads from `MarkdownDocument` / `StatusBarView`. Anything they touch must be cached or O(1) per call.

- Cache key encodes the inputs that produced the cached value (e.g. `"\(theme.id)|\(font.fontName)|\(font.pointSize)"`). Compare keys to decide reuse vs. rebuild.
- No `[Substring]` allocations from full-text splits. `components(separatedBy:)` and `text.split(_:)` are banned in hot paths — use scalar walks or `NSRegularExpression.numberOfMatches`.
- Heavy reference-type values (`NSMutableParagraphStyle`, `NSRegularExpression`) are `static let`. Never instantiated per call.
- All `try!` regex initializers are at type level, one per line, so a malformed pattern points at the failing regex.

### NSViewRepresentable lifecycle

- `makeNSView` runs once per view identity. Subscribe to publishers, attach delegates, install one-time observers here.
- `updateNSView` runs on every SwiftUI render. Sync mutable state (e.g. `coordinator.parent = self`, scheme handler `allowedRoot`); don't reinstall observers, recreate handlers, or rebuild caches.
- Long-lived state (cancellables, timers, caches, observer tokens) lives on the Coordinator and is torn down in `deinit`. Use `[weak self]` for closures stored beyond the call site (`DispatchWorkItem`, Combine sinks, `NotificationCenter` blocks).
- `WKWebViewConfiguration.setURLSchemeHandler` is captured at WebView creation — it cannot be swapped. If the handler's state needs to change, mutate the handler in place via the Coordinator's strong reference.

### Editor (NSTextView)

- Use `NSTextView`, not SwiftUI `TextEditor`. The find bar (`usesFindBar = true`), IME, undo, and continuous spell check rely on it.
- Always check `textView.hasMarkedText()` before mutating text or attributes. IME composition is in flight; defer until the composed text is committed.
- Highlighting is debounced (~150ms) and scoped to the affected paragraph (`SyntaxHighlighter.expandedRange`). Full re-highlight only when a fenced code block boundary is crossed.
- Seed `typingAttributes` whenever the theme or font changes — newly-typed characters render with these *before* the next highlighter pass.
- Find/Replace flow through `performTextFinderAction:` via the AppKit responder chain (see `FindCommands`). Don't reimplement these in SwiftUI.

### Preview (WKWebView)

- Shell HTML (`<head>` + theme CSS + empty `<div id="content">`) loads once via `loadHTMLString`. Subsequent updates inject `document.getElementById('content').innerHTML = JSON.parse(<literal>)` to preserve scroll position natively.
- Full reload only when `theme.id` or `baseURL` changes (`PreviewView.applyUpdate`).
- One `LocalAssetSchemeHandler` instance per WebView, scoped to that document's directory. Never a shared singleton.

### Security boundaries

The trust boundary for local file access is the `yanmo-asset:` scheme handler **plus** the resolver. Anything that emits a URL the WebView will load must enforce containment on both sides.

- `MarkdownRenderer.resolveLocalImageSources` strips out-of-bounds image refs at emission. Out-of-bounds → empty `src`.
- `LocalAssetSchemeHandler.allowedRoot` rejects out-of-bounds requests at load via `MarkdownRenderer.isPath(_:containedIn:)`. The check uses a trailing-`/` boundary (so `/docs/Foo` doesn't match `/docs/FooBar/baz`); symlinks intentionally not resolved.
- New URL schemes are blocked at sanitization (`MarkdownRenderer.sanitizeLinkURL`, `sanitizeImageURL`), not at consumers. Currently blocked: `javascript:`, `vbscript:`, `data:` (except whitelisted image MIMEs).
- Don't relax CSP without understanding what depends on it. `file:` in `exportCSPPolicy` is required for exported HTML to render local images when re-opened in a browser; remove it only if you also inline images as `data:` URLs.

### Mac platform conventions

These follow Apple HIG and document-based app expectations.

- **Multi-document model.** Each window is independent; menu commands act on the focused scene. Use `@FocusedValue` (macOS 13+) — `@FocusedObject` is macOS 14+ and we target 13+.
- **Standard editing actions** (Find, Replace, Cut/Copy/Paste, Undo/Redo, font size) ride the AppKit responder chain via tag-based selectors. Don't replace them with custom SwiftUI handlers.
- **Files live where the user expects.** Drag-dropped images go in `Assets/` next to the document (visible in Finder), not in app sandbox storage.
- **Settings persist in `UserDefaults`** via `@AppStorage`. No iCloud sync without explicit user opt-in.
- **Appearance follows the system** unless the user explicitly overrode it (`AppearanceMode.system` is the default; `applyAppearanceMode` only sets `NSApp.appearance` for non-system modes).
- **Keyboard shortcuts match Mac defaults.** `.command` for primary, `.shift` for capitalized/inverted variants, `.option` for alternatives. Bold = ⌘B, Italic = ⌘I, Cycle View Mode = ⇧⌘P, etc.
- **Native widgets, not reskins.** `HSplitView`, `NSSavePanel`, `NSAlert`, `NSPrintOperation` — use the system controls so users get the system behaviors (drag handles, sandbox prompts, accessibility, localization) for free.

## Direct download release

Yanmo is currently set up for direct macOS distribution, not Mac App Store distribution. Release builds should be signed with Developer ID, notarized, stapled, and distributed as a DMG.

Use a fresh output directory for each release:

```sh
mkdir -p build/Release-YYYYMMDD-yanmo
xcodebuild archive \
  -scheme Yanmo \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath build/Release-YYYYMMDD-yanmo/Yanmo.xcarchive \
  DEVELOPMENT_TEAM=S3J499CH5F \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY='Developer ID Application' \
  PROVISIONING_PROFILE_SPECIFIER=''
```

Package the archived app into a DMG with an `/Applications` shortcut, then sign the DMG:

```sh
mkdir -p build/Release-YYYYMMDD-yanmo/dmg-root
ditto build/Release-YYYYMMDD-yanmo/Yanmo.xcarchive/Products/Applications/Yanmo.app build/Release-YYYYMMDD-yanmo/dmg-root/Yanmo.app
ln -s /Applications build/Release-YYYYMMDD-yanmo/dmg-root/Applications
hdiutil create -volname Yanmo -srcfolder build/Release-YYYYMMDD-yanmo/dmg-root -ov -format UDZO build/Release-YYYYMMDD-yanmo/Yanmo-<version>.dmg
codesign --force --sign 'Developer ID Application: Beijing Wisemind Technologies Co., Ltd (S3J499CH5F)' build/Release-YYYYMMDD-yanmo/Yanmo-<version>.dmg
```

Notarize and staple the signed DMG. The local notarytool keychain profile is `yanmo-notary`; never commit Apple ID passwords or app-specific passwords.

```sh
xcrun notarytool submit build/Release-YYYYMMDD-yanmo/Yanmo-<version>.dmg --keychain-profile yanmo-notary --wait
xcrun stapler staple build/Release-YYYYMMDD-yanmo/Yanmo-<version>.dmg
spctl --assess --type open --context context:primary-signature --verbose=4 build/Release-YYYYMMDD-yanmo/Yanmo-<version>.dmg
```

Expected final Gatekeeper result:

```text
accepted
source=Notarized Developer ID
```

## What this project does NOT have

No CI config. No localization beyond English. No plugin system. No iCloud sync. No networking beyond what the preview WebView naturally does. UI / AppKit / WebKit layers are not unit-tested.
