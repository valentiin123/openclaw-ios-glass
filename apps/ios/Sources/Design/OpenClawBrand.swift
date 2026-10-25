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

/// Exact product palette: the single source of truth for the iOS theme.
/// Every token is adaptive (light/dark) and exposed twice: `uiX` (UIColor) and `x` (Color).
///
/// Light: fond #FAF9F7, fondAlt #F4F1EC, carte #FFFFFF, survol #EFEBE4, accent #BD4531,
/// accentSurvol #A83C29, accentSecondaire #0D9488, texteFort #211E1A, texteStandard #403C35,
/// texteAtténué #6E6960, bordure #E8E4DC.
/// Dark: fond #0E1015, fondAlt #13151B, carte #161920, surélevée #191C24, survol #1F2330,
/// accent #FF5C5C, accentSurvol #FF7070, boutonPrimaire #D13C3C, accentSecondaire #14B8A6,
/// texteFort #F4F4F5, texteStandard #BCBCC0, texteAtténué #8B8B94, bordure #1E2028.
///
/// Light has no dedicated surélevée / boutonPrimaire value: surélevée falls back to carte
/// (#FFFFFF) and boutonPrimaire to accent (#BD4531).
enum OpenClawPalette {
    // MARK: UIColor tokens

    static let uiFond: UIColor = uiAdaptive(light: 0xFAF9F7, dark: 0x0E1015)
    static let uiFondAlt: UIColor = uiAdaptive(light: 0xF4F1EC, dark: 0x13151B)
    static let uiCarte: UIColor = uiAdaptive(light: 0xFFFFFF, dark: 0x161920)
    static let uiSurélevée: UIColor = uiAdaptive(light: 0xFFFFFF, dark: 0x191C24)
    static let uiSurvol: UIColor = uiAdaptive(light: 0xEFEBE4, dark: 0x1F2330)
    static let uiAccent: UIColor = uiAdaptive(light: 0xBD4531, dark: 0xFF5C5C)
    static let uiAccentSurvol: UIColor = uiAdaptive(light: 0xA83C29, dark: 0xFF7070)
    static let uiAccentSecondaire: UIColor = uiAdaptive(light: 0x0D9488, dark: 0x14B8A6)
    static let uiBoutonPrimaire: UIColor = uiAdaptive(light: 0xBD4531, dark: 0xD13C3C)
    static let uiTexteFort: UIColor = uiAdaptive(light: 0x211E1A, dark: 0xF4F4F5)
    static let uiTexteStandard: UIColor = uiAdaptive(light: 0x403C35, dark: 0xBCBCC0)
    static let uiTexteAtténué: UIColor = uiAdaptive(light: 0x6E6960, dark: 0x8B8B94)
    static let uiBordure: UIColor = uiAdaptive(light: 0xE8E4DC, dark: 0x1E2028)

    // Derived roles (palette hexes only).
    /// Readable accent for small text: light uses accentSurvol (#A83C29) because #BD4531
    /// drops under 4.5:1 on hover and tinted surfaces; dark uses accent (#FF5C5C).
    static let uiAccentTexte: UIColor = uiAdaptive(light: 0xA83C29, dark: 0xFF5C5C)
    /// Inset panel inside a card: fondAlt in light, surélevée in dark.
    static let uiSurfaceInset: UIColor = uiAdaptive(light: 0xF4F1EC, dark: 0x191C24)

    // MARK: Color tokens

    static let fond: Color = Color(uiColor: uiFond)
    static let fondAlt: Color = Color(uiColor: uiFondAlt)
    static let carte: Color = Color(uiColor: uiCarte)
    static let surélevée: Color = Color(uiColor: uiSurélevée)
    static let survol: Color = Color(uiColor: uiSurvol)
    static let accent: Color = Color(uiColor: uiAccent)
    static let accentSurvol: Color = Color(uiColor: uiAccentSurvol)
    static let accentSecondaire: Color = Color(uiColor: uiAccentSecondaire)
    static let boutonPrimaire: Color = Color(uiColor: uiBoutonPrimaire)
    static let texteFort: Color = Color(uiColor: uiTexteFort)
    static let texteStandard: Color = Color(uiColor: uiTexteStandard)
    static let texteAtténué: Color = Color(uiColor: uiTexteAtténué)
    static let bordure: Color = Color(uiColor: uiBordure)
    static let accentTexte: Color = Color(uiColor: uiAccentTexte)
    static let surfaceInset: Color = Color(uiColor: uiSurfaceInset)

