import SwiftUI

enum AppearanceMode: String, CaseIterable, Codable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system: return "Follow System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum DefaultPageSize: String, CaseIterable, Codable {
    case a4 = "A4"
    case letter = "Letter"

    var label: String { rawValue }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // MARK: - Editor
    @AppStorage("editorFontName") var editorFontName: String = "JetBrains Mono"
    @AppStorage("editorFontSize") var editorFontSize: Double = 15.0
    @AppStorage("wordWrap") var wordWrap: Bool = true
    @AppStorage("readingSpeedWPM") var readingSpeedWPM: Int = 200

    // MARK: - Appearance
    @AppStorage("selectedLightThemeId") var selectedLightThemeId: String = "default-light"
    @AppStorage("selectedDarkThemeId")  var selectedDarkThemeId: String  = "default-dark"
    @AppStorage("appearanceMode") var appearanceMode: AppearanceMode = .system
    @AppStorage("pdfExportThemeId") var pdfExportThemeId: String = ""

    private var _appearanceObserver: NSKeyValueObservation?

    init() {
        AppSettings.migrateIfNeeded(defaults: .standard)
        _appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }
    }

    static func migrateIfNeeded(defaults: UserDefaults) {
        guard let legacyId = defaults.string(forKey: "selectedThemeId"), !legacyId.isEmpty else { return }
        if let legacyTheme = Theme.theme(for: legacyId) {
            switch legacyTheme.mode {
            case .light: defaults.set(legacyId, forKey: "selectedLightThemeId")
            case .dark:  defaults.set(legacyId, forKey: "selectedDarkThemeId")
            }
        }
        defaults.removeObject(forKey: "selectedThemeId")
    }

    // MARK: - Export
    @AppStorage("defaultPageSize") var defaultPageSize: DefaultPageSize = .a4

    // MARK: - View State
    @AppStorage("toolbarVisible") var toolbarVisible: Bool = true
    @AppStorage("sidebarVisible") var sidebarVisible: Bool = false
    @AppStorage("viewMode") var viewMode: ViewMode = .defaultMode
    /// Editor pane width in split view; 0 means "no saved width yet".
    @AppStorage("editorPaneWidth") var editorPaneWidth: Double = 0

    var currentTheme: Theme {
        let isDark: Bool
        switch appearanceMode {
        case .light:  isDark = false
        case .dark:   isDark = true
        case .system: isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        let preferredId = isDark ? selectedDarkThemeId : selectedLightThemeId
        return Theme.theme(for: preferredId) ?? (isDark ? Theme.defaultDark : Theme.defaultLight)
    }

    var editorFont: NSFont {
        if let font = NSFont(name: editorFontName, size: CGFloat(editorFontSize)) {
            return font
        }
        if let font = NSFont(name: "SF Mono", size: CGFloat(editorFontSize)) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: CGFloat(editorFontSize), weight: .regular)
    }

    func increaseFontSize() {
        editorFontSize = min(editorFontSize + 1, 72)
    }

    func decreaseFontSize() {
        editorFontSize = max(editorFontSize - 1, 8)
    }

    func resetFontSize() {
        editorFontSize = 15.0
    }
}
