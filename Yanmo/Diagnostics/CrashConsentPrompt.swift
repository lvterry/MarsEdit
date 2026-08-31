import SwiftUI

private final class CrashPromptClaim {
    static let shared = CrashPromptClaim()

    private var claimed = false

    private init() {}

    func claim(_ consent: CrashConsent) -> Bool {
        guard consent == .unknown else { return false }
        guard !claimed else { return false }

        claimed = true
        return true
    }

    func release() {
        claimed = false
    }
}

private struct CrashConsentPrompt: ViewModifier {
    @ObservedObject private var settings: AppSettings
    private let feature: CrashFeature
    private let document: CrashDocumentState
    @State private var showing = false

    init(
        settings: AppSettings,
        feature: CrashFeature,
        document: CrashDocumentState
    ) {
        self.settings = settings
        self.feature = feature
        self.document = document
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard CrashPromptClaim.shared.claim(settings.crashConsent) else { return }

                DispatchQueue.main.async {
                    showing = true
                }
            }
            .onDisappear {
                guard showing else { return }

                CrashPromptClaim.shared.release()
                showing = false
            }
            .alert("Share Crash Diagnostics?", isPresented: $showing) {
                Button("Don’t Share", role: .cancel) {
                    choose(.denied)
                }
                Button("Share") {
                    choose(.allowed)
                }
            } message: {
                Text("Help improve Yanmo by sharing crash diagnostics. Reports include the Yanmo version, macOS version, hardware architecture, and crash stack. Yanmo does not include document contents or filenames.")
            }
    }

    private func choose(_ consent: CrashConsent) {
        settings.setCrashConsent(consent)
        CrashReporter.shared.apply(consent)
        if consent == .allowed {
            CrashReporter.shared.record(feature, document: document)
        }
        CrashPromptClaim.shared.release()
    }
}

extension View {
    func crashConsentPrompt(
        settings: AppSettings,
        feature: CrashFeature,
        document: CrashDocumentState
    ) -> some View {
        modifier(CrashConsentPrompt(
            settings: settings,
            feature: feature,
            document: document
        ))
    }
}
