import SwiftUI

/// Native typography and surfaces for the Settings window.
///
/// The Codenotch proportional scale (`Design`) exists for the *data*
/// surfaces — widget, panel, dashboard readouts — where the numbers are the
/// product and deserve to be large. Reusing it for Settings put an 18.7pt
/// semibold title on every list row, against the ~13pt macOS uses, and the
/// result read as shouty. Settings should look like a Mac settings window.
enum SettingsChrome {
    static let sectionSpacing: CGFloat = 18
    static let rowSpacing: CGFloat = 8
    static let rowPadding: CGFloat = 12
    static let corner: CGFloat = 10
    static let windowPadding: CGFloat = 20
    static let paneWidth: CGFloat = 540
    /// Settings tabs keep one window size, as Mac settings windows do.
    static let paneHeight: CGFloat = 560
}

/// A scrolling Settings tab of a fixed size.
///
/// A `ScrollView` has no intrinsic height. In a window that sizes itself to
/// fit its content, giving one only a `maxHeight` resolves to zero and the
/// content disappears; giving it none at all lets the content run off the
/// bottom of the screen. Either way something goes missing, so the pane is
/// pinned to a definite size and scrolls inside it.
struct SettingsPane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        // Scroll only when the content actually overflows. A `ScrollView`
        // has no intrinsic height: given only a `maxHeight` in a
        // fit-to-content window it collapses to nothing, and given none the
        // content runs off the bottom of the screen — both of which have
        // already hidden a control here. Offering the plain layout first
        // means short tabs get no scrollbar, and long ones still scroll.
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .frame(width: SettingsChrome.paneWidth,
               height: SettingsChrome.paneHeight,
               alignment: .topLeading)
    }
}

/// A quiet grouped-row surface, the Settings counterpart to `NotchCard`.
struct SettingsRow<Content: View>: View {
    var selected: Bool = false
    var accent: Color = .accentColor
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(SettingsChrome.rowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: SettingsChrome.corner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SettingsChrome.corner, style: .continuous)
                    .strokeBorder(selected ? accent : Color(nsColor: .separatorColor),
                                  lineWidth: selected ? 2 : 1)
            }
    }
}

struct SettingsSectionHeader: View {
    var title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

struct SettingsFootnote: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
