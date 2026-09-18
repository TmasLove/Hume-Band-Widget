import AppKit
import SwiftUI
import Observation

/// Owns the floating panel: where it sits, when it exists, and the state the
/// SwiftUI content reads.
///
/// The panel is always sized for its *expanded* form and pinned to the edge.
/// The resting pill is drawn inside that frame, aligned to the bezel, and the
/// rest of the panel is a hole — nothing is drawn there, so SwiftUI hit
/// testing returns nil and clicks fall through to whatever is behind. This is
/// why the panel never has to resize itself to fold, which would be visible
/// as a window-server resize rather than an animation.
@MainActor
@Observable
final class PanelController {
    static let shared = PanelController()

    private(set) var isExpanded = false

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            Self.defaults?.set(isEnabled, forKey: Self.enabledKey)
            isEnabled ? show() : hide()
        }
    }

    var edge: PanelEdge {
        didSet {
            guard edge != oldValue else { return }
            Self.defaults?.set(edge.rawValue, forKey: Self.edgeKey)
            // The panel's aspect changes with the axis, so rebuild rather
            // than reposition.
            if isEnabled { hide(); show() }
        }
    }

    private var panel: HumePanel?
    private let model = MetricsViewModel()

    private static let enabledKey = "panelEnabled"
    private static let edgeKey = "panelEdge"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: HumeConfig.appGroup) }

    /// Expanded footprint. The resting pill is a fraction of this.
    private static let expandedLong: CGFloat = 340
    private static let expandedDepth: CGFloat = 132
    /// How far the pill sits from the bezel, so it does not look welded on.
    private static let inset: CGFloat = 8

    private init() {
        // On by default the first time only. A panel that floats above every
        // other window should never appear uninvited on later launches, so
        // once the user has an opinion it is respected.
        isEnabled = Self.defaults?.object(forKey: Self.enabledKey) as? Bool ?? true
        edge = Self.defaults?.string(forKey: Self.edgeKey).flatMap(PanelEdge.init) ?? .top
        if isEnabled { show() }
    }

    func setExpanded(_ value: Bool) {
        guard isExpanded != value else { return }
        withAnimation(Motion.contents) { isExpanded = value }
    }

    // MARK: - Lifecycle

    func show() {
        guard panel == nil, let screen = NSScreen.main else { return }

        let size = Self.panelSize(for: edge)
        let p = HumePanel(contentRect: NSRect(origin: .zero, size: size))
        p.onClick = { [weak self] in self?.openDashboard() }
        p.contextMenuProvider = { [weak self] in self?.menu() }

        // The palette is injected inside `PanelRootView`, which observes
        // `ZoneSettings`. Reading it here instead would snapshot it: an
        // `NSHostingView`'s root is set once, so a later change would never
        // reach the floating panel.
        let root = PanelRootView(controller: self, model: model)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        p.contentView = host

        p.setFrameOrigin(Self.origin(for: edge, size: size, on: screen))
        p.orderFrontRegardless()
        panel = p
        model.startPolling()
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        isExpanded = false
        model.stopPolling()
    }

    // MARK: - Geometry

    private static func panelSize(for edge: PanelEdge) -> CGSize {
        edge.isVertical ? CGSize(width: expandedDepth, height: expandedLong)
                        : CGSize(width: expandedLong, height: expandedDepth)
    }

    /// Bottom-left origin in screen coordinates, where y grows *up* — the
    /// opposite of the panel's own flipped content coordinates, which is the
    /// easiest thing to get wrong here.
    ///
    /// Uses `screen.frame` rather than `visibleFrame` so the top edge can sit
    /// over the menu bar, which is the whole point of `level = .statusBar`.
    private static func origin(for edge: PanelEdge, size: CGSize, on screen: NSScreen) -> NSPoint {
        let f = screen.frame
        switch edge {
        case .top:
            return NSPoint(x: f.midX - size.width / 2, y: f.maxY - size.height - inset)
        case .bottom:
            return NSPoint(x: f.midX - size.width / 2, y: f.minY + inset)
        case .left:
            return NSPoint(x: f.minX + inset, y: f.midY - size.height / 2)
        case .right:
            return NSPoint(x: f.maxX - size.width - inset, y: f.midY - size.height / 2)
        }
    }

    // MARK: - Actions

    private func openDashboard() {
        NSApp.activate(ignoringOtherApps: true)
        if let url = URL(string: "\(HumeConfig.urlScheme)://dashboard?metric=heartRate") {
            NSWorkspace.shared.open(url)
        }
    }

    private func menu() -> NSMenu {
        let m = NSMenu()
        for e in PanelEdge.allCases {
            let item = NSMenuItem(title: "Pin to \(e.title)", action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = e.rawValue
            item.state = (e == edge) ? .on : .off
            m.addItem(item)
        }
        m.addItem(.separator())
        let hideItem = NSMenuItem(title: "Hide Panel", action: #selector(hideFromMenu), keyEquivalent: "")
        hideItem.target = self
        m.addItem(hideItem)
        return m
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let e = PanelEdge(rawValue: raw) else { return }
        edge = e
    }

    @objc private func hideFromMenu() { isEnabled = false }
}
