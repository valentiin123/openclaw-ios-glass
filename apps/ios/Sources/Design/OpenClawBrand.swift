import Observation
import OpenClawChatUI
import SwiftUI

enum AppAppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appearance.preference"

    static var launchArgumentPreference: AppAppearancePreference? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--openclaw-appearance") else {
            return nil
        }
        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else { return nil }
        return AppAppearancePreference(rawValue: arguments[valueIndex].lowercased())
    }

    var id: String {
        self.rawValue
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
@Observable
final class AppAppearanceModel {
    private(set) var preference: AppAppearancePreference

    init(userDefaults: UserDefaults = .standard) {
        let storedPreference = userDefaults.string(forKey: AppAppearancePreference.storageKey)
            .flatMap(AppAppearancePreference.init(rawValue:))
        self.preference = AppAppearancePreference.launchArgumentPreference ?? storedPreference ?? .system
        if AppAppearancePreference.launchArgumentPreference != nil {
            userDefaults.set(self.preference.rawValue, forKey: AppAppearancePreference.storageKey)
        }
    }

    func select(_ preference: AppAppearancePreference, userDefaults: UserDefaults = .standard) {
        guard self.preference != preference else { return }
        userDefaults.set(preference.rawValue, forKey: AppAppearancePreference.storageKey)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.preference = preference
        }
    }
}

enum OpenClawBrand {
    // Carapace semantic palette: these tokens are shared by voice surfaces that
    // need the web system's quieter ink/paper hierarchy in native SwiftUI.
    static let carapaceElevated = Color(red: 32 / 255.0, green: 32 / 255.0, blue: 36 / 255.0)
    static let carapaceCoral = Color(red: 245 / 255.0, green: 101 / 255.0, blue: 74 / 255.0)
    static let carapaceSea = Color(red: 79 / 255.0, green: 200 / 255.0, blue: 174 / 255.0)
    // Accent fills stay dark enough for white content; foreground accents adapt
    // separately so small labels retain 4.5:1 contrast on dark surfaces and tinted pills.
    // Control UI palette. Sources:
    //  - src/canvas/wrap.ts (WIDGET_BASE_STYLES): --surface, --card, --elevated, --text,
    //    --text-strong, --muted, --border, --border-strong, --accent, --accent-fill, status colors.
    //  - src/gateway/control-ui-public-session-render.ts (PUBLIC_SESSION_STYLES):
    //    --bg-muted, --hover, --panel, --primary-hover, --link.
    // Dark page background is pure black (OLED) by product decision; the web --surface/--bg
    // (#0e1015) is intentionally NOT used for pages. Opaque surfaces sit above it.
    // Accent: light #bd4531 (fill) / #a83c29 (--primary-hover, used for text because #bd4531
    // falls under 4.5:1 on tinted panels); dark #ff5c5c (--accent) / #d13c3c (--accent-fill).
    static let uiAccentFill = adaptiveUIColor(light: (189, 69, 49), dark: (209, 60, 60))
    static let uiAccent = adaptiveUIColor(light: (168, 60, 41), dark: (255, 92, 92))
    static let uiAccentHot = adaptiveUIColor(light: (189, 69, 49), dark: (194, 46, 46))
    static let uiAccentHotForeground = adaptiveUIColor(light: (168, 60, 41), dark: (255, 112, 112))
    static let uiVoid = adaptiveUIColor(light: (250, 249, 247), dark: (0, 0, 0))
    static let uiObsidian = adaptiveUIColor(light: (255, 255, 255), dark: (22, 25, 32))
    static let uiTextSecondary = adaptiveUIColor(light: (110, 105, 96), dark: (139, 139, 148))
    // Status: dark values follow wrap.ts (--ok #22c55e, --warn #f59e0b). Light values and the
    // dark danger/info stay on the previous app values: the web ones (#15803d, #b45309, #dc2626,
    // #2563eb light; #ef4444, #3b82f6 dark) computed under 4.5:1 on 10-12% tinted pills.
    static let uiOK = adaptiveUIColor(light: (19, 122, 62), dark: (34, 197, 94))
    static let uiWarn = adaptiveUIColor(light: (154, 87, 0), dark: (245, 158, 11))
    static let uiDanger = adaptiveUIColor(light: (185, 28, 28), dark: (252, 165, 165))
    static let uiInfo = adaptiveUIColor(light: (0, 91, 196), dark: (100, 168, 255))
    // Surface and ink tokens (wrap.ts / control-ui-public-session-render.ts).
    static let uiCard = adaptiveUIColor(light: (255, 255, 255), dark: (22, 25, 32))
    static let uiElevated = adaptiveUIColor(light: (255, 255, 255), dark: (25, 28, 36))
    static let uiPanel = adaptiveUIColor(light: (244, 241, 236), dark: (25, 28, 36))
    static let uiHover = adaptiveUIColor(light: (239, 235, 228), dark: (31, 35, 48))
    static let uiBorder = adaptiveUIColor(light: (232, 228, 220), dark: (30, 32, 40))
    static let uiBorderStrong = adaptiveUIColor(light: (214, 208, 197), dark: (46, 48, 64))
    static let uiTextPrimary = adaptiveUIColor(light: (64, 60, 53), dark: (212, 212, 216))
    static let uiTextStrong = adaptiveUIColor(light: (33, 30, 26), dark: (244, 244, 245))
    // Carapace status foreground tokens. Keep these separate from the broader
    // app feedback palette so compact state indicators match the web system.
    static let uiStatusSuccess = adaptiveUIColor(light: (22, 163, 74), dark: (34, 197, 94))
    static let uiStatusWarning = adaptiveUIColor(light: (217, 119, 6), dark: (251, 191, 36))
    static let uiStatusError = adaptiveUIColor(light: (220, 38, 38), dark: (239, 68, 68))

