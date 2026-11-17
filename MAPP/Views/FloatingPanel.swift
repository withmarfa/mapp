import SwiftUI

/// A panel the window shows over everything, as the command palette, the search palette and quick add are: one
/// shape, material, edge and shadow, and a click anywhere outside puts it away, as it does a menu. Every panel
/// starts at the same height, its top about an eighth of the way down the window and centred over it, so what
/// grows grows downward.
struct FloatingPanel<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { window in
            ZStack(alignment: .top) {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture(perform: onDismiss)
                    // Claims the pointer, so a view beneath the panel is told when it leaves it.
                    .onContinuousHover { _ in }
                content
                    .padding(.top, window.size.height * FloatingPanelMetrics.topFraction)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
    }
}

extension View {
    /// The surface a floating panel's content sits on, `width` wide and as tall as the content: the regular Liquid
    /// Glass the system gives popovers and other floating controls that hold text, with its own edge, and a
    /// shadow that lifts it off the window.
    func floatingPanelSurface(width: CGFloat) -> some View {
        frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .modifier(FloatingPanelSurface())
    }
}

enum FloatingPanelMetrics {
    static let cornerRadius: CGFloat = 20
    /// How far down the window a panel's top sits, as a fraction of its height.
    static let topFraction: CGFloat = 0.12
}

private struct FloatingPanelSurface: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: FloatingPanelMetrics.cornerRadius, style: .continuous)

    func body(content: Content) -> some View {
        #if DEBUG
        tuned(content, Tuning.shared.choice(Tuning.paletteMaterial, as: FloatingPanelMaterial.self) ?? .glass)
        #else
        content
            .glassEffect(.regular, in: shape)
            .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
        #endif
    }

    #if DEBUG
    /// The surface for a material the Tuning panel chose. Each keeps the panel's shape; the edge and the shadow
    /// follow the material, since a material without glass has no edge of its own.
    @ViewBuilder
    private func tuned(_ content: Content, _ material: FloatingPanelMaterial) -> some View {
        switch material {
        case .glass:
            content
                .glassEffect(.regular, in: shape)
                .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
        case .clearGlass:
            // Clear glass needs a dimming layer to keep text legible over a bright page, and light text over it.
            content
                .glassEffect(.clear, in: shape)
                .background(.black.opacity(0.35), in: shape)
                .environment(\.colorScheme, .dark)
                .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
        case .thickMaterial:
            content
                .background(.thickMaterial, in: shape)
                .overlay { edge(.primary.opacity(0.12)) }
                .shadow(color: .black.opacity(0.2), radius: 30, y: 12)
        case .popover:
            content
                .background { VisualEffectBackground(material: .popover, cornerRadius: FloatingPanelMetrics.cornerRadius) }
                .overlay { edge(.primary.opacity(0.12)) }
                .shadow(color: .black.opacity(0.2), radius: 30, y: 12)
        case .hud:
            content
                .background {
                    VisualEffectBackground(material: .hudWindow, cornerRadius: FloatingPanelMetrics.cornerRadius, appearance: .vibrantDark)
                }
                .overlay { edge(.white.opacity(0.14)) }
                .environment(\.colorScheme, .dark)
                .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
        case .opaque:
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay { edge(.primary.opacity(0.1)) }
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                .shadow(color: .black.opacity(0.3), radius: 40, y: 20)
        }
    }

    private func edge(_ color: Color) -> some View {
        shape.strokeBorder(color, lineWidth: 1).allowsHitTesting(false)
    }
    #endif
}

#if DEBUG
/// The materials the Tuning panel offers for the floating panels, named as the panel lists them.
enum FloatingPanelMaterial: String, CaseIterable {
    case glass = "Liquid Glass, regular (ships now)"
    case clearGlass = "Liquid Glass, clear and dimmed"
    case thickMaterial = "Thick material"
    case popover = "Popover material"
    case hud = "HUD material (always dark)"
    case opaque = "Opaque window background"
}

/// An AppKit material behind the panel, blending with the window beneath it, rounded to the panel's corners by a
/// mask, which is how `NSVisualEffectView` takes a shape.
private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let cornerRadius: CGFloat
    var appearance: NSAppearance.Name?

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.appearance = appearance.flatMap(NSAppearance.init(named:))
        view.maskImage = Self.mask(cornerRadius)
    }

    private static func mask(_ radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
#endif
