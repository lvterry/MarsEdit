import Combine
import XCTest
@testable import Yanmo

final class FileReloadServiceTests: XCTestCase {
    private static let timeout: TimeInterval = 2.0
    private static let debounce: TimeInterval = 0.01
    private static let saveSettleDelay: UInt64 = 100_000_000

    private var tempRoot: URL!
    private var fileURL: URL!
    private var cancellables: Set<AnyCancellable> = []

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileReloadServiceTests-\(UUID().uuidString)", isDirectory: true)
        fileURL = tempRoot.appendingPathComponent("document.md")

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        cancellables.removeAll()
        try? FileManager.default.removeItem(at: tempRoot)
        fileURL = nil
        tempRoot = nil
    }

    @MainActor
    func testReloadsCleanDocumentAfterInPlaceWrite() async throws {
        let document = MarkdownDocument(text: "original")
        let service = FileReloadService(debounce: Self.debounce)
        let reloaded = expectation(description: "Document reloaded")

        document.$text
            .dropFirst()
            .sink { text in
                if text == "external" {
                    reloaded.fulfill()
                }
            }
            .store(in: &cancellables)

        service.start(url: fileURL, document: document) { warning in
            XCTFail("Unexpected warning: \(warning)")
        }

        try "external".write(to: fileURL, atomically: false, encoding: .utf8)
        await fulfillment(of: [reloaded], timeout: Self.timeout)

        XCTAssertEqual(document.text, "external")
        service.stop()
    }

    @MainActor
    func testReloadsCleanDocumentAfterAtomicWrite() async throws {
        let document = MarkdownDocument(text: "original")
        let service = FileReloadService(debounce: Self.debounce)
        let reloaded = expectation(description: "Document reloaded")

        document.$text
            .dropFirst()
            .sink { text in
                if text == "replacement" {
                    reloaded.fulfill()
                }
            }
            .store(in: &cancellables)

        service.start(url: fileURL, document: document) { warning in
            XCTFail("Unexpected warning: \(warning)")
        }

        try "replacement".write(to: fileURL, atomically: true, encoding: .utf8)
        await fulfillment(of: [reloaded], timeout: Self.timeout)

        XCTAssertEqual(document.text, "replacement")
        service.stop()
    }

    @MainActor
    func testPreservesDirtyDocumentAndWarns() async throws {
        let document = MarkdownDocument(text: "original")
        let service = FileReloadService(debounce: Self.debounce)
        let warned = expectation(description: "Conflict warning")

        service.start(url: fileURL, document: document) { warning in
            XCTAssertEqual(warning, FileReloadService.conflictWarning)
            warned.fulfill()
        }

        document.text = "local edit"
        try "external edit".write(to: fileURL, atomically: false, encoding: .utf8)
        await fulfillment(of: [warned], timeout: Self.timeout)

        XCTAssertEqual(document.text, "local edit")
        service.stop()
    }

    @MainActor
    func testOwnSaveAdvancesCleanBaseline() async throws {
        let document = MarkdownDocument(text: "original")
        let service = FileReloadService(debounce: Self.debounce)
        let reloaded = expectation(description: "Later external edit reloaded")

        document.$text
            .dropFirst()
            .sink { text in
                if text == "external edit" {
                    reloaded.fulfill()
                }
            }
            .store(in: &cancellables)

        service.start(url: fileURL, document: document) { warning in
            XCTFail("Unexpected warning: \(warning)")
        }

        document.text = "local save"
        try "local save".write(to: fileURL, atomically: false, encoding: .utf8)
        try await Task.sleep(nanoseconds: Self.saveSettleDelay)
        try "external edit".write(to: fileURL, atomically: false, encoding: .utf8)

        await fulfillment(of: [reloaded], timeout: Self.timeout)
        XCTAssertEqual(document.text, "external edit")
        service.stop()
    }
}