    static func uiAdaptive(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            let value: UInt32 = traits.userInterfaceStyle == .dark ? dark : light
            let red: CGFloat = CGFloat((value >> 16) & 0xFF) / 255
            let green: CGFloat = CGFloat((value >> 8) & 0xFF) / 255
            let blue: CGFloat = CGFloat(value & 0xFF) / 255
            return UIColor(red: red, green: green, blue: blue, alpha: 1)
        }
    }
}

enum OpenClawBrand {
    // Carapace semantic palette: these tokens are shared by voice surfaces that
    // need the web system's quieter ink/paper hierarchy in native SwiftUI.
    // carapaceElevated backs a white glyph in both appearances, so it stays the dark
    // palette "surélevée" (#191C24) instead of adapting.
    static let carapaceElevated = Color(red: 25 / 255.0, green: 28 / 255.0, blue: 36 / 255.0)
    static let carapaceCoral = OpenClawPalette.accent
    static let carapaceSea = OpenClawPalette.accentSecondaire
    // Accent fills stay dark enough for white content; foreground accents adapt
    // separately so small labels retain 4.5:1 contrast on dark surfaces and tinted pills.
    // Control UI palette. Sources:
    //  - src/canvas/wrap.ts (WIDGET_BASE_STYLES): --surface, --card, --elevated, --text,
    //    --text-strong, --muted, --border, --border-strong, --accent, --accent-fill, status colors.
    //  - src/gateway/control-ui-public-session-render.ts (PUBLIC_SESSION_STYLES):
    //    --bg-muted, --hover, --panel, --primary-hover, --link.
    // Values come from OpenClawPalette (exact product palette). The dark page background is
    // #0E1015; the former OLED black is gone. Foreground accents use the palette's
    // accentSurvol in light (#A83C29) because #BD4531 falls under 4.5:1 on hover and tinted
    // surfaces; fills use boutonPrimaire.
    static let uiAccentFill = OpenClawPalette.uiBoutonPrimaire
    static let uiAccent = OpenClawPalette.uiAccentTexte
    static let uiAccentHot = OpenClawPalette.uiBoutonPrimaire
    static let uiAccentHotForeground = OpenClawPalette.uiAccentSurvol
    static let uiVoid = OpenClawPalette.uiFond
    static let uiObsidian = OpenClawPalette.uiCarte
    static let uiTextSecondary = OpenClawPalette.uiTexteAtténué
    // Status: dark values follow wrap.ts (--ok #22c55e, --warn #f59e0b). Light values and the
    // dark danger/info stay on the previous app values: the web ones (#15803d, #b45309, #dc2626,
    // #2563eb light; #ef4444, #3b82f6 dark) computed under 4.5:1 on 10-12% tinted pills.
    static let uiOK = adaptiveUIColor(light: (19, 122, 62), dark: (34, 197, 94))
    static let uiWarn = adaptiveUIColor(light: (154, 87, 0), dark: (245, 158, 11))
    static let uiDanger = adaptiveUIColor(light: (185, 28, 28), dark: (252, 165, 165))
    static let uiInfo = adaptiveUIColor(light: (0, 91, 196), dark: (100, 168, 255))
    // Surface and ink tokens (wrap.ts / control-ui-public-session-render.ts).
    static let uiCard = OpenClawPalette.uiCarte
    static let uiElevated = OpenClawPalette.uiSurélevée
    static let uiPanel = OpenClawPalette.uiFondAlt
    static let uiHover = OpenClawPalette.uiSurvol
    static let uiBorder = OpenClawPalette.uiBordure
    // The palette defines a single border color, so the strong border equals it.
    static let uiBorderStrong = OpenClawPalette.uiBordure
    static let uiTextPrimary = OpenClawPalette.uiTexteStandard
    static let uiTextStrong = OpenClawPalette.uiTexteFort
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
    // Activation surfaces follow the exact palette ramp; dark canvas is #0E1015.
    static let activationCanvas = OpenClawPalette.fond
    static let activationSurface = OpenClawPalette.carte
    static let activationInsetSurface = OpenClawPalette.surfaceInset
    static let activationNeutralSurface = OpenClawPalette.carte
    static let activationNeutralInsetSurface = OpenClawPalette.surfaceInset
    static let activationNeutralStroke = OpenClawPalette.bordure
    static let activationNeutralDivider = OpenClawPalette.bordure
    // Same value as uiAccentFill (boutonPrimaire) so white label text keeps >= 4.5:1.
    static let activationPrimaryAction = OpenClawPalette.boutonPrimaire
    static let activationPrimaryActionText = Color.white
    static let activationHairline = Color(uiColor: OpenClawPalette.uiAccent.withAlphaComponent(0.13))
    static let activationGlow = OpenClawPalette.accent

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
