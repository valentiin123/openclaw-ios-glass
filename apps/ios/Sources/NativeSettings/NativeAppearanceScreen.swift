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
@MainActor
struct NativeAppearanceScreen: View {
    @Environment(AppAppearanceModel.self) private var appearanceModel
    var headerSidebarAction: OpenClawSidebarHeaderAction?
    var embedded: Bool = false

    var body: some View {
        NativeSettingsPage(
            title: NativeSettingsDestination.appearance.title,
            headerSidebarAction: self.headerSidebarAction,
            embedded: self.embedded)
        {
            self.list
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(AppAppearancePreference.allCases) { option in
                    self.optionRow(option)
                }
            } footer: {
                Text("System follows the appearance chosen in iOS Settings.")
                    .font(OpenClawType.footnote)
            }
        }
    }

    private func optionRow(_ option: AppAppearancePreference) -> some View {
        let isSelected: Bool = self.appearanceModel.preference == option
        let title: String = NativeAppearancePresentation.title(option)
        let icon: String = NativeAppearancePresentation.icon(option)
        let traits: AccessibilityTraits = isSelected ? .isSelected : []
        return Button {
            self.appearanceModel.select(option)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(OpenClawType.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .font(OpenClawType.body)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(OpenClawType.subheadSemiBold)
                        .foregroundStyle(OpenClawBrand.accent)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(traits)
    }
}
