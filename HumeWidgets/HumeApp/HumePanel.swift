import AppKit

/// Which screen edge the panel is welded to.
enum PanelEdge: String, CaseIterable, Identifiable, Sendable {
    case top, bottom, left, right

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// True when the metrics stack runs down the screen rather than across it.
    var isVertical: Bool { self == .left || self == .right }
}

/// Borderless, non-activating panel that floats over everything including the
/// menu bar and full-screen apps.
///
/// Configuration lifted from Codenotch's `NotchPanel`, because it is the set
/// that actually works: non-activating matters most — glancing at your heart
/// rate must never pull focus from what you were doing, and a normal window
/// would.
final class HumePanel: NSPanel {
    /// A left click anywhere on the visible chrome.
    ///
    /// Handled on the panel rather than the content view because
    /// `NSWindow.sendEvent` sees every event first, while the hosting view's
    /// hit test resolves to a SwiftUI-owned subview that may swallow it.
    var onClick: (() -> Void)?
    var contextMenuProvider: (() -> NSMenu?)?

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .rightMouseDown,
              let menu = contextMenuProvider?(),
              let view = contentView,
              // Only over the visible chrome; elsewhere the panel is a hole.
              view.hitTest(event.locationInWindow) != nil
        else { return super.sendEvent(event) }

        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    override func mouseDown(with event: NSEvent) {
        guard let view = contentView, view.hitTest(event.locationInWindow) != nil else {
            return super.mouseDown(with: event)
        }
        onClick?()
    }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        // Above the menu bar, present on every Space, and not swept away when
        // another app goes full screen.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        // Needed for SwiftUI `.onHover` to fire inside a non-activating panel.
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
