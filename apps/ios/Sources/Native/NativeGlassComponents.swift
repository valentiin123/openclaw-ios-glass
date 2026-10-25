import SwiftUI

// Shared Liquid Glass building blocks for the Workboard, Automations and Activity screens.
// Glass is used for chrome and controls (pills, chips, header metrics, action bars, icon badges).
// Reading content (titles, notes, logs) stays on quiet opaque surfaces for legibility.

enum NGFilterID {
    static let all: String = "__all__"
}

// MARK: - Pill

/// Small glass capsule with an icon and a short label. State never relies on color alone.
struct NGPill: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage = self.systemImage {
                Image(systemName: systemImage)
                    .font(OpenClawType.caption2SemiBold)
                    .accessibilityHidden(true)
            }
            Text(verbatim: self.text)
                .font(OpenClawType.caption2SemiBold)
                .lineLimit(1)
        }
        .foregroundStyle(self.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .openClawGlassCapsule(tint: self.tint.opacity(0.18))
    }
}

// MARK: - Icon badge

/// Round glass badge holding a status symbol.
struct NGIconBadge: View {
    let systemImage: String
    var tint: Color = .secondary
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: self.systemImage)
            .font(OpenClawType.subheadSemiBold)
            .foregroundStyle(self.tint)
            .frame(width: self.size, height: self.size)
            .openClawGlass(in: Circle(), tint: self.tint.opacity(0.16))
            .accessibilityHidden(true)
    }
}

// MARK: - Summary header

struct NGMetricItem: Identifiable {
    let id: String
    let value: Int
    let label: String
    let systemImage: String
    var tint: Color = .secondary
}

/// Row of glass metric tiles shown at the top of a list.
struct NGSummaryHeader: View {
    let items: [NGMetricItem]

    var body: some View {
        OpenClawGlassControlGroup {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                ForEach(self.items) { item in
                    self.metric(item)
                }
            }
        }
    }

    private func metric(_ item: NGMetricItem) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: item.systemImage)
                    .font(OpenClawType.captionSemiBold)
                    .foregroundStyle(item.tint)
                    .accessibilityHidden(true)
                Text(item.value, format: .number)
                    .font(OpenClawType.title3SemiBold)
                    .monospacedDigit()
            }
            Text(verbatim: item.label)
                .font(OpenClawType.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .openClawGlass(
            in: RoundedRectangle(cornerRadius: 18, style: .continuous),
            tint: item.tint.opacity(0.10))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Filter bar

/// Horizontal glass filter bar. The selected chip is a glass capsule that morphs between options.
struct NGFilterBar: View {
    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        var count: Int?
        var systemImage: String?
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace
    let items: [Item]
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            OpenClawGlassControlGroup {
                HStack(spacing: 6) {
                    ForEach(self.items) { item in
                        self.chip(item)
                    }
                }
            }
            .padding(.horizontal, OpenClawProMetric.pagePadding)
            .padding(.vertical, 6)
        }
        .sensoryFeedback(.selection, trigger: self.selection)
    }

    private func chip(_ item: Item) -> some View {
        let isSelected: Bool = item.id == self.selection
        return Button {
            guard !isSelected else { return }
            OpenClawMotion.perform(reduceMotion: self.reduceMotion) {
                self.selection = item.id
            }
        } label: {
            HStack(spacing: 6) {
                if let systemImage = item.systemImage {
                    Image(systemName: systemImage)
                        .font(OpenClawType.captionSemiBold)
                        .accessibilityHidden(true)
                }
                Text(verbatim: item.title)
                    .font(OpenClawType.subheadSemiBold)
                    .lineLimit(1)
                if let count = item.count {
                    Text(count, format: .number)
                        .font(OpenClawType.captionSemiBold)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .background {
                if isSelected {
                    NGSelectionBackground(namespace: self.namespace)
                } else {
                    Capsule().fill(Color(uiColor: .tertiarySystemFill))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct NGSelectionBackground: View {
    let namespace: Namespace.ID

    var body: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(
                    OpenClawGlassStyle.glass(tint: OpenClawBrand.accent.opacity(0.16), interactive: true),
                    in: Capsule())
                .glassEffectID("ng.filter.selection", in: self.namespace)
        } else {
            Capsule().fill(.thinMaterial)
        }
    }
}

// MARK: - Content surface

/// Opaque card surface with a hairline border, used for reading content.
struct NGCardSurface: ViewModifier {
    var radius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: self.radius, style: .continuous)
                shape
                    .fill(OpenClawBrand.surfaceCard)
                    .overlay {
                        shape.strokeBorder(
                            OpenClawBrand.hairlineBorder,
                            lineWidth: OpenClawProMetric.borderWidth)
                    }
            }
    }
}

extension View {
    func ngCardSurface(radius: CGFloat = 16) -> some View {
        modifier(NGCardSurface(radius: radius))
    }

    /// List row that hosts a free-standing card: no separator, no row background, tight insets.
    func ngCardRow() -> some View {
        self.listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(
                top: 4,
                leading: OpenClawProMetric.pagePadding,
                bottom: 4,
                trailing: OpenClawProMetric.pagePadding))
    }
}

// MARK: - States

/// Loading placeholder: calm pulsing blocks (static under Reduce Motion).
struct NGSkeletonList: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    var rows: Int = 6

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<self.rows, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(height: 76)
            }
        }
        .padding(.horizontal, OpenClawProMetric.pagePadding)
        .padding(.top, 12)
        .opacity(self.pulse ? 0.45 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            guard !self.reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                self.pulse = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading"))
    }
}

/// Error state with a glass retry button. Message comes from the Gateway or the transport.
struct NGErrorState: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        OpenClawEmptyState(
            systemImage: "exclamationmark.triangle",
            title: "Could not load",
            message: .verbatim(self.message))
        {
            Button {
                Task { await self.retry() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .nativeGlassButtonStyle(prominent: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown when the Gateway does not advertise the method behind a screen.
struct NGUnavailableState: View {
    let systemImage: String
    let title: String
    let message: String
    let retry: () async -> Void

    var body: some View {
        OpenClawEmptyState(
            systemImage: self.systemImage,
            title: .verbatim(self.title),
            message: .verbatim(self.message))
        {
            Button {
                Task { await self.retry() }
            } label: {
                Label("Check again", systemImage: "arrow.clockwise")
            }
            .nativeGlassButtonStyle()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Flow layout

/// Wraps pills onto several lines.
struct NGFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth: CGFloat = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0
        for subview in subviews {
            let size: CGSize = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + self.spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + self.spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - self.spacing)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ())
    {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size: CGSize = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + self.spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + self.spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
