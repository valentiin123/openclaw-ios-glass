import SwiftUI

// Shared building blocks of the Overview. Same family as the Agents board tiles:
// opaque slightly rounded rectangle, hairline border, no shadow, no glass.
// Liquid Glass stays on bars, controls and buttons only.
// Compiler hygiene: typed constants, small @ViewBuilder properties, no nested trailing closures.

enum OverviewMetric {
    /// Same radius as the Agents board tiles.
    static let radius: CGFloat = OpenClawRadius.md
    /// Minimum hit target.
    static let minTarget: CGFloat = 44
    static let sectionSpacing: CGFloat = 16
}

/// One figure of the summary strip.
struct OverviewStat: Identifiable {
    let id: String
    let title: String
    let value: String
}

// MARK: - Surface

private struct OverviewTileModifier: ViewModifier {
    let tint: Color?

    func body(content: Content) -> some View {
        let shape: RoundedRectangle = RoundedRectangle(
            cornerRadius: OverviewMetric.radius,
            style: .continuous)
        let border: Color = self.borderColor
        return content
            .background(shape.fill(OpenClawBrand.surfaceCard))
            .clipShape(shape)
            .overlay(shape.strokeBorder(border, lineWidth: OpenClawProMetric.borderWidth))
    }

    private var borderColor: Color {
        guard let tint = self.tint else { return OpenClawBrand.hairlineBorderStrong }
        return tint.opacity(0.45)
    }
}

extension View {
    /// Opaque tile surface with a hairline border. Optional tint colours the border only.
    func overviewTile(tint: Color? = nil) -> some View {
        self.modifier(OverviewTileModifier(tint: tint))
    }
}

// MARK: - Press feedback

/// Press feedback of a tile: shared press scale, dimmed instead of scaled under Reduce Motion.
struct OverviewPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPressed: Bool = configuration.isPressed
        let scaled: Bool = isPressed && !self.reduceMotion
        let scale: CGFloat = scaled ? OpenClawMotion.pressedScale : 1
        let dim: Double = isPressed ? 0.88 : 1
        let animation: Animation = OpenClawMotion.animation(reduceMotion: self.reduceMotion)
        return configuration.label
            .scaleEffect(scale)
            .opacity(dim)
            .animation(animation, value: isPressed)
    }
}

// MARK: - Section label

/// Small caption above a section, with a discreet square "pixel" marker.
struct OverviewSectionLabel: View {
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(OpenClawBrand.accent)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(self.title)
                .font(OpenClawType.captionSemiBold)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
