import SwiftUI
import AppKit

/// Persists the editor/preview divider position across document windows and
/// app launches.
///
/// HSplitView lays its panes out proportionally once created and offers no
/// SwiftUI API for the divider position, so a saved width can't be applied
/// (or observed) through view modifiers. This controller locates the
/// underlying NSSplitView, applies the saved editor width, and records the
/// live width as the user drags the divider.
///
/// Timing notes:
/// - The saved width is applied when the window becomes key, one async turn
///   after WindowFrameRestorer applies the saved window frame. Applying
///   earlier would land in the default-size window and then be rescaled
///   proportionally when the frame is restored.
/// - Widths are only recorded after that first application, so the
///   proportional relayouts during window setup never clobber the saved
///   value — the same class of bug WindowFrameRestorer guards against.
/// - Toggling editor-only back to split re-applies the saved width, since
///   HSplitView otherwise pins the divider near the right edge.
struct SplitDividerController: NSViewRepresentable {
    @EnvironmentObject private var settings: AppSettings

    func makeCoordinator() -> Coordinator {
        Coordinator(settings: settings)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // The hosting hierarchy isn't wired to the split view until the
        // next layout pass.
        DispatchQueue.main.async { [weak coordinator = context.coordinator] in
            coordinator?.attach(from: view)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    final class Coordinator: NSObject {
        private let settings: AppSettings
        private weak var splitView: NSSplitView?
        private var resizeObserver: NSObjectProtocol?
        private var keyObserver: NSObjectProtocol?
        /// The width to restore, captured before any layout pass can write
        /// intermediate values back to settings.
        private let savedWidth: Double
        private var appliedSavedWidth = false
        private var lastPaneCount = 0

        init(settings: AppSettings) {
            self.settings = settings
            self.savedWidth = settings.editorPaneWidth
            super.init()
        }

        deinit {
            if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
            if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        }

        func attach(from view: NSView) {
            guard splitView == nil else { return }
            var candidate: NSView? = view
            while let current = candidate {
                if let split = current as? NSSplitView {
                    splitView = split
                    observe(split)
                    // A window opened mid-session (File > Open) becomes key in
                    // the same turn as its creation — before this async attach
                    // registers the observer — so check the current state.
                    if split.window?.isKeyWindow == true {
                        DispatchQueue.main.async { [weak self] in
                            self?.applySavedWidthIfNeeded()
                        }
                    }
                    return
                }
                candidate = current.superview
            }
        }

        private func observe(_ split: NSSplitView) {
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSSplitView.didResizeSubviewsNotification,
                object: split,
                queue: .main
            ) { [weak self] _ in
                self?.sync()
            }
            // object: nil because the split view may not be in a window yet;
            // filter by window instead.
            keyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self, weak split] note in
                guard note.object as? NSWindow === split?.window else { return }
                DispatchQueue.main.async { self?.applySavedWidthIfNeeded() }
            }
        }

        /// Applies the saved editor width to the divider.
        private func applySavedWidthIfNeeded() {
            guard !appliedSavedWidth else { return }
            guard let split = splitView, split.arrangedSubviews.count >= 2 else { return }
            appliedSavedWidth = true
            guard savedWidth >= 200 else { return }
            split.setPosition(CGFloat(savedWidth), ofDividerAt: 0)
        }

        /// Records the current editor pane width, or re-applies the saved
        /// one when the preview pane reappears in an editor-only layout.
        private func sync() {
            guard let split = splitView else { return }
            // Update the pane count before any setPosition call: setPosition
            // posts didResizeSubviews synchronously, re-entering sync() —
            // stale state here caused unbounded recursion.
            let paneCount = split.arrangedSubviews.count
            let previousCount = lastPaneCount
            lastPaneCount = paneCount
            guard paneCount >= 2 else { return }
            if previousCount < 2, settings.editorPaneWidth >= 200 {
                // Editor-only -> split: the editor kept the full width.
                // Re-apply the last user-chosen split width.
                split.setPosition(CGFloat(settings.editorPaneWidth), ofDividerAt: 0)
            }
            guard appliedSavedWidth else { return }
            let width = Double(split.arrangedSubviews[0].frame.width)
            if width != settings.editorPaneWidth {
                settings.editorPaneWidth = width
            }
        }
    }
}
