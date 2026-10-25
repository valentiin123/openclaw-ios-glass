import SwiftUI

// Building blocks of the Activity tab (Activity + Automations pages).
// Visual language: same family as the Overview tiles and the Agents board tiles. Opaque surfaces,
// slightly rounded rectangles (OpenClawRadius), hairline borders, square "pixel" state glyphs,
// no shadow and no glass. The only Liquid Glass of the tab is the system tab bar (and the copy toast).
// Compiler hygiene: typed constants, small @ViewBuilder properties, no nested trailing closures.

// MARK: - Metrics

enum ActivityMetric {
    /// Same radius as the Overview and Agents tiles.
    static let radius: CGFloat = OpenClawRadius.md
    static let controlRadius: CGFloat = OpenClawRadius.sm
    static let glyphRadius: CGFloat = OpenClawRadius.xs
    static let minTarget: CGFloat = OpenClawHitTarget.minimum

    /// Insets of a plain list row: the row owns its own vertical padding.
    static let rowInsets: EdgeInsets = EdgeInsets(
        top: 0,
        leading: OpenClawProMetric.pagePadding,
        bottom: 0,
        trailing: OpenClawProMetric.pagePadding)

    /// Insets of a free-standing block inside a list (summary, insights).
    static let blockInsets: EdgeInsets = EdgeInsets(
        top: OpenClawSpace.sm,
        leading: OpenClawProMetric.pagePadding,
        bottom: OpenClawSpace.sm,
        trailing: OpenClawProMetric.pagePadding)
}

// MARK: - Page header slot

private struct ActivityHeaderKey: EnvironmentKey {
    static var defaultValue: AnyView? {
        nil
    }
}

extension EnvironmentValues {
    /// Page header (title + section selector) injected by the Activity tab of the shell. Each hosted
    /// screen draws it as the first row of its own root content, so a pushed detail screen (which
    /// has its own navigation bar) can never end up under it. Nil when a screen is used standalone.
    var activityHeader: AnyView? {
        get { self[ActivityHeaderKey.self] }
        set { self[ActivityHeaderKey.self] = newValue }
    }
}

/// Draws the injected page header, or nothing when there is none.
struct ActivityHeaderSlot: View {
    @Environment(\.activityHeader) private var header: AnyView?

    var body: some View {
        if let header = self.header {
            header
        }
    }
}

private struct ActivityNavigationChrome: ViewModifier {
    @Environment(\.activityHeader) private var header: AnyView?
    let title: String
    let sidebar: OpenClawSidebarHeaderAction?

    @ViewBuilder
    func body(content: Content) -> some View {
        if self.header != nil {
            content.toolbar(.hidden, for: .navigationBar)
        } else {
            content.nativeChrome(title: self.title, sidebar: self.sidebar)
        }
    }
}

extension View {
    /// Hides the navigation bar when the shell owns the header, otherwise keeps the inline title.
    func activityNavigationChrome(title: String, sidebar: OpenClawSidebarHeaderAction?) -> some View {
        modifier(ActivityNavigationChrome(title: title, sidebar: sidebar))
    }

    /// Plain list row: no separator, no row background, the row owns its vertical padding.
    func activityPlainRow() -> some View {
        self.listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(ActivityMetric.rowInsets)
    }

    /// Free-standing block (summary, insights) inside a list.
    func activityBlockRow() -> some View {
        self.listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(ActivityMetric.blockInsets)
    }
}

/// The single header of the page: title (current section) and the section selector under it.
struct ActivityPageHeader<Value: Hashable>: View {
    let title: OpenClawTextValue
    @Binding var selection: Value
    let options: [ActivitySegmentOption<Value>]

    var body: some View {
        VStack(alignment: .leading, spacing: OpenClawSpace.md) {
            self.titleLine
            ActivitySegmented(selection: self.$selection, options: self.options)
        }
        .padding(.horizontal, OpenClawProMetric.pagePadding)
        .padding(.top, OpenClawSpace.sm)
        .padding(.bottom, OpenClawSpace.sm)
    }

