import SwiftUI

/// The starting density, scope, sort and grouping for lists.
struct ListsPage: View {
    @AppStorage(ListKey.density) private var density = Density.standard
    @AppStorage private var storedScope: ListScope
    @AppStorage(OrderKey.sort) private var sort = ItemOrder().sort
    @AppStorage(OrderKey.groupsByDate) private var groupsByDate = ItemOrder().groupsByDate

    init(defaults: UserDefaults? = nil) {
        _storedScope = AppStorage(wrappedValue: .all, ListScope.defaultScopeKey, store: defaults)
    }

    var scope: Binding<ListScope> {
        Binding { storedScope == .library ? .library : .all } set: { storedScope = $0 }
    }

    var body: some View {
        SettingsPageColumn {
            SettingsSection("Density") {
                DensityChoices(selection: $density)
                    .accessibilityIdentifier("ListsDensity")
            }
            SettingsSection("Defaults", footer: "A view or a place can set its own.") {
                SettingsRow("From", line: "What a type, a collection or a new view lists.", lines: nil) {
                    SettingsPopUp(title: "From", selection: scope) {
                        Text("All Items").tag(ListScope.all)
                        Text("Library").tag(ListScope.library)
                    }
                    .accessibilityIdentifier("ListScope")
                }
                SettingsRow("Sort by") {
                    SettingsPopUp(title: "Sort by", selection: $sort) {
                        ForEach(ItemSort.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("ItemSort")
                }
                SettingsRow("Group by", look: sort == .title ? .off : .normal) {
                    SettingsPopUp(title: "Group by", selection: $groupsByDate) {
                        Text("None").tag(false)
                        Text("Date").tag(true)
                    }
                    .accessibilityIdentifier("GroupBy")
                }
            }
        }
        .accessibilityIdentifier("ListsPage")
    }
}

private struct DensityChoices: View {
    @Binding var selection: Density
    private typealias Metric = SettingsTokens.Metric

    var body: some View {
        HStack(alignment: .top, spacing: Metric.densityTileGap) {
            ForEach(Density.allCases, id: \.self) { density in
                let isSelected = selection == density
                Button { selection = density } label: {
                    VStack(spacing: Metric.densityTitleGap) {
                        picture(density, isSelected: isSelected)
                        Text(verbatim: density.title)
                            .settingsFont(.small)
                            .fontWeight(isSelected ? .semibold : .regular)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding([.top, .horizontal], Metric.inset)
        .padding(.bottom, Metric.densityBottomInset)
    }

    private func picture(_ density: Density, isSelected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metric.densityTileRadius)
        return Color.clear
            .aspectRatio(Metric.densityPictureWidth / Metric.densityPictureHeight, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { DensityPicture(density: density).accessibilityHidden(true) }
            .clipShape(shape)
            .overlay { shape.strokeBorder(SettingsTokens.hairline, lineWidth: Metric.tileEdgeWidth) }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Metric.densityTileRadius + Metric.densityRingOutset)
                        .strokeBorder(SettingsTokens.primaryText.opacity(SettingsTokens.densityRingOpacity), lineWidth: Metric.densityRingWidth)
                        .padding(-Metric.densityRingOutset)
                }
            }
    }
}

/// The sample list content laid out in miniature.
private struct DensityPicture: View {
    let density: Density
    private typealias Metric = SettingsTokens.Metric

    private static let note = "lucide:sticky-note"
    private static let task = "lucide:square-check-big"
    private static let bookmark = "lucide:bookmark"

    private var samples: [RowContent] {
        [
            row(Self.note, String(localized: "Note"), String(localized: "Kiln log, firing 14"),
                String(localized: "Bisque, 1000°C, nine hours. Two test tiles cracked on the lower shelf, both from the new clay."), String(localized: "Saturday")),
            row(
                Self.task, String(localized: "Task"), String(localized: "Reply to Ines about the zine proofs"),
                String(localized: "Pages 6 and 7 are the wrong way round in the second proofs."), String(localized: "Thursday"),
                status: String(localized: "Not Started")),
            row(Self.note, String(localized: "Note"), String(localized: "Lewes Trust: comments on the draft"), nil, String(localized: "Tuesday")),
            row("lucide:user", String(localized: "Person"), String(localized: "Ines Barros"), nil, String(localized: "16 Nov")),
            row(Self.task, String(localized: "Task"), String(localized: "Keep the gallery grid aligned when the window resizes"), nil, String(localized: "12 Nov")),
            row(Self.bookmark, String(localized: "Bookmark"), String(localized: "Paper for the zine"), nil, String(localized: "8 Nov")),
        ]
    }

    private func row(_ icon: String, _ type: String, _ title: String, _ line: String?, _ date: String, status: String? = nil) -> RowContent {
        var content = RowContent(title: title, date: date, secondary: line, typeIcon: icon, typeLabel: type, mixesTypes: true)
        content.chips = status.map { [.status(.notStarted, label: $0)] } ?? []
        return content
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / Metric.densityPictureWidth * Metric.densityRowScale
            rows
                .frame(width: Metric.densityPictureWidth / Metric.densityRowScale)
                .scaleEffect(scale, anchor: .topLeading)
        }
        .background(SettingsTokens.card)
        .allowsHitTesting(false)
    }

    private var rows: some View {
        let isCompact = density == .compact
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(samples.prefix(isCompact ? 6 : 3).enumerated()), id: \.offset) { index, content in
                previewRow(content, showsPicture: !isCompact && index == 0)
                    .frame(height: isCompact ? Metric.densityCompactRowHeight : nil)
                    .overlay(alignment: .top) {
                        if index > 0 {
                            Rectangle()
                                .fill(SettingsTokens.rule)
                                .frame(height: Metric.ruleThickness)
                        }
                    }
            }
        }
        .padding(.horizontal, Metric.densityPreviewInset)
    }

