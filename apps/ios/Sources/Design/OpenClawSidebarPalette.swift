import SwiftUI
import UIKit

/// Sidebar surface tokens. The drawer follows the app appearance (owner decision
/// superseding always-dark). Values come from the Control UI palette:
///  - src/canvas/wrap.ts: --surface, --card, --text, --text-strong, --muted, --border-strong
///  - src/gateway/control-ui-public-session-render.ts: --bg (light), --bg-muted, --hover, --panel, --border
/// Dark background stays pure black (OLED); elevated and selection are opaque surfaces above it.
/// Muted text keeps >= 4.5:1 on background, elevated and selection in both appearances.
enum OpenClawSidebarPalette {
    static let background = adaptive(light: 0xFAF9F7, dark: 0x000000)
    static let elevated = adaptive(light: 0xF4F1EC, dark: 0x161920)
    static let selection = adaptive(light: 0xEFEBE4, dark: 0x1F2330)
    static let text = adaptive(light: 0x403C35, dark: 0xD4D4D8)
    static let textStrong = adaptive(light: 0x211E1A, dark: 0xF4F4F5)
    static let muted = adaptive(light: 0x6E6960, dark: 0x8B8B94)
    static let accent = OpenClawBrand.accent

    /// Opaque hairline: --border-strong in dark (#2e3040), --border in light (#e8e4dc).
    static let hairline = adaptive(light: 0xE8E4DC, dark: 0x2E3040)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1)
        })
    }
}
