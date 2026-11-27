import SwiftUI

/// A row of colors to choose from, then a color of the person's own at the end, made with the system's color panel. The
/// chosen swatch has a white dot, and the focus is a gray ring, never the accent.
struct SettingsSwatches<Value: Hashable>: View {
    struct Swatch: Identifiable {
        let value: Value
        let color: Color
        let title: Text
        var id: Value { value }
    }

    let swatches: [Swatch]
    @Binding var selection: Value
    /// The color of the person's own: whether it is the choice, and the color made.
    var custom: (isSelected: Bool, color: Binding<Color>)?
    let title: LocalizedStringKey

    private typealias Metric = SettingsTokens.Metric

    var body: some View {
        HStack(spacing: Metric.swatchSpacing) {
            ForEach(swatches) { swatch in
                let isSelected = selection == swatch.value && custom?.isSelected != true
                Button { selection = swatch.value } label: {
                    dot(swatch.color, isSelected: isSelected).contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help(swatch.title)
                .accessibilityLabel(swatch.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            if let custom {
                Rectangle().fill(SettingsTokens.rule)
                    .frame(width: Metric.swatchDividerWidth, height: Metric.swatchDividerHeight)
                    .padding(.horizontal, Metric.swatchDividerInset)
                customSwatch(custom)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }

    private func dot(_ fill: some ShapeStyle, isSelected: Bool) -> some View {
        Circle().fill(fill)
            .frame(width: Metric.swatch, height: Metric.swatch)
            .overlay { Circle().strokeBorder(SettingsTokens.swatchEdge, lineWidth: Metric.swatchEdgeWidth) }
            .overlay {
                if isSelected {
                    Circle().fill(SettingsTokens.swatchDot).frame(width: Metric.swatchDot, height: Metric.swatchDot)
                }
            }
    }

    /// The color of the person's own: a rainbow until they have made one, then that color with the chosen dot. The system's
    /// color panel opens from it, through a color well laid over it that draws nothing of its own.
    @ViewBuilder fileprivate func customSwatch(_ custom: (isSelected: Bool, color: Binding<Color>)) -> some View {
        dot(custom.isSelected ? AnyShapeStyle(custom.color.wrappedValue) : AnyShapeStyle(SettingsTokens.rainbow), isSelected: custom.isSelected)
            .overlay {
                ColorPicker("Custom Color", selection: custom.color, supportsOpacity: false)
                    .labelsHidden()
                    .opacity(Metric.invisibleWell)
                    .frame(width: Metric.swatch, height: Metric.swatch)
                    .clipShape(.circle)
            }
            .help("Custom Color")
    }
}

/// A miniature Marfa window in the light or dark appearance.
struct SettingsThemePicture: View {
    enum Look { case light, dark }

    let look: Look

    private typealias Preview = SettingsTokens.ThemePreview

    private var palette: Preview.Palette { look == .light ? Preview.light : Preview.dark }

    var body: some View {
        GeometryReader { space in
            let scale = min(Preview.scale, space.size.width / Preview.referenceWidth)
            let width = max(Preview.referenceWidth, space.size.width / Preview.scale)
            HStack(spacing: 0) {
                sidebar
                list
            }
            .frame(width: width, height: width / SettingsTokens.Metric.choiceAspect)
            .scaleEffect(scale, anchor: .topLeading)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Preview.sidebarRowGap) {
            sidebarRow("Library", symbol: "square.grid.2x2", ink: palette.secondary, isSelected: true)
            sidebarRow("Feed", symbol: "tray", ink: palette.secondary)
            sidebarRow("Note", symbol: "note.text", ink: Preview.note)
                .padding(.top, Preview.sidebarGroupGap)
            sidebarRow("Task", symbol: "checkmark.square", ink: Preview.task)
            sidebarRow("Events", symbol: "calendar", ink: Preview.event)
        }
        .padding(.horizontal, Preview.panelInset)
        .padding(.top, Preview.sidebarTop)
        .frame(width: Preview.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(palette.sidebar)
        .overlay(alignment: .topLeading) {
            HStack(spacing: Preview.trafficGap) {
                ForEach(Preview.trafficLights.indices, id: \.self) { index in
                    Circle().fill(Preview.trafficLights[index])
                        .overlay { Circle().strokeBorder(Preview.trafficEdge, lineWidth: SettingsTokens.Metric.choiceEdgeWidth) }
                        .frame(width: Preview.trafficSize, height: Preview.trafficSize)
                }
            }
            .padding(Preview.trafficInset)
        }
    }

    private func sidebarRow(_ title: LocalizedStringKey, symbol: String, ink: Color, isSelected: Bool = false) -> some View {
        HStack(spacing: Preview.sidebarLabelGap) {
            glyph(symbol, ink: ink, size: Preview.sidebarGlyph)
            Text(title).font(Preview.sidebarFont).foregroundStyle(palette.text).lineLimit(1)
        }
        .padding(.horizontal, Preview.panelInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Preview.sidebarRowHeight)
        .background(isSelected ? palette.sidebarSelection : .clear, in: .rect(cornerRadius: Preview.sidebarRadius))
    }

    private var list: some View {
        VStack(spacing: 0) {
            item(
                "Kiln log, firing 14", symbol: "note.text", ink: Preview.note, date: "Saturday",
                line: "Bisque, 1000°C, nine hours. Two test tiles cracked on the lower shelf, both from the new clay.")
                .background(palette.listSelection, in: .rect(cornerRadius: Preview.listRadius))
            item(
                "Reply to Ines about the zine proofs", symbol: "checkmark.square", ink: Preview.task, date: "Thursday",
                line: "Pages 6 and 7 are the wrong way round in the second proofs.")
            item("Lewes Trust: comments on the draft", symbol: "note.text", ink: Preview.note, date: "Tuesday")
                .overlay(alignment: .top) {
                    Rectangle().fill(palette.rule).frame(height: SettingsTokens.Metric.ruleThickness)
                        .padding(.horizontal, Preview.listRowInset)
                }
        }
        .padding(.horizontal, Preview.panelInset)
        .padding(.top, Preview.listTop)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.page)
    }

    private func item(_ title: LocalizedStringKey, symbol: String, ink: Color, date: LocalizedStringKey, line: LocalizedStringKey? = nil) -> some View {
        VStack(alignment: .leading, spacing: Preview.listLineGap) {
            HStack(spacing: Preview.listTitleGap) {
                glyph(symbol, ink: ink, size: Preview.listGlyph)
                Text(title).font(Preview.titleFont).foregroundStyle(palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(date).font(Preview.detailFont).foregroundStyle(palette.tertiary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            if let line {
                Text(line).font(Preview.detailFont).foregroundStyle(palette.secondary)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, Preview.listRowInset)
        .padding(.top, Preview.listRowInset)
        .frame(height: Preview.listRowHeight, alignment: .topLeading)
    }

    private func glyph(_ symbol: String, ink: Color, size: CGFloat) -> some View {
        Image(systemName: symbol).resizable().scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(ink)
    }
}

/// The system theme's tile: the light look and the dark look, split by a diagonal.
struct SettingsSystemThemePicture: View {
    var body: some View {
        ZStack {
            SettingsThemePicture(look: .light)
            SettingsThemePicture(look: .dark).mask(DiagonalHalf())
        }
    }

    private struct DiagonalHalf: Shape {
        nonisolated func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.maxX * SettingsTokens.ThemePreview.splitTop, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX * SettingsTokens.ThemePreview.splitBottom, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}