    private var titleLine: some View {
        HStack(spacing: OpenClawSpace.sm) {
            Rectangle()
                .fill(OpenClawBrand.accent)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            self.title.text
                .font(OpenClawType.title3SemiBold)
                .foregroundStyle(OpenClawPalette.texteFort)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Surface

private struct ActivityTileModifier: ViewModifier {
    let tint: Color?

    func body(content: Content) -> some View {
        let shape: RoundedRectangle = RoundedRectangle(
            cornerRadius: ActivityMetric.radius,
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
    /// Opaque tile with a hairline border. An optional tint colours the border only.
    func activityTile(tint: Color? = nil) -> some View {
        modifier(ActivityTileModifier(tint: tint))
    }
}

/// One thin separator line.
struct ActivityHairline: View {
    var body: some View {
        Rectangle()
            .fill(OpenClawBrand.hairlineBorder)
            .frame(height: OpenClawProMetric.borderWidth)
            .accessibilityHidden(true)
    }
}

// MARK: - Glyph and tags

/// Square "pixel" state glyph. The symbol carries the state, the tint only reinforces it.
struct ActivityGlyph: View {
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 32
    let systemImage: String
    let tint: Color

    var body: some View {
        let shape: RoundedRectangle = RoundedRectangle(
            cornerRadius: ActivityMetric.glyphRadius,
            style: .continuous)
        let fill: Color = self.tint.opacity(0.14)
        let border: Color = self.tint.opacity(0.35)
        return Image(systemName: self.systemImage)
            .font(OpenClawType.captionSemiBold)
            .foregroundStyle(self.tint)
            .frame(width: self.side, height: self.side)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(border, lineWidth: OpenClawProMetric.borderWidth))
            .accessibilityHidden(true)
    }
}

/// Small flat status tag: symbol + text, never color alone.
struct ActivityStatusTag: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        let shape: RoundedRectangle = RoundedRectangle(
            cornerRadius: ActivityMetric.glyphRadius,
            style: .continuous)
        let fill: Color = self.tint.opacity(0.14)
        return HStack(spacing: 4) {
            Image(systemName: self.systemImage)
                .font(OpenClawType.caption2SemiBold)
                .accessibilityHidden(true)
            Text(verbatim: self.text)
                .font(OpenClawType.caption2SemiBold)
                .lineLimit(1)
        }
        .foregroundStyle(self.tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(shape.fill(fill))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Page header segmented control

struct ActivitySegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: OpenClawTextValue
    let systemImage: String

    var id: Value {
        self.value
    }
}

/// Flat two-segment selector of the page header: fondAlt track with a hairline, the selected
/// segment is an elevated rectangle with an accent liseré that slides on the shared spring.
/// At accessibility text sizes the same choice is offered as a full-width menu (44 pt tall).
struct ActivitySegmented<Value: Hashable>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var namespace
    @Binding var selection: Value
    let options: [ActivitySegmentOption<Value>]

    var body: some View {
        if self.dynamicTypeSize.isAccessibilitySize {
            self.menuPicker
        } else {
            self.track
        }
    }

    // MARK: Track

    private var track: some View {
        let shape: RoundedRectangle = RoundedRectangle(
            cornerRadius: OpenClawRadius.sm,
            style: .continuous)
        return HStack(spacing: 4) {
            ForEach(self.options) { (option: ActivitySegmentOption<Value>) in
                self.segment(option)
            }
        }
        .padding(4)
        .background(shape.fill(OpenClawPalette.fondAlt))
        .overlay(shape.strokeBorder(OpenClawBrand.hairlineBorderStrong, lineWidth: OpenClawProMetric.borderWidth))
        .sensoryFeedback(.selection, trigger: self.selection)
    }

    private func segment(_ option: ActivitySegmentOption<Value>) -> some View {
        let isSelected: Bool = option.value == self.selection
        let foreground: Color = isSelected ? OpenClawPalette.texteFort : OpenClawPalette.texteAtténué
        return Button {
            self.select(option.value)
        } label: {
            self.segmentLabel(option, foreground: foreground, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func segmentLabel(
        _ option: ActivitySegmentOption<Value>,
        foreground: Color,
        isSelected: Bool) -> some View
    {
        HStack(spacing: 6) {
            Image(systemName: option.systemImage)
                .font(OpenClawType.captionSemiBold)
                .accessibilityHidden(true)
            option.title.text
                .font(OpenClawType.subheadSemiBold)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity, minHeight: ActivityMetric.minTarget)
        .background {
            if isSelected {
                self.selectionBackground
            }
        }
        .contentShape(Rectangle())
    }

    private var selectionBackground: some View {
        let shape: RoundedRectangle = RoundedRectangle(
            cornerRadius: OpenClawRadius.xs,
            style: .continuous)
        let border: Color = OpenClawBrand.accent.opacity(0.5)
        return shape
            .fill(OpenClawBrand.surfaceElevated)
            .overlay(shape.strokeBorder(border, lineWidth: OpenClawProMetric.borderWidth))
            .matchedGeometryEffect(id: "activity.segment.selection", in: self.namespace)
    }

    private func select(_ value: Value) {
        guard value != self.selection else { return }
        OpenClawMotion.perform(reduceMotion: self.reduceMotion) {
            self.selection = value
        }
    }

    // MARK: Menu fallback

    private var menuPicker: some View {
        Picker(selection: self.$selection) {
            ForEach(self.options) { (option: ActivitySegmentOption<Value>) in
                option.title.text.tag(option.value)
            }
        } label: {
            self.selectedTitle
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, minHeight: ActivityMetric.minTarget, alignment: .leading)
    }

    private var selectedTitle: Text {
        for option in self.options where option.value == self.selection {
            return option.title.text
        }
        return Text(verbatim: "")
    }
}

// MARK: - Filters

struct ActivityChipItem: Identifiable, Equatable {
    let id: String
    let title: String
    var count: Int?
    var systemImage: String?
}

/// Flat filter chip: hairline rectangle, accent liseré when selected. 44 pt tall hit area.
struct ActivityChip: View {
    let title: String
    var systemImage: String?
    var count: Int?
    let isSelected: Bool
    var tint: Color = OpenClawBrand.accent
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            self.label
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(self.isSelected ? .isSelected : [])
    }

    private var label: some View {
        let shape: RoundedRectangle = RoundedRectangle(
            cornerRadius: ActivityMetric.controlRadius,
            style: .continuous)
        let fill: Color = self.isSelected ? self.tint.opacity(0.12) : Color.clear
        let border: Color = self.isSelected ? self.tint.opacity(0.5) : OpenClawBrand.hairlineBorderStrong
        let foreground: Color = self.isSelected ? OpenClawPalette.texteFort : OpenClawPalette.texteAtténué
        return self.content
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(border, lineWidth: OpenClawProMetric.borderWidth))
            .frame(minHeight: ActivityMetric.minTarget)
            .contentShape(Rectangle())
    }

    private var content: some View {
        HStack(spacing: 6) {
            if let systemImage = self.systemImage {
                Image(systemName: systemImage)
                    .font(OpenClawType.captionSemiBold)
                    .accessibilityHidden(true)
            }
            Text(verbatim: self.title)
                .font(OpenClawType.subheadSemiBold)
                .lineLimit(1)
            if let count = self.count {
                Text(count, format: .number)
                    .font(OpenClawType.captionSemiBold)
                    .monospacedDigit()
                    .foregroundStyle(OpenClawPalette.texteAtténué)
            }
        }
    }
}

/// ONE line of filters under the header: scrolling chips (optional failures toggle at the end)
/// and a search button at the trailing edge. Opening the search swaps the line for a search
/// field with a Cancel button, so the filters never stack with a second bar.
struct ActivityFilterRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @State private var isSearching: Bool = false
    let items: [ActivityChipItem]
    @Binding var selection: String
    var failuresOnly: Binding<Bool>?
    @Binding var search: String
    let searchPrompt: LocalizedStringKey

    var body: some View {
        Group {
            if self.isSearching {
                self.searchLine
            } else {
                self.chipLine
            }
        }
        .padding(.horizontal, OpenClawProMetric.pagePadding)
        .padding(.vertical, 4)
        .onAppear {
            if !self.search.isEmpty { self.isSearching = true }
        }
        .onChange(of: self.search) { _, newValue in
            if !newValue.isEmpty, !self.isSearching { self.isSearching = true }
        }
        .onChange(of: self.isSearching) { _, newValue in
            if newValue { self.searchFocused = true }
        }
    }

    // MARK: Chips

    private var chipLine: some View {
        HStack(spacing: OpenClawSpace.sm) {
            ScrollView(.horizontal) {
                HStack(spacing: OpenClawSpace.sm) {
                    ForEach(self.items) { (item: ActivityChipItem) in
                        self.chip(item)
                    }
                    self.failuresChip
                }
            }
            .scrollIndicators(.hidden)
            self.searchButton
        }
        .sensoryFeedback(.selection, trigger: self.selection)
    }

    private func chip(_ item: ActivityChipItem) -> some View {
        ActivityChip(
            title: item.title,
            systemImage: item.systemImage,
            count: item.count,
            isSelected: item.id == self.selection,
            action: { self.choose(item.id) })
    }

    @ViewBuilder
    private var failuresChip: some View {
        if let binding = self.failuresOnly {
            ActivityChip(
                title: String(localized: "Failed"),
                systemImage: "exclamationmark.triangle",
                count: nil,
                isSelected: binding.wrappedValue,
                tint: OpenClawBrand.danger,
                action: { self.toggleFailures(binding) })
        }
    }

    private func choose(_ id: String) {
        guard id != self.selection else { return }
        OpenClawMotion.perform(reduceMotion: self.reduceMotion) {
            self.selection = id
        }
    }

    private func toggleFailures(_ binding: Binding<Bool>) {
        OpenClawMotion.perform(reduceMotion: self.reduceMotion) {
            binding.wrappedValue.toggle()
        }
    }

    // MARK: Search

    private var searchButton: some View {
        Button {
            self.openSearch()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(OpenClawType.subheadSemiBold)
                .foregroundStyle(OpenClawPalette.texteAtténué)
                .frame(width: ActivityMetric.minTarget, height: ActivityMetric.minTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Search"))
    }

    private var searchLine: some View {
        HStack(spacing: OpenClawSpace.sm) {
            self.searchField
            Button {
                self.closeSearch()
            } label: {
                Text("Cancel")
                    .font(OpenClawType.subheadSemiBold)
                    .foregroundStyle(OpenClawBrand.accent)
                    .padding(.horizontal, 4)
                    .frame(minHeight: ActivityMetric.minTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var searchField: some View {
        let shape: RoundedRectangle = RoundedRectangle(
            cornerRadius: ActivityMetric.controlRadius,
            style: .continuous)
        return HStack(spacing: OpenClawSpace.sm) {
            Image(systemName: "magnifyingglass")
                .font(OpenClawType.captionSemiBold)
                .foregroundStyle(OpenClawPalette.texteAtténué)
                .accessibilityHidden(true)
            TextField(self.searchPrompt, text: self.$search)
                .font(OpenClawType.subhead)
                .focused(self.$searchFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: ActivityMetric.minTarget)
        .background(shape.fill(OpenClawBrand.surfaceCard))
        .overlay(shape.strokeBorder(OpenClawBrand.hairlineBorderStrong, lineWidth: OpenClawProMetric.borderWidth))
    }

    private func openSearch() {
        OpenClawMotion.perform(reduceMotion: self.reduceMotion) {
            self.isSearching = true
        }
    }

    private func closeSearch() {
        self.searchFocused = false
        OpenClawMotion.perform(reduceMotion: self.reduceMotion) {
            self.search = ""
            self.isSearching = false
        }
    }
}

// MARK: - Summary strip

struct ActivityStat: Identifiable {
    let id: String
    let value: Int
    let label: String
    var tint: Color = OpenClawPalette.texteAtténué
}

/// One opaque tile with the key figures separated by hairlines. Falls back to a vertical
/// list of rows when the figures no longer fit side by side (large Dynamic Type).
struct ActivitySummaryStrip: View {
    let stats: [ActivityStat]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            self.horizontal
            self.vertical
        }
        .activityTile()
    }

    private var horizontal: some View {
        HStack(spacing: 0) {
            ForEach(self.stats) { (stat: ActivityStat) in
                self.cell(stat)
            }
        }
    }

    private func cell(_ stat: ActivityStat) -> some View {
        let isFirst: Bool = stat.id == self.stats.first?.id
        return VStack(spacing: 2) {
            Text(stat.value, format: .number)
                .font(OpenClawType.title3SemiBold)
                .foregroundStyle(OpenClawPalette.texteFort)
                .monospacedDigit()
            HStack(spacing: 4) {
                self.marker(stat.tint)
                Text(verbatim: stat.label)
                    .font(OpenClawType.caption)
                    .foregroundStyle(OpenClawPalette.texteAtténué)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .overlay(alignment: .leading) {
            if !isFirst {
                Rectangle()
                    .fill(OpenClawBrand.hairlineBorder)
                    .frame(width: OpenClawProMetric.borderWidth)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var vertical: some View {
        VStack(spacing: 0) {
            ForEach(self.stats) { (stat: ActivityStat) in
                self.verticalRow(stat)
            }
        }
    }

    private func verticalRow(_ stat: ActivityStat) -> some View {
        let isFirst: Bool = stat.id == self.stats.first?.id
        return HStack(spacing: 8) {
            self.marker(stat.tint)
            Text(verbatim: stat.label)
                .font(OpenClawType.subhead)
                .foregroundStyle(OpenClawPalette.texteAtténué)
            Spacer(minLength: 8)
            Text(stat.value, format: .number)
                .font(OpenClawType.subheadSemiBold)
                .foregroundStyle(OpenClawPalette.texteFort)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: ActivityMetric.minTarget)
        .overlay(alignment: .top) {
            if !isFirst { ActivityHairline() }
        }
        .accessibilityElement(children: .combine)
    }

    private func marker(_ tint: Color) -> some View {
        Rectangle()
            .fill(tint)
            .frame(width: 5, height: 5)
            .accessibilityHidden(true)
    }
}

// MARK: - Disclosure row

/// Tile-shaped row that expands the charts. 44 pt tall.
struct ActivityDisclosureRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            self.isExpanded.toggle()
        } label: {
            self.label
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(self.stateKey))
        .sensoryFeedback(.selection, trigger: self.isExpanded)
    }

    private var stateKey: LocalizedStringKey {
        self.isExpanded ? "Expanded" : "Collapsed"
    }

    private var label: some View {
        let angle: Double = self.isExpanded ? 180 : 0
        return HStack(spacing: 8) {
            Image(systemName: self.systemImage)
                .font(OpenClawType.captionSemiBold)
                .foregroundStyle(OpenClawBrand.accent)
                .accessibilityHidden(true)
            Text(self.title)
                .font(OpenClawType.subheadSemiBold)
                .foregroundStyle(OpenClawPalette.texteFort)
            Spacer(minLength: 8)
            Image(systemName: "chevron.down")
                .font(OpenClawType.captionSemiBold)
                .foregroundStyle(OpenClawPalette.texteAtténué)
                .rotationEffect(.degrees(angle))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: ActivityMetric.minTarget, alignment: .leading)
        .activityTile()
        .contentShape(Rectangle())
        .openClawAnimation(value: self.isExpanded)
    }
}

// MARK: - Section header

/// Header of a list section (a day, or Active / Paused): pixel marker, label, count. Pinned on the page background.
struct ActivitySectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(OpenClawBrand.accent)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(verbatim: self.title)
                .font(OpenClawType.captionSemiBold)
                .foregroundStyle(OpenClawPalette.texteAtténué)
            Spacer(minLength: 8)
            Text(self.count, format: .number)
                .font(OpenClawType.caption)
                .foregroundStyle(OpenClawPalette.texteAtténué)
                .monospacedDigit()
        }
        .textCase(nil)
        .ngStickyHeader()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Button styles

/// Row press feedback: a quiet hover-coloured wash, no scale (rows span the full width).
struct ActivityRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let isPressed: Bool = configuration.isPressed
        let fill: Color = isPressed ? OpenClawPalette.survol : Color.clear
        let shape: RoundedRectangle = RoundedRectangle(
            cornerRadius: ActivityMetric.glyphRadius,
            style: .continuous)
        return configuration.label
            .background(shape.fill(fill).padding(.horizontal, -8))
    }
}

/// Flat action button of the states (Retry, Check again, Clear filters). 44 pt minimum.
struct ActivityActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        let shape: RoundedRectangle = RoundedRectangle(
            cornerRadius: ActivityMetric.controlRadius,
            style: .continuous)
        let fill: Color = self.prominent ? OpenClawBrand.accentFill : Color.clear
        let foreground: Color = self.prominent ? Color.white : OpenClawPalette.texteFort
        let dim: Double = configuration.isPressed ? OpenClawOpacity.pressed : 1
        let enabledOpacity: Double = self.isEnabled ? dim : OpenClawOpacity.disabled
        return configuration.label
            .font(OpenClawType.subheadSemiBold)
            .foregroundStyle(foreground)
            .padding(.horizontal, OpenClawSpace.lg)
            .frame(minHeight: ActivityMetric.minTarget)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(OpenClawBrand.hairlineBorderStrong, lineWidth: OpenClawProMetric.borderWidth))
            .contentShape(Rectangle())
            .opacity(enabledOpacity)
    }
}

// MARK: - States

/// Scrollable host of a placeholder state, so pull-to-refresh also works on empty and error states.
struct ActivityPlaceholder<Content: View>: View {
    let refresh: () async -> Void
    private let content: Content

    init(refresh: @escaping () async -> Void, @ViewBuilder content: () -> Content) {
        self.refresh = refresh
        self.content = content()
    }

    var body: some View {
        ScrollView {
            self.content
                .padding(.top, OpenClawSpace.xxl)
                .frame(maxWidth: .infinity)
        }
        .refreshable { await self.refresh() }
    }
}

/// Loading placeholder shaped like the rows it announces. Calm pulse, static under Reduce Motion.
struct ActivitySkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse: Bool = false
    var rows: Int = 8

    var body: some View {
        let opacity: Double = self.pulse ? 0.45 : 1
        return VStack(spacing: 0) {
            ForEach(0..<self.rows, id: \.self) { (_: Int) in
                self.skeletonRow
            }
        }
        .padding(.horizontal, OpenClawProMetric.pagePadding)
        .padding(.top, OpenClawSpace.sm)
        .opacity(opacity)
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

    private var skeletonRow: some View {
        let glyph: RoundedRectangle = RoundedRectangle(
            cornerRadius: ActivityMetric.glyphRadius,
            style: .continuous)
        let bar: RoundedRectangle = RoundedRectangle(cornerRadius: 3, style: .continuous)
        return HStack(spacing: OpenClawSpace.md) {
            glyph
                .fill(OpenClawPalette.survol)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 6) {
                bar.fill(OpenClawPalette.survol).frame(width: 170, height: 12)
                bar.fill(OpenClawPalette.survol).frame(width: 110, height: 10)
            }
            Spacer(minLength: 0)
            bar.fill(OpenClawPalette.survol).frame(width: 36, height: 10)
        }
        .padding(.vertical, 10)
        .frame(minHeight: ActivityMetric.minTarget)
        .overlay(alignment: .bottom) { ActivityHairline() }
    }
}
