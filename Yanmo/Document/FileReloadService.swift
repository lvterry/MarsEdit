import Combine
import Darwin
import Foundation

/// Reconciles an open document with changes made outside Yanmo.
final class FileReloadService: ObservableObject {
    static let conflictWarning = "File changed externally. Unsaved edits were kept."

    private static let defaultDebounce: TimeInterval = 0.2
    private static let readErrorPrefix = "Unable to reload external file changes"

    private let debounce: TimeInterval
    private let readQueue = DispatchQueue(label: "com.yanmo.file-reload.read")

    private weak var document: MarkdownDocument?
    private var fileURL: URL?
    private var baseline = ""
    private var conflictText: String?
    private var lastReadError: String?
    private var loadWork: DispatchWorkItem?
    private var watcher: FileChangeWatcher?
    private var onWarning: ((String) -> Void)?

    init(debounce: TimeInterval = FileReloadService.defaultDebounce) {
        self.debounce = debounce
    }

    deinit {
        watcher?.stop()
        loadWork?.cancel()
    }

    func start(
        url: URL?,
        document: MarkdownDocument,
        onWarning: @escaping (String) -> Void
    ) {
        stop()

        guard let url else { return }

        self.document = document
        self.fileURL = url
        self.onWarning = onWarning
        baseline = document.text

        do {
            watcher = try FileChangeWatcher(fileURL: url) { [weak self] in
                DispatchQueue.main.async {
                    self?.scheduleRead(for: url)
                }
            }
        } catch {
            warnReadError(error)
            return
        }

        // Close the race between the initial document read and watcher setup.
        scheduleRead(for: url)
    }

    func stop() {
        watcher?.stop()
        watcher = nil

        loadWork?.cancel()
        loadWork = nil

        document = nil
        fileURL = nil
        conflictText = nil
        lastReadError = nil
        onWarning = nil
    }

    private func scheduleRead(for url: URL) {
        guard fileURL == url else { return }

        loadWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            let result = Result { try MarkdownFileReader.read(url) }
            DispatchQueue.main.async {
                self?.apply(result, from: url)
            }
        }
        loadWork = work
        readQueue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    private func apply(_ result: Result<String, Error>, from url: URL) {
        guard fileURL == url, let document else { return }

        switch result {
        case .failure(let error):
            warnReadError(error)
        case .success(let incoming):
            lastReadError = nil
            reconcile(incoming, with: document)
        }
    }

    private func reconcile(_ incoming: String, with document: MarkdownDocument) {
        guard incoming != baseline else { return }

        let local = document.text
        if incoming == local {
            baseline = incoming
            conflictText = nil
            return
        }

        if local == baseline {
            baseline = incoming
            conflictText = nil
            document.text = incoming
            return
        }

        guard conflictText != incoming else { return }

        conflictText = incoming
        onWarning?(Self.conflictWarning)
    }

    private func warnReadError(_ error: Error) {
        let message = "\(Self.readErrorPrefix): \(error.localizedDescription)"
        guard lastReadError != message else { return }

        lastReadError = message
        onWarning?(message)
    }
}

/// Watches the file for in-place writes and its directory for replacements.
private final class FileChangeWatcher {
    private enum State {
        case active
        case stopped
    }

    private static let directoryEvents: DispatchSource.FileSystemEvent = [
        .write,
        .rename,
        .delete,
        .attrib,
        .link,
        .revoke,
    ]

    private static let fileEvents: DispatchSource.FileSystemEvent = [
        .write,
        .rename,
        .delete,
        .extend,
        .attrib,
        .revoke,
    ]

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.yanmo.file-reload.watch")
    private let onChange: () -> Void
    private let directorySource: DispatchSourceFileSystemObject
    private var fileSource: DispatchSourceFileSystemObject?
    private var state = State.active

    init(fileURL: URL, onChange: @escaping () -> Void) throws {
        self.fileURL = fileURL
        self.onChange = onChange

        let directoryURL = fileURL.deletingLastPathComponent()
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        directorySource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: Self.directoryEvents,
            queue: queue
        )
        directorySource.setEventHandler { [weak self] in
            self?.directoryChanged()
        }
        directorySource.setCancelHandler {
            close(descriptor)
        }
        directorySource.resume()

        installFileSource()
    }

    deinit {
        stop()
    }

    func stop() {
        queue.sync {
            guard state == .active else { return }

            state = .stopped
            fileSource?.cancel()
            fileSource = nil
            directorySource.cancel()
        }
    }

    private func directoryChanged() {
        guard state == .active else { return }

        installFileSource()
        onChange()
    }

    private func installFileSource() {
        fileSource?.cancel()
        fileSource = nil

        let descriptor = open(fileURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: Self.fileEvents,
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.fileChanged()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        fileSource = source
    }

    private func fileChanged() {
        guard state == .active else { return }

        onChange()
        installFileSource()
    }
}

/// Keeps raw file decoding below the document service layer.
private enum MarkdownFileReader {
    static func read(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let text = String(data: data, encoding: .utf8) {
            return text
        }

        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }

        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
}
