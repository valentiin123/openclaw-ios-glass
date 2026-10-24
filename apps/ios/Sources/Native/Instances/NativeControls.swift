import SwiftUI

/// Shared native controls for the Workboard and Instances screens.
/// Liquid Glass is applied to controls only; content rows stay on opaque list surfaces.
extension View {
    @ViewBuilder
    func nativeGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }

    /// Guarantees the 44 pt minimum hit target for compact controls.
    func nativeMinimumTapTarget() -> some View {
        self.frame(minWidth: 44, minHeight: 44)
    }
}

/// Inline banner for a failed action or a section-level problem. Icon + text, never color alone.
struct NativeInlineNotice: View {
    let message: String
    var systemImage: String = "exclamationmark.triangle"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: self.systemImage)
                .accessibilityHidden(true)
            Text(verbatim: self.message)
                .font(OpenClawType.subhead)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}
