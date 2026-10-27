import SwiftUI

/// A soft band of glass behind the toolbar, for a page that scrolls under it. The window hides its toolbar's
/// background (`MAPPApp`), and the page's web view is not a SwiftUI scroll view, so the app does not rely on the
/// system drawing a soft edge over the page. This band is the app's own signal that content is under the toolbar:
/// it is absent while nothing is behind the toolbar, and fades in once something is. If the system's edge is ever
/// seen to draw over the page as well, this band is the thing to remove.
struct ToolbarBand: View {
    /// The toolbar's height, which the band covers entirely.
    let toolbarHeight: CGFloat
    let isShown: Bool

    /// How far the band's lower edge fades out below the toolbar, so it ends softly rather than in a line.
    static let fade: CGFloat = 14

    /// How much of the material shows over the toolbar's height, so the page reads through it.
    static let strength: Double = 0.6

    static let material: Material = .bar

    /// The values the band draws with: the constants above, which a Debug build lets the tuning panel replace.
    private var look: (strength: Double, fade: CGFloat, material: Material) {
        #if DEBUG
        let tuning = Tuning.shared
        return (tuning.number(Knobs.strength), CGFloat(tuning.number(Knobs.fade)),
                tuning.choice(Knobs.material, as: BandMaterial.self)?.material ?? Self.material)
        #else
        return (Self.strength, Self.fade, Self.material)
        #endif
    }

    var body: some View {
        let look = look
        Rectangle()
            .fill(look.material)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(look.strength), location: 0),
                        .init(color: .black.opacity(look.strength), location: toolbarHeight / (toolbarHeight + look.fade)),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(height: toolbarHeight + look.fade)
            // With no toolbar over the page, as in full screen while the toolbar is hidden, there is nothing to back.
            .opacity(isShown && toolbarHeight > 0 ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: isShown)
            // Clicks, the window's drag area and the toolbar's buttons all work as if it were not there.
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .ignoresSafeArea(.container, edges: .top)
    }
}

#if DEBUG
extension ToolbarBand {
    /// The band's tuning knobs, defaulting to the constants above. Delete them once the look is settled.
    enum Knobs {
        static let strength = Knob.slider("toolbarBand", "strength", ToolbarBand.strength, in: 0...1, step: 0.05)
        static let fade = Knob.slider("toolbarBand", "fade", Double(ToolbarBand.fade), in: 0...40, step: 1)
        static let material = Knob.picker("toolbarBand", "material", BandMaterial.bar)
    }

    enum BandMaterial: String, CaseIterable {
        case ultraThin, thin, regular, thick, ultraThick, bar

        var material: Material {
            switch self {
            case .ultraThin: .ultraThinMaterial
            case .thin: .thinMaterial
            case .regular: .regularMaterial
            case .thick: .thickMaterial
            case .ultraThick: .ultraThickMaterial
            case .bar: .bar
            }
        }
    }
}
#endif
