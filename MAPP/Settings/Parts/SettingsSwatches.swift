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

    var body: some View {
        HStack(spacing: SettingsTokens.Metric.swatchSpacing) {
            ForEach(swatches) { swatch in
                Button { selection = swatch.value } label: {
                    Circle()
                        .fill(swatch.color)
                        .frame(width: SettingsTokens.Metric.swatch, height: SettingsTokens.Metric.swatch)
                        .overlay {
                            if selection == swatch.value && custom?.isSelected != true {
                                Circle().fill(.white).frame(width: SettingsTokens.Metric.swatchDot, height: SettingsTokens.Metric.swatchDot)
                            }
                        }
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help(swatch.title)
                .accessibilityLabel(swatch.title)
                .accessibilityAddTraits(selection == swatch.value && custom?.isSelected != true ? .isSelected : [])
            }
            if let custom {
                Rectangle().fill(SettingsTokens.rule).frame(width: 1, height: SettingsTokens.Metric.swatch)
                ColorPicker("Custom Color", selection: custom.color, supportsOpacity: false)
                    .labelsHidden()
                    .accessibilityLabel("Custom Color")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }
}

/// The small window a theme's tile draws: a sidebar and lines of text, in the light or the dark look.
struct SettingsThemePicture: View {
    enum Look { case light, dark }

    let look: Look

    var body: some View {
        GeometryReader { space in
            HStack(spacing: 0) {
                Rectangle().fill(look == .light ? SettingsTokens.ThemePreview.lightSidebar : SettingsTokens.ThemePreview.darkSidebar)
                    .frame(width: space.size.width * SettingsTokens.Metric.previewSidebar)
                VStack(alignment: .leading, spacing: SettingsTokens.Metric.previewLineSpacing) {
                    line(widthShare: 0.4, heading: true)
                    ForEach(0..<4, id: \.self) { _ in line(widthShare: 1, heading: false) }
                    Spacer(minLength: 0)
                }
                .padding(SettingsTokens.Metric.previewLineSpacing * 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(look == .light ? SettingsTokens.ThemePreview.lightPage : SettingsTokens.ThemePreview.darkPage)
            }
        }
    }

    private func line(widthShare: CGFloat, heading: Bool) -> some View {
        let color: Color = switch (look, heading) {
        case (.light, true): SettingsTokens.ThemePreview.lightHeading
        case (.light, false): SettingsTokens.ThemePreview.lightLine
        case (.dark, true): SettingsTokens.ThemePreview.darkHeading
        case (.dark, false): SettingsTokens.ThemePreview.darkLine
        }
        return GeometryReader { space in
            Capsule().fill(color).frame(width: space.size.width * widthShare, height: SettingsTokens.Metric.previewLine)
        }
        .frame(height: SettingsTokens.Metric.previewLine)
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
            path.move(to: CGPoint(x: rect.maxX * 0.62, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX * 0.38, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}
