import SwiftUI

@main
struct HumeWidgetsApp: App {
    @State private var deepLinkedMetric: MetricReading.Kind?
    @State private var deepLinkedTab: WidgetPage?
    @State private var deepLinkExpandsGraph = false
    @State private var settings = ZoneSettings.shared
    /// Held here so the controller is constructed at launch. It is a lazy
    /// static, and nothing else touches it until Settings is opened — without
    /// this the panel would only appear after a visit to Settings.
    @State private var panel = PanelController.shared
    @State private var relay = RelayServer.shared

    var body: some Scene {
        WindowGroup {
            DashboardView(highlighted: deepLinkedMetric,
                          requestedTab: deepLinkedTab,
                          requestedGraphExpanded: deepLinkExpandsGraph)
                // Injected once at the root so no component has to know where
                // the preference lives.
                .environment(\.zonePalette, settings.palette)
                // The widget's `widgetURL` lands here; the metric the user
                // tapped is the one the dashboard scrolls to.
                .task { relay.restoreIfEnabled() }
                .onOpenURL { url in
                    guard url.scheme == HumeConfig.urlScheme else { return }
                    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    let items = components?.queryItems ?? []
                    func value(_ name: String) -> String? {
                        items.first { $0.name == name }?.value
                    }
                    deepLinkedMetric = value("metric").flatMap { FocusMetric(rawValue: $0)?.kind }
                    deepLinkedTab = value("tab").flatMap(WidgetPage.init)
                    deepLinkExpandsGraph = value("graph") == "expanded"
                }
        }
        .defaultSize(width: 460, height: 860)
        // Colour vision belongs one click away, not buried in Settings. A
        // `Picker` in a `CommandMenu` renders as a checkmarked submenu, which
        // is the standard macOS shape for "pick one of these".
        .commands {
            CommandMenu("View") {
                Picker("Zone Colours", selection: $settings.palette) {
                    ForEach(ZonePalette.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Divider()
                Toggle("Desktop Panel", isOn: $panel.isEnabled)
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }

        Settings {
            TabView {
                SettingsView()
                    .tabItem { Label("View", systemImage: "eye") }
                PanelSettingsView()
                    .tabItem { Label("Desktop panel", systemImage: "rectangle.topthird.inset.filled") }
                PhoneRelayView()
                    .tabItem { Label("iPhone", systemImage: "iphone.gen3") }
                BandScanView()
                    .tabItem { Label("Band", systemImage: "dot.radiowaves.left.and.right") }
            }
        }
    }
}
