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
                customSwatch(custom)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }
}

extension SettingsSwatches {
    /// The color of the person's own: a rainbow until they have made one, then that color with the chosen dot. The system's
    /// color panel opens from it, through a color well laid over it that draws nothing of its own.
    @ViewBuilder fileprivate func customSwatch(_ custom: (isSelected: Bool, color: Binding<Color>)) -> some View {
        Circle()
            .fill(custom.isSelected ? AnyShapeStyle(custom.color.wrappedValue) : AnyShapeStyle(SettingsTokens.rainbow))
            .frame(width: SettingsTokens.Metric.swatch, height: SettingsTokens.Metric.swatch)
            .overlay {
                if custom.isSelected {
                    Circle().fill(.white).frame(width: SettingsTokens.Metric.swatchDot, height: SettingsTokens.Metric.swatchDot)
                }
            }
            .overlay {
                ColorPicker("Custom Color", selection: custom.color, supportsOpacity: false)
                    .labelsHidden()
                    .opacity(SettingsTokens.Metric.invisibleWell)
                    .frame(width: SettingsTokens.Metric.swatch, height: SettingsTokens.Metric.swatch)
                    .clipShape(.circle)
            }
            .help("Custom Color")
    }
}

/// The small window a theme's tile draws: a sidebar of short bars and a page of lines, in the light or the dark look.
struct SettingsThemePicture: View {
    enum Look { case light, dark }

    let look: Look

    private typealias Metric = SettingsTokens.Metric
    private typealias Preview = SettingsTokens.ThemePreview

    var body: some View {
        GeometryReader { space in
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Metric.previewLineSpacing) {
                    ForEach(0..<Metric.previewSidebarLines, id: \.self) { _ in
                        bar(look == .light ? Preview.lightSidebarLine : Preview.darkSidebarLine, widthShare: 1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Metric.previewSidebarPadding)
                .padding(.top, Metric.previewTop)
                .frame(width: space.size.width * Metric.previewSidebar)
                .frame(maxHeight: .infinity)
                .background(look == .light ? Preview.lightSidebar : Preview.darkSidebar)
                VStack(alignment: .leading, spacing: Metric.previewLineSpacing) {
                    bar(look == .light ? Preview.lightLine : Preview.darkLine, widthShare: Metric.previewHeading)
                    ForEach(0..<4, id: \.self) { _ in bar(look == .light ? Preview.lightLine : Preview.darkLine, widthShare: 1) }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Metric.previewPadding)
                .padding(.top, Metric.previewTop)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(look == .light ? Preview.lightPage : Preview.darkPage)
            }
        }
    }

    private func bar(_ color: Color, widthShare: CGFloat) -> some View {
        GeometryReader { space in
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
            path.move(to: CGPoint(x: rect.maxX * 0.56, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX * 0.46, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}
