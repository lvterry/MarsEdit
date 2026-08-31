import SwiftUI
import XCTest
@testable import Yanmo

final class CrashConsentTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.\(UUID())"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testConsentStartsUnknown() {
        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.crashConsent, .unknown)
    }

    func testConsentPersistsAllowed() {
        let settings = AppSettings(defaults: defaults)
        settings.setCrashConsent(.allowed)

        XCTAssertEqual(AppSettings(defaults: defaults).crashConsent, .allowed)
    }

    func testConsentPersistsDenied() {
        let settings = AppSettings(defaults: defaults)
        settings.setCrashConsent(.denied)

        XCTAssertEqual(AppSettings(defaults: defaults).crashConsent, .denied)
    }

    func testInvalidConsentBecomesUnknown() {
        defaults.set("invalid", forKey: "crashReportingConsent")

        XCTAssertEqual(AppSettings(defaults: defaults).crashConsent, .unknown)
    }

    func testPromptAcceptsInitialState() {
        let settings = AppSettings(defaults: defaults)

        _ = EmptyView().crashConsentPrompt(
            settings: settings,
            feature: .editing,
            document: .saved
        )
    }
}
