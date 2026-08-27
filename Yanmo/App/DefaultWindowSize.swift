import AppKit

// Tracks the "default window size": the size of the currently active
// document window.
//
// Rules:
// 1. A brand-new window with no recorded size uses the built-in default.
// 2. If the user never resizes, every window keeps that default.
// 3. Resizing the active window updates the default; windows opened later
//    adopt it, existing windows are never resized.
// 4. When a window closes and an older window regains focus, the default
//    becomes that window's size — which falls out of "the active window
//    defines the default" on every didBecomeKey.
//
// The recorded size persists across launches, so the first window of the
// next session opens at the last-used size. Only sizes are tracked; new
// windows keep the cascade position SwiftUI gives them.
final class DefaultWindowSize {
    static let shared = DefaultWindowSize()

    private static let defaultsKey = "defaultWindowSize"

    /// Windows that have become key at least once. A new window's setup
    /// resizes (default size, cascade placement) happen before it ever
    /// becomes key; they must not overwrite the recorded default.
    ///
    /// Must be keyed by the live window object, not by memory address
    /// (`ObjectIdentifier`): a closed NSWindow's address can be recycled by
    /// the next allocation, which made brand-new windows look already
    /// activated — skipping adoption and leaking their setup sizes into the
    /// recorded default. Weak entries disappear with each window.
    private let activatedWindows = NSHashTable<AnyObject>.weakObjects()
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: NSWindow.didResizeNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                self?.windowWasResized(note.object as? NSWindow)
            },
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                self?.windowBecameKey(note.object as? NSWindow)
            },
        ]
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private var recordedSize: NSSize? {
        get {
            guard let str = UserDefaults.standard.string(forKey: Self.defaultsKey) else { return nil }
            return NSSizeFromString(str)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(NSStringFromSize(newValue), forKey: Self.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
            }
        }
    }

    /// Rule 3: resizing the active window becomes the new default.
    private func windowWasResized(_ window: NSWindow?) {
        guard let window,
              isDocumentWindow(window),
              activatedWindows.contains(window),
              !window.isZoomed,
              !window.styleMask.contains(.fullScreen)
        else { return }
        recordedSize = window.frame.size
    }

    private func windowBecameKey(_ window: NSWindow?) {
        guard let window, isDocumentWindow(window) else { return }
        if !activatedWindows.contains(window) {
            activatedWindows.add(window)
            // Rules 1-3: a new window adopts the recorded size once, keeping
            // the cascade origin SwiftUI already picked for it.
            if let size = recordedSize,
               !window.isZoomed,
               !window.styleMask.contains(.fullScreen)
            {
                var frame = window.frame
                let heightDelta = size.height - frame.size.height
                frame.size = size
                frame.origin.y -= heightDelta // grow downward from the top edge
                window.setFrame(frame, display: true)
            }
        }
        // Rules 3/4: whichever window is active defines the default.
        if !window.isZoomed, !window.styleMask.contains(.fullScreen) {
            recordedSize = window.frame.size
        }
    }

    private func isDocumentWindow(_ window: NSWindow) -> Bool {
        !(window is NSPanel)
            && window.styleMask.contains(.resizable)
            && window.frame.width >= 700
    }
}
