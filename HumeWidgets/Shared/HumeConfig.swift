import Foundation

enum HumeConfig {
    /// The App Group both targets share.
    ///
    /// Read from `Info.plist` rather than hardcoded, because on macOS the
    /// identifier must carry your Apple Team ID as a prefix — and baking
    /// somebody's team into source means everyone who clones this has to
    /// edit it. The plist value is `$(HUME_DEVELOPMENT_TEAM).group.…`,
    /// which Xcode expands from `Config/Signing.xcconfig`.
    static let appGroup: String = {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
            ?? "group.com.tomasroldan.humewidgets"
    }()
    static let widgetKind = "HumeBandWidget"
    static let urlScheme = "humeband"
}
