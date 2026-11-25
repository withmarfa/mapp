import SwiftUI

/// A panel the window shows over everything, as the command palette, the search palette and the new item are: one
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
    /// The surface a floating panel's content sits on, `width` wide and as tall as the content, in the material the
    /// person chose in Settings (`PaletteMaterial`), with its own edge and a shadow that lifts it off the window.
    func floatingPanelSurface(width: CGFloat, cornerRadius: CGFloat = FloatingPanelMetrics.cornerRadius) -> some View {
        frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .modifier(FloatingPanelSurface(cornerRadius: cornerRadius, isNested: false))
    }

    /// The same surface for a panel inside a floating panel, as Actions is in the palette: its own corners, and a
    /// shadow small enough to lift it off the rows under it.
    func nestedPanelSurface(cornerRadius: CGFloat) -> some View {
        modifier(FloatingPanelSurface(cornerRadius: cornerRadius, isNested: true))
    }
}

enum FloatingPanelMetrics {
    static let cornerRadius: CGFloat = 20
    /// How far down the window a panel's top sits, as a fraction of its height.
    static let topFraction: CGFloat = 0.12
}

private struct FloatingPanelSurface: ViewModifier {
    let cornerRadius: CGFloat
    let isNested: Bool
    @AppStorage(InterfaceKey.paletteMaterial) private var material = PaletteMaterial.standard

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) }

    /// Glass draws its own edge; the other materials take a hairline so the panel keeps its shape over a page.
    func body(content: Content) -> some View {
        switch material {
        case .glass:
            content
                .glassEffect(.regular, in: shape)
                .modifier(Lift(opacity: 0.18, isNested: isNested))
        case .translucent:
            content
                .background { VisualEffectBackground(material: .popover, cornerRadius: cornerRadius) }
                .overlay { edge }
                .modifier(Lift(opacity: 0.2, isNested: isNested))
        case .solid:
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay { edge }
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                .modifier(Lift(opacity: 0.3, isNested: isNested))
        }
    }

    private var edge: some View {
        shape.strokeBorder(.primary.opacity(0.1), lineWidth: 1).allowsHitTesting(false)
    }
}

/// The shadow that lifts a panel off the window, or a nested panel off the rows under it.
private struct Lift: ViewModifier {
    let opacity: Double
    let isNested: Bool

    func body(content: Content) -> some View {
        if isNested {
            content.shadow(color: .black.opacity(opacity * 0.7), radius: 12, y: 4)
        } else {
            content.shadow(color: .black.opacity(opacity), radius: 30, y: 12)
        }
    }
}

/// An AppKit material behind the panel, blending with the window beneath it, rounded to the panel's corners by a
/// mask, which is how `NSVisualEffectView` takes a shape.
private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
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
