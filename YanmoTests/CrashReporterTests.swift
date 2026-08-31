import Sentry
import XCTest
@testable import Yanmo

final class CrashReporterTests: XCTestCase {
    func testScrubberRemovesForbiddenEventData() {
        let event = Event(level: .fatal)
        event.serverName = "Terry’s Mac"
        event.extra = ["document": "private text"]
        event.tags = ["filename": "secret.md"]
        event.transaction = "/Users/terry/secret.md"
        event.context = [
            "app": [
                "app_identifier": "com.yanmo.app",
                "app_version": "0.10.0",
                "app_build": "9",
                "device_app_hash": "stable-id"
            ],
            "device": [
                "arch": "arm64",
                "locale": "en_US",
                "model": "MacBookPro"
            ],
            "os": [
                "name": "macOS",
                "version": "26.0",
                "build": "25A1",
                "kernel_version": "private"
            ],
            "custom": ["path": "/Users/terry/secret.md"]
        ]

        let result = CrashReporter.scrub(event)

        XCTAssertNil(result.serverName)
        XCTAssertNil(result.extra)
        XCTAssertNil(result.tags)
        XCTAssertNil(result.transaction)
        XCTAssertEqual(result.context?["app"]?.count, 3)
        XCTAssertEqual(result.context?["device"]?.count, 1)
        XCTAssertEqual(result.context?["os"]?.count, 3)
        XCTAssertNil(result.context?["custom"])
    }

    func testScrubberKeepsOnlyAllowlistedBreadcrumbs() {
        let state = Breadcrumb(level: .info, category: "yanmo.state")
        state.setData(value: "editing", key: "feature")
        state.setData(value: "unsaved", key: "document_state")
        state.setData(value: "secret.md", key: "filename")

        let network = Breadcrumb(level: .info, category: "http")
        network.setData(value: "https://example.com/private", key: "url")

        let event = Event(level: .fatal)
        event.breadcrumbs = [state, network]

        let result = CrashReporter.scrub(event)
        let breadcrumb = result.breadcrumbs?.first

        XCTAssertEqual(result.breadcrumbs?.count, 1)
        XCTAssertEqual(breadcrumb?.data?["feature"] as? String, "editing")
        XCTAssertEqual(breadcrumb?.data?["document_state"] as? String, "unsaved")
        XCTAssertNil(breadcrumb?.data?["filename"])
    }

    func testScrubberRejectsUnknownStateBreadcrumb() {
        let state = Breadcrumb(level: .info, category: "yanmo.state")
        state.setData(value: "secret.md", key: "feature")

        let event = Event(level: .fatal)
        event.breadcrumbs = [state]

        XCTAssertEqual(CrashReporter.scrub(event).breadcrumbs?.count, 0)
    }
}
