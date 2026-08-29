import SwiftUI

struct ContentView: View {
    @ObservedObject var document: MarkdownDocument
    let fileURL: URL?
    @EnvironmentObject var settings: AppSettings
    @StateObject private var session = DocumentSession()
    @StateObject private var fileReloader = FileReloadService()

    @State private var cursorPosition: (line: Int, column: Int) = (1, 1)
    @State private var outlineItems: [OutlineItem] = []
    private static let toastDuration: TimeInterval = 4.0
    @State private var toastMessage: String?
    @State private var toastID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            if settings.toolbarVisible {
                ToolbarView()
                Divider()
            }

            // Main content area
            HStack(spacing: 0) {
                // Outline sidebar
                if settings.sidebarVisible {
                    OutlineSidebar(items: outlineItems)
                    Divider()
                }

                // Editor / Preview split
                GeometryReader { geometry in
                    HSplitView {
                        if settings.viewMode != .previewOnly {
                            EditorView(
                                document: document,
                                fileURL: fileURL,
                                cursorPosition: $cursorPosition
                            )
                            .frame(minWidth: 200)
                            .background(SplitDividerController())
                        }

                        if settings.viewMode != .editorOnly {
                            PreviewView(
                                document: document,
                                baseURL: fileURL?.deletingLastPathComponent()
                            )
                            .frame(minWidth: 200)
                        }
                    }
                }
            }

            Divider()

            // Status bar
            StatusBarView(
                document: document,
                cursorPosition: cursorPosition
            )
        }
        .overlay(alignment: .top) {
            // Toast notification
            if let message = toastMessage {
                ToastView(message: message)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, settings.toolbarVisible ? 44 : 8)
            }
        }
        .environmentObject(session)
        .focusedSceneValue(\.documentSession, session)
        .onReceive(session.events) { event in
            handle(event)
        }
        .onChange(of: document.text) { newValue in
            updateOutline(text: newValue)
            checkLargeFile(text: newValue)
        }
        .onAppear {
            updateOutline(text: document.text)
            applyAppearanceMode(settings.appearanceMode)
            startFileReload()
        }
        .onChange(of: fileURL) { _ in startFileReload() }
        .onDisappear { fileReloader.stop() }
        .onChange(of: settings.appearanceMode) { mode in
            applyAppearanceMode(mode)
        }
    }

    // MARK: - Session events

    private func handle(_ event: DocumentSession.Event) {
        switch event {
        case .format, .scrollTo:
            // Handled by EditorView's session subscription.
            break
        case .cycleViewMode:
            withAnimation(.easeInOut(duration: 0.2)) {
                settings.viewMode = settings.viewMode.next
            }
        case .exportHTML:
            exportHTML()
        case .exportPDF:
            exportPDF()
        case .showToast(let message):
            showToast(message)
        }
    }

    // MARK: - Appearance

    private func applyAppearanceMode(_ mode: AppearanceMode) {
        switch mode {
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system: NSApp.appearance = nil
        }
    }

    // MARK: - Outline

    private func updateOutline(text: String) {
        outlineItems = OutlineParser.parse(text)
    }

    // MARK: - Large File Warning

    private func checkLargeFile(text: String) {
        if document.isLargeFile {
            showToast("Large file — some features like live preview may be slower.")
        }
    }

    // MARK: - External Changes

    private func startFileReload() {
        fileReloader.start(url: fileURL, document: document) { message in
            session.post(.showToast(message))
        }
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        let id = UUID()
        withAnimation {
            toastID = id
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.toastDuration) {
            guard toastID == id else { return }
            withAnimation {
                toastMessage = nil
            }
        }
    }

    // MARK: - Export HTML

    private func exportHTML() {
        let theme = settings.currentTheme
        let exporter = HTMLExporter(theme: theme)
        let html = exporter.exportForBrowser(markdown: document.text, documentDirectory: fileURL?.deletingLastPathComponent())

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = suggestedFileName(extension: "html")
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try html.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    showExportError("HTML export failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Export PDF

    private func exportPDF() {
        let theme: Theme
        if !settings.pdfExportThemeId.isEmpty, let t = Theme.theme(for: settings.pdfExportThemeId) {
            theme = t
        } else {
            theme = settings.currentTheme
        }

        let exporter = PDFExporter(theme: theme, pageSize: settings.defaultPageSize)
        let html = HTMLExporter(theme: theme).export(markdown: document.text)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedFileName(extension: "pdf")
        panel.begin { response in
            if response == .OK, let url = panel.url {
                exporter.exportPDF(html: html, baseURL: self.fileURL?.deletingLastPathComponent(), to: url)
            }
        }
    }

    private func suggestedFileName(extension ext: String) -> String {
        if let fileURL = fileURL {
            return fileURL.deletingPathExtension().lastPathComponent + "." + ext
        }
        // Use first H1 if available
        for item in outlineItems where item.level == 1 {
            let safe = item.title.replacingOccurrences(of: "[^a-zA-Z0-9 -]", with: "", options: .regularExpression)
            return safe + "." + ext
        }
        return "Untitled." + ext
    }

    private func showExportError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Export Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - Toast View

struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 4)
    }
}
