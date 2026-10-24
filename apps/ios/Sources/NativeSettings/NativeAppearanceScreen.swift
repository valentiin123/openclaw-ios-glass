import SwiftUI

/// Labels and glyphs for the appearance choices.
enum NativeAppearancePresentation {
    static func title(_ preference: AppAppearancePreference) -> String {
        switch preference {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }

    static func icon(_ preference: AppAppearancePreference) -> String {
        switch preference {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

/// Native replacement for the Dashboard `/settings/appearance` page.
/// Uses the local `AppAppearanceModel`, so no Gateway call is involved.
/// One glass segmented control (a control, so glass is appropriate); everything else is plain list content.
@MainActor
struct NativeAppearanceScreen: View {
    @Environment(AppAppearanceModel.self) private var appearanceModel
    var headerSidebarAction: OpenClawSidebarHeaderAction?
    var embedded: Bool = false
    var onClose: (() -> Void)?

    var body: some View {
        NativeSettingsPage(
            title: NativeSettingsDestination.appearance.title,
            headerSidebarAction: self.headerSidebarAction,
            embedded: self.embedded,
            onClose: self.onClose)
        {
            self.list
        }
    }

    private var selection: Binding<AppAppearancePreference> {
        Binding<AppAppearancePreference>(
            get: { self.appearanceModel.preference },
            set: { (newValue: AppAppearancePreference) in self.appearanceModel.select(newValue) })
    }

    private var options: [OpenClawGlassSegmented<AppAppearancePreference>.Option] {
        var result: [OpenClawGlassSegmented<AppAppearancePreference>.Option] = []
        for preference in AppAppearancePreference.allCases {
            let option = OpenClawGlassSegmented<AppAppearancePreference>.Option(
                preference,
                title: .verbatim(NativeAppearancePresentation.title(preference)),
                systemImage: NativeAppearancePresentation.icon(preference))
            result.append(option)
        }
        return result
    }

    private var list: some View {
        List {
            Section {
                OpenClawGlassSegmented(selection: self.selection, options: self.options)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("NativeSettings.Appearance.Picker")
            } footer: {
                NativeSettingsFooter("System follows the appearance chosen in iOS Settings.")
            }
        }
    }
}