    private func previewRow(_ content: RowContent, showsPicture: Bool) -> some View {
        VStack(alignment: .leading, spacing: Metric.densityLineGap) {
            HStack(spacing: Metric.buttonGap) {
                TonedGlyph(id: content.typeIcon, size: Metric.densityTypeMark)
                Text(verbatim: content.title)
                    .fontWeight(density == .standard ? .semibold : .regular)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let date = content.date {
                    Text(verbatim: date)
                        .font(SettingsTokens.font(.line))
                        .foregroundStyle(SettingsTokens.secondaryText)
                        .fixedSize()
                }
            }
            if density == .standard, let preview = content.secondary {
                Text(verbatim: preview)
                    .font(SettingsTokens.font(.line))
                    .foregroundStyle(SettingsTokens.secondaryText)
                    .lineLimit(2)
                    .padding(.trailing, showsPicture ? Metric.densitySamplePictureClearance : 0)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if density == .standard, !content.chips.isEmpty {
                ChipLine(content: content, statusItem: nil, typeFont: InterfaceStyle.captionFont)
            }
        }
        .font(SettingsTokens.font(.title))
        .padding(.vertical, density == .standard ? Metric.densityStandardRowPadding : 0)
        .padding(.horizontal, Metric.densityRowInset)
        .overlay(alignment: .topTrailing) {
            if showsPicture {
                RowPictureFrame { SamplePicture() }
                    .padding(.top, Metric.densitySamplePictureTop)
                    .padding(.trailing, Metric.densityRowInset)
            }
        }
    }
}

private extension SettingsTokens {
    static let densityRingOpacity = 0.40
}

private extension SettingsTokens.Metric {
    static let densityPictureWidth: CGFloat = 287
    static let densityPictureHeight: CGFloat = 172
    static let densityTileGap: CGFloat = 14
    static let densityTitleGap: CGFloat = 7
    static let densityBottomInset: CGFloat = 12
    static let densityTileRadius: CGFloat = 8
    static let densityRingOutset: CGFloat = 4.5
    static let densityRingWidth: CGFloat = 2.5
    static let densityRowScale: CGFloat = 0.8
    static let densityPreviewInset: CGFloat = 4
    static let densityRowInset: CGFloat = 10
    static let densityTypeMark: CGFloat = 16
    static let densityLineGap: CGFloat = 2
    static let densityStandardRowPadding: CGFloat = 10
    static let densityCompactRowHeight: CGFloat = 28 / densityRowScale
    static let densitySamplePictureClearance: CGFloat = 52
    static let densitySamplePictureTop: CGFloat = 31
}
