import SwiftUI

// Local chart-style switch for the Usage charts (bars / line / share).
// A plain segmented control: no extra glass layer on top of the reading content.

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
    @Binding var style: NativeUsageChartStyle
    let options: [NativeUsageChartStyle]

    var body: some View {
        Picker(selection: self.$style) {
            ForEach(self.options, id: \.self) { option in
                Label(option.title, systemImage: option.systemImage)
                    .labelStyle(.iconOnly)
                    .tag(option)
            }
        } label: {
            Text("Chart style")
        }
        .pickerStyle(.segmented)
        .frame(width: CGFloat(self.options.count) * 56)
        .sensoryFeedback(.selection, trigger: self.style)
    }
}
