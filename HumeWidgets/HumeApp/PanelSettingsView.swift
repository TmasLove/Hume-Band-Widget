import SwiftUI

struct PanelSettingsView: View {
    @State private var controller = PanelController.shared

    var body: some View {
        SettingsPane {
            body_
        }
    }

    private var body_: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.sectionSpacing) {
            VStack(alignment: .leading, spacing: SettingsChrome.rowSpacing) {
                SettingsSectionHeader(title: "Desktop panel")
                SettingsRow {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Float a panel on the desktop", isOn: $controller.isEnabled)

                        Text("Rests as a small pill welded to a screen edge and unfolds when you point at it. It floats above other windows and follows you across Spaces and full-screen apps without taking focus. Click it to open the dashboard; right-click to move or hide it.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Picker("Edge", selection: $controller.edge) {
                            ForEach(PanelEdge.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .disabled(!controller.isEnabled)
                    }
                }
            }

            SettingsFootnote(text: "This is separate from the WidgetKit widget. A widget cannot resize itself — its size is fixed when you place it — so this panel is the only form that genuinely shrinks.")
        }
        .padding(SettingsChrome.windowPadding)
    }
}

#Preview { PanelSettingsView() }