    static let accent = Color(uiColor: Self.uiAccent)
    static let accentFill = Color(uiColor: Self.uiAccentFill)
    static let accentHot = Color(uiColor: Self.uiAccentHot)
    static let accentHotForeground = Color(uiColor: Self.uiAccentHotForeground)
    static let void = Color(uiColor: Self.uiVoid)
    static let obsidian = Color(uiColor: Self.uiObsidian)
    static let textSecondary = Color(uiColor: Self.uiTextSecondary)
    static let surfaceCard = Color(uiColor: Self.uiCard)
    static let surfaceElevated = Color(uiColor: Self.uiElevated)
    static let surfacePanel = Color(uiColor: Self.uiPanel)
    static let surfaceHover = Color(uiColor: Self.uiHover)
    static let hairlineBorder = Color(uiColor: Self.uiBorder)
    static let hairlineBorderStrong = Color(uiColor: Self.uiBorderStrong)
    static let textPrimary = Color(uiColor: Self.uiTextPrimary)
    static let textStrong = Color(uiColor: Self.uiTextStrong)
    static let danger = Color(uiColor: Self.uiDanger)
    static let ok = Color(uiColor: Self.uiOK)
    static let warn = Color(uiColor: Self.uiWarn)
    static let info = Color(uiColor: Self.uiInfo)
    static let statusSuccess = Color(uiColor: Self.uiStatusSuccess)
    static let statusWarning = Color(uiColor: Self.uiStatusWarning)
    static let statusError = Color(uiColor: Self.uiStatusError)
    // Keep provider colors aligned with the Control UI brand tokens.
    static let providerOpenAI = Color(red: 16 / 255.0, green: 163 / 255.0, blue: 127 / 255.0)
    static let providerAnthropic = Color(red: 217 / 255.0, green: 119 / 255.0, blue: 87 / 255.0)
    static let providerGoogle = Color(red: 66 / 255.0, green: 133 / 255.0, blue: 244 / 255.0)
    // Activation surfaces follow the same Control UI ink/paper ramp (wrap.ts --surface/--card/--elevated,
    // control-ui-public-session-render.ts --panel); dark canvas is OLED black.
    static let activationCanvas = Color(uiColor: adaptiveUIColor(light: (250, 249, 247), dark: (0, 0, 0)))
    static let activationSurface = Color(uiColor: adaptiveUIColor(light: (255, 255, 255), dark: (22, 25, 32)))
    static let activationInsetSurface = Color(uiColor: adaptiveUIColor(light: (244, 241, 236), dark: (25, 28, 36)))
    static let activationNeutralSurface = Color(uiColor: adaptiveUIColor(light: (255, 255, 255), dark: (22, 25, 32)))
    static let activationNeutralInsetSurface = Color(uiColor: adaptiveUIColor(
        light: (244, 241, 236),
        dark: (25, 28, 36)))
    static let activationNeutralStroke = Color(uiColor: adaptiveUIColor(
        light: (0, 0, 0),
        dark: (255, 255, 255)).withAlphaComponent(0.08))
    static let activationNeutralDivider = Color(uiColor: adaptiveUIColor(
        light: (0, 0, 0),
        dark: (255, 255, 255)).withAlphaComponent(0.09))
    // Same values as uiAccentFill (wrap.ts --accent-fill) so white label text keeps >= 4.5:1.
    static let activationPrimaryAction = Color(uiColor: adaptiveUIColor(light: (189, 69, 49), dark: (209, 60, 60)))
    static let activationPrimaryActionText = Color.white
    static let activationHairline = Color(uiColor: adaptiveUIColor(
        light: (136, 44, 40),
        dark: (255, 210, 205)).withAlphaComponent(0.13))
    static let activationGlow = Color(uiColor: adaptiveUIColor(light: (189, 69, 49), dark: (255, 92, 92)))

