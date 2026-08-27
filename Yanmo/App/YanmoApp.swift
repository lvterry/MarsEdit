import SwiftUI
import AppKit
import Combine

@main
struct YanmoApp: App {
    @StateObject private var settings = AppSettings.shared

    init() {
        // Instantiate early so it observes the first document window.
        _ = WindowFrameRestorer.shared
    }

    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
                .environmentObject(settings)
                .frame(minWidth: 700, minHeight: 500)
        }
        .commands {
            TemplateCommands(store: .shared)
            FormatCommands()
            FindCommands()
            ViewModeCommands(settings: settings)
            CommandGroup(replacing: .help) {}
            ExportCommands()
            FontSizeCommands(settings: settings)
        }

        Settings {
            PreferencesView()
                .environmentObject(settings)
        }
    }
}

// MARK: - Format Menu

private struct FormatCommands: Commands {
    @FocusedValue(\.documentSession) private var session: DocumentSession?

    var body: some Commands {
        CommandGroup(replacing: .textFormatting) {
            Button("Bold") { post(.bold) }
                .keyboardShortcut("b", modifiers: .command)
            Button("Italic") { post(.italic) }
                .keyboardShortcut("i", modifiers: .command)
            Button("Inline Code") { post(.inlineCode) }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Button("Insert Link") { post(.link) }
                .keyboardShortcut("k", modifiers: .command)

            Divider()

            Menu("Heading") {
                ForEach(1...3, id: \.self) { level in
                    Button("H\(level)") { post(.heading(level)) }
                }
            }

            Button("Blockquote") { post(.blockquote) }
            Button("Horizontal Rule") { post(.horizontalRule) }

            Divider()

            Button("Ordered List") { post(.orderedList) }
            Button("Unordered List") { post(.unorderedList) }
            Button("Task List") { post(.taskList) }

            Divider()

            Button("Code Block") { post(.codeBlock) }
            Button("Strikethrough") { post(.strikethrough) }
            Button("Image") { post(.image) }
        }
    }

    private func post(_ action: FormatAction) {
        session?.post(.format(action))
    }
}

// MARK: - Find Menu
//
// NSTextView already handles `performTextFinderAction:` when `usesFindBar = true`
// (set in EditorView.makeNSView). These menu items just need to forward the
// standard tag-based action up the responder chain.

private struct FindCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Section {
                Menu("Find") {
                    Button("Find…") { Self.send(.showFindInterface) }
                        .keyboardShortcut("f", modifiers: .command)
                    Button("Find Next") { Self.send(.nextMatch) }
                        .keyboardShortcut("g", modifiers: .command)
                    Button("Find Previous") { Self.send(.previousMatch) }
                        .keyboardShortcut("g", modifiers: [.command, .shift])
                    Button("Use Selection for Find") { Self.send(.setSearchString) }
                        .keyboardShortcut("e", modifiers: .command)
                    Divider()
                    Button("Replace…") { Self.send(.showReplaceInterface) }
                    Button("Replace All") { Self.send(.replaceAll) }
                    Button("Replace") { Self.send(.replace) }
                    Button("Replace and Find") { Self.send(.replaceAndFind) }
                }
            }
        }
    }

    /// Forwards a Find-menu action to the first responder via the standard
    /// AppKit `performTextFinderAction:` selector. Constructs an NSMenuItem with
    /// the appropriate tag because that's how the receiver discovers which
    /// action to run.
    private static func send(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        NSApp.sendAction(#selector(TextFinderActionResponding.performTextFinderAction(_:)), to: nil, from: item)
    }
}

// MARK: - View Menu

private struct ViewModeCommands: Commands {
    @ObservedObject var settings: AppSettings
    @FocusedValue(\.documentSession) private var session: DocumentSession?

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Toggle Toolbar") {
                settings.toolbarVisible.toggle()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Button("Toggle Sidebar") {
                settings.sidebarVisible.toggle()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Button("Cycle View Mode") {
                session?.post(.cycleViewMode)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }
    }
}

