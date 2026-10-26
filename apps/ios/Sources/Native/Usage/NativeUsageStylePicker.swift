import SwiftUI

// Local chart-style switch for the Usage charts (bars / line / share).
// Opaque control (no glass on top of reading content), every segment is a 44 x 44 pt hit target.

enum NativeUsageChartStyle: Hashable {
    case bars
    case line
    case share

    var systemImage: String {
        switch self {
        case .bars: "chart.bar.fill"
        case .line: "chart.xyaxis.line"
        case .share: "chart.pie.fill"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .bars: "Bars"
        case .line: "Line"
        case .share: "Share"
        }
    }
}

struct NativeUsageStylePicker: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var style: NativeUsageChartStyle
    let options: [NativeUsageChartStyle]

    private static let targetSize: CGFloat = 44

    var body: some View {
        HStack(spacing: 2) {
            ForEach(self.options, id: \.self) { (option: NativeUsageChartStyle) in
                self.segment(option)
            }
        }
        .padding(2)
        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Chart style"))
        .sensoryFeedback(.selection, trigger: self.style)
    }

    private func segment(_ option: NativeUsageChartStyle) -> some View {
        let isSelected: Bool = self.style == option
        return Button {
            guard !isSelected else { return }
            OpenClawMotion.perform(reduceMotion: self.reduceMotion) { self.style = option }
        } label: {
            Label(option.title, systemImage: option.systemImage)
                .labelStyle(.iconOnly)
                .font(OpenClawType.subheadSemiBold)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .frame(minWidth: Self.targetSize, minHeight: Self.targetSize)
                .background {
                    if isSelected {
                        Capsule().fill(OpenClawBrand.accent)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