    static var sheetBackground: LinearGradient {
        LinearGradient(
            colors: [
                void,
                void,
            ],
            startPoint: .top,
            endPoint: .bottom)
    }

    static var activationCanvasGradient: LinearGradient {
        LinearGradient(
            colors: [
                activationCanvas,
                activationCanvas,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
    }

    static var activationInsetGradient: LinearGradient {
        LinearGradient(
            colors: [
                activationInsetSurface.opacity(0.94),
                activationInsetSurface,
                activationSurface.opacity(0.36),
            ],
            startPoint: .top,
            endPoint: .bottom)
    }

    static var activationNeutralGradient: LinearGradient {
        LinearGradient(
            colors: [
                activationNeutralInsetSurface,
                activationNeutralSurface,
            ],
            startPoint: .top,
            endPoint: .bottom)
    }

    static var activationPrimaryGradient: LinearGradient {
        LinearGradient(
            colors: [
                activationPrimaryAction,
                activationPrimaryAction,
            ],
            startPoint: .top,
            endPoint: .bottom)
    }

    private static func adaptiveUIColor(
        light: (red: CGFloat, green: CGFloat, blue: CGFloat),
        dark: (red: CGFloat, green: CGFloat, blue: CGFloat)) -> UIColor
    {
        UIColor { traits in
            let components = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: components.red / 255,
                green: components.green / 255,
                blue: components.blue / 255,
                alpha: 1)
        }
    }
}

extension TalkWaveformPalette {
    /// iOS app branding for shared voice contours. This lives with the palette
    /// owner so removing a presentation surface cannot remove the app theme.
    static let openClawBrand = TalkWaveformPalette(
        active: [
            OpenClawBrand.carapaceCoral,
            OpenClawBrand.carapaceSea,
            OpenClawBrand.accent,
        ],
        inactive: [
            Color(uiColor: .systemGray2),
            Color(uiColor: .systemGray3),
            Color(uiColor: .systemGray4),
        ])
}

struct OpenClawActivationGlyph: View {
    let size: CGFloat
    var mood: OpenClawMascotMood = .idle
    /// Opt-in tap Easter eggs; leave off when the glyph sits inside a control.
    var interactive = false