// MARK: - Export

private struct ExportCommands: Commands {
    @FocusedValue(\.documentSession) private var session: DocumentSession?

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Export to HTML…") {
                session?.post(.exportHTML)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button("Export to PDF…") {
                session?.post(.exportPDF)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }
    }
}

// MARK: - Font Size

private struct FontSizeCommands: Commands {
    @ObservedObject var settings: AppSettings

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Section {
                Button("Increase Font Size") {
                    settings.increaseFontSize()
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Decrease Font Size") {
                    settings.decreaseFontSize()
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Font Size") {
                    settings.resetFontSize()
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}

// MARK: - Template Commands

private struct TemplateCommands: Commands {
    @ObservedObject var store: TemplateStore
    @Environment(\.newDocument) private var newDocument

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Menu("New from Template") {
                if store.templates.isEmpty {
                    Button("No Templates") {}
                        .disabled(true)
                } else {
                    ForEach(store.templates) { template in
                        Button(template.displayName) {
                            guard let text = try? store.readContents(of: template) else { return }
                            newDocument { MarkdownDocument(text: text) }
                        }
                    }
                }
                Divider()
                Button("Reveal Templates Folder in Finder") {
                    store.revealInFinder()
                }
            }
        }
    }
}

// Lightweight protocol that exposes the AppKit selector to `#selector`.
@objc private protocol TextFinderActionResponding {
    func performTextFinderAction(_ sender: Any?)
}

// MARK: - Document Session
//
// Per-document event hub. Each `ContentView` owns one and publishes it as a
// `focusedSceneValue` so app-wide menu commands can target the active window's
// session without broadcasting through `NotificationCenter`. Within a window,
// child views (toolbar, outline, editor) reach the same session through
// `@EnvironmentObject` and post typed events.

final class DocumentSession: ObservableObject {
    enum Event {
        case format(FormatAction)
        case scrollTo(NSRange)
        case cycleViewMode
        case exportHTML
        case exportPDF
        case showToast(String)
    }

    let events = PassthroughSubject<Event, Never>()

    func post(_ event: Event) {
        events.send(event)
    }
}

private struct DocumentSessionFocusedKey: FocusedValueKey {
    typealias Value = DocumentSession
}

extension FocusedValues {
    var documentSession: DocumentSession? {
        get { self[DocumentSessionFocusedKey.self] }
        set { self[DocumentSessionFocusedKey.self] = newValue }
    }
}

// MARK: - Format Actions

enum FormatAction {
    case bold
    case italic
    case strikethrough
    case inlineCode
    case codeBlock
    case link
    case image
    case heading(Int)
    case blockquote
    case horizontalRule
    case orderedList
    case unorderedList
    case taskList

    var wrapPrefix: String {
        switch self {
        case .bold: return "**"
        case .italic: return "_"
        case .strikethrough: return "~~"
        case .inlineCode: return "`"
        case .codeBlock: return "```\n"
        case .link: return "["
        case .image: return "!["
        case .heading(let level): return String(repeating: "#", count: level) + " "
        case .blockquote: return "> "
        case .horizontalRule: return "\n---\n"
        case .orderedList: return "1. "
        case .unorderedList: return "- "
        case .taskList: return "- [ ] "
        }
    }

    var wrapSuffix: String {
        switch self {
        case .bold: return "**"
        case .italic: return "_"
        case .strikethrough: return "~~"
        case .inlineCode: return "`"
        case .codeBlock: return "\n```"
        case .link: return "](url)"
        case .image: return "](image_url)"
        default: return ""
        }
    }

    var isLinePrefix: Bool {
        switch self {
        case .heading, .blockquote, .horizontalRule, .orderedList, .unorderedList, .taskList:
            return true
        default:
            return false
        }
    }

    var insertsAtLineStart: Bool {
        switch self {
        case .orderedList, .unorderedList, .taskList:
            return true
        default:
            return false
        }
    }
}
