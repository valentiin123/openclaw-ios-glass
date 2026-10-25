import SwiftUI

extension EnvironmentValues {
    @Entry public var openClawChatDesktopLayout = false
}

#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if os(macOS)
extension NSAppearance {
    fileprivate var isDarkAqua: Bool {
        self.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
#endif

public enum OpenClawChatTheme {
    public static func desktopCanvas(in colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(.sRGB, red: 14 / 255.0, green: 16 / 255.0, blue: 21 / 255.0)
            : Color(.sRGB, red: 250 / 255.0, green: 249 / 255.0, blue: 247 / 255.0)
    }

    public static func desktopComposer(in colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(.sRGB, red: 25 / 255.0, green: 28 / 255.0, blue: 36 / 255.0)
            : .white
    }

    public static func desktopAccent(in colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(.sRGB, red: 255 / 255.0, green: 92 / 255.0, blue: 92 / 255.0)
            : Color(.sRGB, red: 189 / 255.0, green: 69 / 255.0, blue: 49 / 255.0)
    }

    public static func desktopPrimary(in colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(.sRGB, red: 209 / 255.0, green: 60 / 255.0, blue: 60 / 255.0)
            : self.desktopAccent(in: colorScheme)
    }

    public static func desktopText(in colorScheme: ColorScheme, contrast: ColorSchemeContrast) -> Color {
        if contrast == .increased {
            return colorScheme == .dark
                ? Color(.sRGB, red: 244 / 255.0, green: 244 / 255.0, blue: 245 / 255.0)
                : Color(.sRGB, red: 33 / 255.0, green: 30 / 255.0, blue: 26 / 255.0)
        }
        return colorScheme == .dark
            ? Color(.sRGB, red: 188 / 255.0, green: 188 / 255.0, blue: 192 / 255.0)
            : Color(.sRGB, red: 64 / 255.0, green: 60 / 255.0, blue: 53 / 255.0)
    }

    static func desktopUserBubble(in colorScheme: ColorScheme, accent: Color?) -> Color {
        // Bound the accent contribution so even its lightest/darkest extremes retain reading contrast.
        self.desktopCanvas(in: colorScheme)
            .mix(with: accent ?? self.desktopAccent(in: colorScheme), by: 0.15, in: .device)
    }

    #if !os(macOS)
    private enum IOSPalette {
        // Exact product palette (mirrors OpenClawPalette in the iOS app target, which this
        // shared package cannot import).
        static func ui(_ value: UInt32) -> UIColor {
            let red: CGFloat = CGFloat((value >> 16) & 0xFF) / 255
            let green: CGFloat = CGFloat((value >> 8) & 0xFF) / 255
            let blue: CGFloat = CGFloat(value & 0xFF) / 255
            return UIColor(red: red, green: green, blue: blue, alpha: 1)
        }

        // Light: fond, fondAlt, carte, survol, accent, texteStandard, texteAtténué, bordure.
        static let lightCanvas: UIColor = ui(0xFAF9F7)
        static let lightAlt: UIColor = ui(0xF4F1EC)
        static let lightCard: UIColor = ui(0xFFFFFF)
        static let lightHover: UIColor = ui(0xEFEBE4)
        static let lightAccent: UIColor = ui(0xBD4531)
        static let lightText: UIColor = ui(0x403C35)
        static let lightMuted: UIColor = ui(0x6E6960)
        static let lightBorder: UIColor = ui(0xE8E4DC)
        // Dark: fond, fondAlt, carte, surélevée, survol, boutonPrimaire, texteStandard,
        // texteAtténué, bordure.
        static let darkCanvas: UIColor = ui(0x0E1015)
        static let darkAlt: UIColor = ui(0x13151B)
        static let darkCard: UIColor = ui(0x161920)
        static let darkRaised: UIColor = ui(0x191C24)
        static let darkHover: UIColor = ui(0x1F2330)
        static let darkPrimary: UIColor = ui(0xD13C3C)
        static let darkText: UIColor = ui(0xBCBCC0)
        static let darkMuted: UIColor = ui(0x8B8B94)
        static let darkBorder: UIColor = ui(0x1E2028)
    }

    private static func adaptiveColor(
        light: UIColor,
        dark: UIColor) -> Color
    {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
    #endif

    #if os(macOS)
    static func resolvedAssistantBubbleColor(for appearance: NSAppearance) -> NSColor {
        // NSColor semantic colors don't reliably resolve for arbitrary NSAppearance in SwiftPM.
        // Use explicit light/dark values so the bubble updates when the system appearance flips.
        appearance.isDarkAqua
            ? NSColor(calibratedWhite: 0.18, alpha: 0.88)
            : NSColor(calibratedWhite: 0.94, alpha: 0.92)
    }

    static func resolvedOnboardingAssistantBubbleColor(for appearance: NSAppearance) -> NSColor {
        appearance.isDarkAqua
            ? NSColor(calibratedWhite: 0.20, alpha: 0.94)
            : NSColor(calibratedWhite: 0.97, alpha: 0.98)
    }

    static let assistantBubbleDynamicNSColor = NSColor(
        name: NSColor.Name("OpenClawChatTheme.assistantBubble"),
        dynamicProvider: resolvedAssistantBubbleColor(for:))

    static let onboardingAssistantBubbleDynamicNSColor = NSColor(
        name: NSColor.Name("OpenClawChatTheme.onboardingAssistantBubble"),
        dynamicProvider: resolvedOnboardingAssistantBubbleColor(for:))
    #endif

    @ViewBuilder
    static var background: some View {
        #if os(macOS)
        // Plain material so the chat reads as a native surface; the window
        // (or the anchored panel's effect view) supplies the vibrancy.
        Rectangle()
            .fill(.ultraThinMaterial)
        #else
        ZStack {
            LinearGradient(
                colors: [
                    self.adaptiveColor(light: IOSPalette.lightCanvas, dark: IOSPalette.darkCanvas),
                    self.adaptiveColor(light: IOSPalette.lightCanvas, dark: IOSPalette.darkCanvas),
                    self.adaptiveColor(light: IOSPalette.lightCanvas, dark: IOSPalette.darkCanvas),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)
        }
        #endif
    }

    static var subtleCard: AnyShapeStyle {
        #if os(macOS)
        AnyShapeStyle(.ultraThinMaterial)
        #else
        AnyShapeStyle(self.adaptiveColor(light: IOSPalette.lightCard, dark: IOSPalette.darkCard))
        #endif
    }

    static var userBubble: Color {
        #if os(macOS)
        // Follow the user's system accent; hosts can still override per-view
        // with `userAccent` (e.g. the seam color in the desktop app).
        Color(nsColor: .controlAccentColor)
        #else
        self.adaptiveColor(
            light: IOSPalette.lightAccent,
            dark: IOSPalette.darkPrimary)
        #endif
    }

    static var accent: Color {
        self.userBubble
    }

    /// Discreet opaque surface behind the user's own messages. Assistant replies have no surface.
    static var userSurface: Color {
        #if os(macOS)
        Color(nsColor: .quaternarySystemFill)
        #else
        self.adaptiveColor(light: IOSPalette.lightAlt, dark: IOSPalette.darkRaised)
        #endif
    }

    static var danger: Color {
        #if os(macOS)
        Color(nsColor: .systemRed)
        #else
        Color(uiColor: .systemRed)
        #endif
    }

    static var muted: Color {
        #if os(macOS)
        .secondary
        #else
        self.adaptiveColor(light: IOSPalette.lightMuted, dark: IOSPalette.darkMuted)
        #endif
    }

    static var warning: Color {
        #if os(macOS)
        Color(nsColor: .systemOrange)
        #else
        Color(uiColor: .systemOrange)
        #endif
    }

    static var success: Color {
        #if os(macOS)
        Color(nsColor: .systemGreen)
        #else
        Color(uiColor: .systemGreen)
        #endif
    }

    static var assistantBubble: Color {
        #if os(macOS)
        Color(nsColor: self.assistantBubbleDynamicNSColor)
        #else
        // Receiver bubble: palette survol in light, surélevée in dark, both distinct from the canvas.
        self.adaptiveColor(light: IOSPalette.lightHover, dark: IOSPalette.darkRaised)
        #endif
    }

    static var onboardingAssistantBubble: Color {
        #if os(macOS)
        Color(nsColor: self.onboardingAssistantBubbleDynamicNSColor)
        #else
        self.adaptiveColor(light: IOSPalette.lightAlt, dark: IOSPalette.darkRaised)
        #endif
    }

    static var onboardingAssistantBorder: Color {
        #if os(macOS)
        Color.white.opacity(0.12)
        #else
        self.adaptiveColor(light: IOSPalette.lightBorder, dark: IOSPalette.darkBorder)
        #endif
    }

    static var userText: Color {
        .white
    }

    /// Readable ink for text rendered on a host-supplied user accent. Mirrors the
    /// Control UI accent contract (ui/src/app/control-ui-presentation.ts): WCAG
    /// relative luminance, black/white reach equal contrast at 0.179. Without it,
    /// light accents like #fbbf24 render unreadable fixed-white user text.
    static func userText(on accent: Color?) -> Color {
        guard let accent else { return self.userText }
        return self.relativeLuminance(of: accent) > 0.179 ? .black : .white
    }

    static func relativeLuminance(of color: Color) -> Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        #if os(macOS)
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return 0 }
        rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #else
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return 0 }
        #endif
        func linear(_ channel: CGFloat) -> Double {
            let c = Double(channel)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    static var assistantText: Color {
        #if os(macOS)
        Color(nsColor: .labelColor)
        #else
        self.adaptiveColor(light: IOSPalette.lightText, dark: IOSPalette.darkText)
        #endif
    }

    static var composerBackground: AnyShapeStyle {
        #if os(macOS)
        AnyShapeStyle(.ultraThinMaterial)
        #else
        AnyShapeStyle(self.adaptiveColor(light: IOSPalette.lightCard, dark: IOSPalette.darkCard))
        #endif
    }

    static var composerField: AnyShapeStyle {
        #if os(macOS)
        AnyShapeStyle(.thinMaterial)
        #else
        AnyShapeStyle(self.adaptiveColor(light: IOSPalette.lightAlt, dark: IOSPalette.darkRaised))
        #endif
    }

    static var composerBorder: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor).opacity(0.6)
        #else
        self.adaptiveColor(light: IOSPalette.lightBorder, dark: IOSPalette.darkBorder)
        #endif
    }

    static var divider: Color {
        #if os(macOS)
        Color.secondary.opacity(0.2)
        #else
        self.adaptiveColor(light: IOSPalette.lightBorder, dark: IOSPalette.darkBorder)
        #endif
    }
}

fileprivate struct ChatPaletteRGB {
    let red: Double
    let green: Double
    let blue: Double

    init(hex: UInt32) {
        self.red = Double((hex >> 16) & 0xFF) / 255.0
        self.green = Double((hex >> 8) & 0xFF) / 255.0
        self.blue = Double(hex & 0xFF) / 255.0
    }
}

// Exact chat palette (light / dark). Content colors for the redesigned transcript:
// code blocks, quotes, tool cards, reasoning and subagent rows use these, never hard-coded values.
extension OpenClawChatTheme {
    private static func paletteColor(light: UInt32, dark: UInt32) -> Color {
        let lightRGB: ChatPaletteRGB = ChatPaletteRGB(hex: light)
        let darkRGB: ChatPaletteRGB = ChatPaletteRGB(hex: dark)
        #if os(macOS)
        let dynamicColor: NSColor = NSColor(name: nil, dynamicProvider: { appearance in
            let rgb: ChatPaletteRGB = appearance.isDarkAqua ? darkRGB : lightRGB
            return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
        return Color(nsColor: dynamicColor)
        #else
        let dynamicColor: UIColor = UIColor { traits in
            let rgb: ChatPaletteRGB = traits.userInterfaceStyle == .dark ? darkRGB : lightRGB
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        }
        return Color(uiColor: dynamicColor)
        #endif
    }

    /// Primary brand accent: #BD4531 light, #FF5C5C dark.
    static var brandAccent: Color {
        self.paletteColor(light: 0xBD4531, dark: 0xFF5C5C)
    }

    /// Accent hover / pressed: #A83C29 light, #FF7070 dark.
    static var brandAccentHover: Color {
        self.paletteColor(light: 0xA83C29, dark: 0xFF7070)
    }

    /// Secondary accent (teal): #0D9488 light, #14B8A6 dark.
    static var brandSecondary: Color {
        self.paletteColor(light: 0x0D9488, dark: 0x14B8A6)
    }

    /// Strong text: #211E1A light, #F4F4F5 dark.
    static var inkStrong: Color {
        self.paletteColor(light: 0x211E1A, dark: 0xF4F4F5)
    }

    /// Standard text: #403C35 light, #BCBCC0 dark.
    static var inkStandard: Color {
        self.paletteColor(light: 0x403C35, dark: 0xBCBCC0)
    }

    /// Muted text: #6E6960 light, #8B8B94 dark.
    static var inkMuted: Color {
        self.paletteColor(light: 0x6E6960, dark: 0x8B8B94)
    }

    /// Alternate background (code body): #F4F1EC light, #13151B dark.
    static var surfaceAlt: Color {
        self.paletteColor(light: 0xF4F1EC, dark: 0x13151B)
    }

    /// Card surface: #FFFFFF light, #161920 dark.
    static var surfaceCard: Color {
        self.paletteColor(light: 0xFFFFFF, dark: 0x161920)
    }

    /// Raised surface: #FFFFFF light, #191C24 dark.
    static var surfaceRaised: Color {
        self.paletteColor(light: 0xFFFFFF, dark: 0x191C24)
    }

    /// Hover / header strip: #EFEBE4 light, #1F2330 dark.
    static var surfaceHover: Color {
        self.paletteColor(light: 0xEFEBE4, dark: 0x1F2330)
    }

    /// Hairline border: #E8E4DC light, #1E2028 dark.
    static var hairline: Color {
        self.paletteColor(light: 0xE8E4DC, dark: 0x1E2028)
    }

    /// Violet for agent and web tool kinds (system color, adapts by itself).
    static var violet: Color {
        #if os(macOS)
        Color(nsColor: .systemPurple)
        #else
        Color(uiColor: .systemPurple)
        #endif
    }

    /// Informational blue for running subagents and web tools (system color, adapts by itself).
    static var info: Color {
        #if os(macOS)
        Color(nsColor: .systemBlue)
        #else
        Color(uiColor: .systemBlue)
        #endif
    }
}

enum OpenClawPlatformImageFactory {
    static func image(_ image: OpenClawPlatformImage) -> Image {
        #if os(macOS)
        Image(nsImage: image)
        #else
        Image(uiImage: image)
        #endif
    }
}