    var body: some View {
        OpenClawMascotView(floats: false, mood: self.mood, interactive: self.interactive)
            .frame(width: self.size, height: self.size)
            .shadow(
                color: OpenClawBrand.activationGlow.opacity(0.18),
                radius: self.size * 0.12,
                x: 0,
                y: self.size * 0.05)
            .accessibilityHidden(true)
    }
}

extension View {
    func openClawSheetChrome() -> some View {
        self
            .tint(OpenClawBrand.accent)
            .background {
                OpenClawBrand.sheetBackground
                    .ignoresSafeArea()
            }
    }

    /// Opaque content surface: flat fill, hairline border, no glass, no highlight.
    func openClawCraftSurface(cornerRadius: CGFloat = 12) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(OpenClawBrand.activationSurface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(OpenClawBrand.hairlineBorderStrong, lineWidth: 1)
            }
    }
}

/// Capsule surface shared by the branded button styles, using system
/// Liquid Glass (prominent is tinted).
/// No gradients, sheens, or shadows: they turn into a muddy halo on dark surfaces.
enum OpenClawButtonSurfaceKind {
    case prominent
    case secondary
}

private struct OpenClawButtonSurfaceModifier: ViewModifier {
    let kind: OpenClawButtonSurfaceKind
    let isEnabled: Bool

    private var isFilled: Bool {
        self.kind == .prominent && self.isEnabled
    }

    func body(content: Content) -> some View {
        content.glassEffect(self.glass, in: .capsule)
    }

    private var glass: Glass {
        self.isFilled ? .regular.tint(OpenClawBrand.accentFill).interactive() : .regular.interactive(self.isEnabled)
    }
}

extension View {
    func openClawButtonSurface(
        _ kind: OpenClawButtonSurfaceKind,
        isEnabled: Bool) -> some View
    {
        self.modifier(OpenClawButtonSurfaceModifier(kind: kind, isEnabled: isEnabled))
    }

    /// System prominent button filled with the accent. The app tint is the readable
    /// foreground accent, so prominent fills must opt into the darker fill accent.
    func openClawProminentButton() -> some View {
        self.buttonStyle(.borderedProminent).tint(OpenClawBrand.accentFill)
    }
}

struct OpenClawPrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var height: CGFloat = 54

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OpenClawType.subheadSemiBold)
            .foregroundStyle(self.isEnabled ? OpenClawBrand.activationPrimaryActionText : Color.secondary)
            // Spinners inside the label must not inherit the red app tint over the red fill.
            .tint(self.isEnabled ? OpenClawBrand.activationPrimaryActionText : Color.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: self.height)
            .openClawButtonSurface(.prominent, isEnabled: self.isEnabled)
            .contentShape(Capsule(style: .continuous))
    }
}

struct OpenClawSecondaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var height: CGFloat = 50

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OpenClawType.subheadSemiBold)
            .foregroundStyle(self.isEnabled ? OpenClawBrand.accent : Color.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: self.height)
            .openClawButtonSurface(.secondary, isEnabled: self.isEnabled)
            .contentShape(Capsule(style: .continuous))
    }
}

struct OpenClawCloseButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var minWidth: CGFloat = 36
    var height: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OpenClawType.subheadSemiBold)
            .foregroundStyle(self.isEnabled ? OpenClawBrand.accent : Color.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: self.minWidth, minHeight: self.height)
            .padding(.horizontal, 7)
            .openClawButtonSurface(.secondary, isEnabled: self.isEnabled)
            // Visual stays 36pt; the vertical padding brings the hit area to 44pt.
            .padding(.vertical, 4)
            .contentShape(Rectangle())
    }
}
