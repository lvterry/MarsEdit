import Foundation
import Sentry

enum CrashConsent: String {
    case unknown
    case allowed
    case denied
}

enum CrashFeature: String {
    case editing
    case previewing
    case exportingHTML
    case exportingPDF
    case updatingSettings
}

enum CrashDocumentState: String {
    case saved
    case unsaved
}

final class CrashReporter {
    static let shared = CrashReporter()

    private enum Environment: String {
        case development
        case staging
        case production
    }

    private static let dsnKey = "SentryDSN"
    private static let environmentKey = "SentryEnvironment"
    private static let bundleIDKey = "CFBundleIdentifier"
    private static let versionKey = "CFBundleShortVersionString"
    private static let buildKey = "CFBundleVersion"
    private static let breadcrumbCategory = "yanmo.state"
    private static let featureKey = "feature"
    private static let documentStateKey = "document_state"

    private static let allowedContextFields: [String: Set<String>] = [
        "app": ["app_identifier", "app_version", "app_build"],
        "device": ["arch"],
        "os": ["name", "version", "build"]
    ]

    private var started = false

    private init() {}

    func startIfAllowed(_ consent: CrashConsent) {
        guard consent == .allowed else { return }

        start()
    }

    func apply(_ consent: CrashConsent) {
        if consent == .allowed {
            start()
            return
        }

        stop()
    }

    func record(_ feature: CrashFeature, document: CrashDocumentState? = nil) {
        guard started else { return }

        let crumb = Breadcrumb(level: .info, category: Self.breadcrumbCategory)
        crumb.type = "state"
        crumb.setData(value: feature.rawValue, key: Self.featureKey)
        if let document {
            crumb.setData(value: document.rawValue, key: Self.documentStateKey)
        }
        SentrySDK.addBreadcrumb(crumb)
    }

    private func start() {
        guard !started else { return }
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: Self.dsnKey) as? String else { return }
        guard !dsn.isEmpty else { return }

        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = Self.environment
            options.releaseName = Self.releaseName
            options.dist = Bundle.main.object(forInfoDictionaryKey: Self.buildKey) as? String
            options.sendDefaultPii = false
            options.enableMemoryIntrospection = false
            options.enableAutoSessionTracking = false
            options.enableWatchdogTerminationTracking = false
            options.enableAppHangTracking = false
            options.enableAutoPerformanceTracing = false
            options.enableNetworkTracking = false
            options.enableNetworkBreadcrumbs = false
            options.enableCaptureFailedRequests = false
            options.enableFileIOTracing = false
            options.enableCoreDataTracing = false
            options.enableAutoBreadcrumbTracking = false
            options.enableLogs = false
            options.sendClientReports = false
            options.tracesSampleRate = 0
            options.enableUncaughtNSExceptionReporting = true
            options.beforeSend = { event in
                Self.scrub(event)
            }
        }

        started = true
    }

    private func stop() {
        guard started else { return }

        SentrySDK.close()
        started = false
    }

    static func scrub(_ event: Event) -> Event {
        event.user = nil
        event.request = nil
        event.serverName = nil
        event.message = nil
        event.error = nil
        event.extra = nil
        event.tags = nil
        event.transaction = nil
        event.context = scrub(context: event.context)
        event.breadcrumbs = scrub(breadcrumbs: event.breadcrumbs)

        event.exceptions?.forEach { exception in
            exception.value = nil
        }
        event.threads?.forEach { thread in
            thread.name = nil
        }

        return event
    }

    private static var environment: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: environmentKey) as? String,
           let environment = Environment(rawValue: value) {
            return environment.rawValue
        }

#if DEBUG
        return Environment.development.rawValue
#else
        return Environment.production.rawValue
#endif
    }

    private static var releaseName: String? {
        guard let bundleID = Bundle.main.object(forInfoDictionaryKey: bundleIDKey) as? String else {
            return nil
        }
        guard let version = Bundle.main.object(forInfoDictionaryKey: versionKey) as? String else {
            return nil
        }
        guard let build = Bundle.main.object(forInfoDictionaryKey: buildKey) as? String else {
            return nil
        }

        return "\(bundleID)@\(version)+\(build)"
    }

    private static func scrub(
        context: [String: [String: Any]]?
    ) -> [String: [String: Any]]? {
        guard let context else { return nil }

        var result: [String: [String: Any]] = [:]
        for (name, fields) in allowedContextFields {
            guard let values = context[name] else { continue }

            let kept = values.filter { fields.contains($0.key) }
            if !kept.isEmpty {
                result[name] = kept
            }
        }

        return result.isEmpty ? nil : result
    }

    private static func scrub(breadcrumbs: [Breadcrumb]?) -> [Breadcrumb]? {
        guard let breadcrumbs else { return nil }

        return breadcrumbs.compactMap { breadcrumb in
            guard breadcrumb.category == breadcrumbCategory else { return nil }
            guard let feature = breadcrumb.data?[featureKey] as? String else { return nil }
            guard CrashFeature(rawValue: feature) != nil else { return nil }

            let clean = Breadcrumb(level: .info, category: breadcrumbCategory)
            clean.type = "state"
            clean.setData(value: feature, key: featureKey)

            if let state = breadcrumb.data?[documentStateKey] as? String,
               CrashDocumentState(rawValue: state) != nil {
                clean.setData(value: state, key: documentStateKey)
            }

            return clean
        }
    }
}
