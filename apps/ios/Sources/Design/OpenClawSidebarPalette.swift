import SwiftUI
import UIKit

/// Sidebar surface tokens. The drawer follows the app appearance. Every value comes from
/// `OpenClawPalette` (exact product palette), so the sidebar cannot drift from the app theme:
///  - background: fond (light #FAF9F7, dark #0E1015)
///  - elevated: fondAlt (light #F4F1EC, dark #13151B)
///  - selection: survol (light #EFEBE4, dark #1F2330)
///  - text / textStrong / muted: texteStandard / texteFort / texteAtténué
///  - hairline: bordure (light #E8E4DC, dark #1E2028)
/// Muted text keeps >= 4.5:1 on background, elevated and selection in both appearances.
enum OpenClawSidebarPalette {
    static let background: Color = OpenClawPalette.fond
    static let elevated: Color = OpenClawPalette.fondAlt
    static let selection: Color = OpenClawPalette.survol
    static let text: Color = OpenClawPalette.texteStandard
    static let textStrong: Color = OpenClawPalette.texteFort
    static let muted: Color = OpenClawPalette.texteAtténué
    static let accent: Color = OpenClawBrand.accent

    /// Opaque hairline: the palette defines a single border color.
    static let hairline: Color = OpenClawPalette.bordure
}
