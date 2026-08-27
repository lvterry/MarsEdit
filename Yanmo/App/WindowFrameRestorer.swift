import AppKit

// Persists the document window frame so windows opened later match the size
// (and position) the user last chose. SwiftUI's DocumentGroup has no API for
// this, so it works at the AppKit notification level.
//
// A new document window posts several didResize notifications while SwiftUI
// configures it (default size, cascade placement) — before it ever becomes
// key. Those setup resizes must not overwrite the user's saved frame, so
// frames are only saved once a window has become key at least once. The
// saved frame is applied the first time each document window becomes key.
// NSPanel subclasses (Settings, print/export panels) are ignored.
final class WindowFrameRestorer {
    static let shared = WindowFrameRestorer()

    private static let defaultsKey = "documentWindowFrame"

    private var shownWindows = Set<ObjectIdentifier>()
    private var restoredCount = 0
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: NSWindow.didResizeNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                self?.saveFrame(note.object as? NSWindow)
            },
            center.addObserver(
                forName: NSWindow.didMoveNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                self?.saveFrame(note.object as? NSWindow)
            },
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                self?.restoreFrame(note.object as? NSWindow)
            },
        ]
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private var savedFrame: NSRect? {
        get {
            guard let str = UserDefaults.standard.string(forKey: Self.defaultsKey) else { return nil }
            return NSRectFromString(str)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(NSStringFromRect(newValue), forKey: Self.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
            }
        }
    }

    private func saveFrame(_ window: NSWindow?) {
        guard let window,
              isDocumentWindow(window),
              !window.isZoomed,
              !window.styleMask.contains(.fullScreen),
              shownWindows.contains(ObjectIdentifier(window))
        else { return }
        savedFrame = window.frame
    }

    private func restoreFrame(_ window: NSWindow?) {
        guard let window, isDocumentWindow(window) else { return }
        shownWindows.insert(ObjectIdentifier(window))
        guard let frame = savedFrame,
              !window.isZoomed,
              !window.styleMask.contains(.fullScreen)
        else { return }
        // The first window of a session gets the saved origin too, so the app
        // reopens where the user left it. Later windows only take the saved
        // size and keep the cascade origin SwiftUI already picked for them,
        // instead of stacking exactly on top of the previous window.
        restoredCount += 1
        var target = window.frame
        target.size = frame.size
        if restoredCount == 1 {
            target.origin = frame.origin
        }
        window.setFrame(target, display: true)
    }

    private func isDocumentWindow(_ window: NSWindow) -> Bool {
        !(window is NSPanel)
            && window.styleMask.contains(.resizable)
            && window.frame.width >= 700
    }
}
