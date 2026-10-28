import SwiftUI

/// A band of blurred material over the toolbar, ended by a hairline, for content that scrolls under it, in the
/// manner of the system's hard scroll edge effect. The window hides its toolbar's background (`MAPPApp`), the
/// page's web view is not a SwiftUI scroll view, and WebKit's own scroll edge is not public API, so the app draws
/// the band itself: it is absent while nothing is behind the toolbar and appears once something is.
struct ToolbarBand: View {
    /// The toolbar's height, which the band covers entirely and ends at, with no fade below it.
    let toolbarHeight: CGFloat
    let isShown: Bool

    /// How much of the blur shows, so the content behind reads only as a faint ghost.
    static let strength: Double = 0.95

    /// How much of the system's separator color shows along the lower edge.
    static let hairline: Double = 1

    static let material: Material = .bar

    @Environment(\.displayScale) private var displayScale

    /// The values the band draws with: the constants above, which a Debug build lets the tuning panel replace.
    private var look: (strength: Double, hairline: Double) {
        #if DEBUG
        let tuning = Tuning.shared
        return (tuning.number(Knobs.strength), tuning.number(Knobs.hairline))
        #else
        return (Self.strength, Self.hairline)
        #endif
    }

    var body: some View {
        let look = look
        Rectangle()
            .fill(Self.material)
            .opacity(look.strength)
            .overlay(alignment: .bottom) {
                // One physical pixel, whatever the display's scale.
                Rectangle()
                    .fill(.separator)
                    .frame(height: 1 / displayScale)
                    .opacity(look.hairline)
            }
            .frame(height: toolbarHeight)
            // With no toolbar over the page, as in full screen while the toolbar is hidden, there is nothing to back.
            .opacity(isShown && toolbarHeight > 0 ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: isShown)
            // Clicks, the window's drag area and the toolbar's buttons all work as if it were not there.
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .ignoresSafeArea(.container, edges: .top)
    }
}

extension View {
    /// Gives a list or other scroll view the same toolbar edge as the page: a `ToolbarBand` over the toolbar once
    /// the content has scrolled beneath it. The system's own edge for the scroll view is hidden, so only one draws.
    func bandsToolbar() -> some View {
        modifier(BandsToolbar())
    }
}

private struct BandsToolbar: ViewModifier {
    @State private var isUnderToolbar = false

    func body(content: Content) -> some View {
        #if DEBUG
        let edge = Tuning.shared.choice(ToolbarBand.Knobs.listEdge, as: ToolbarBand.ListEdge.self) ?? .band
        #else
        let edge = ToolbarBand.ListEdge.band
        #endif
        content
            // At rest the content starts exactly below the toolbar, which the scroll geometry reports as an inset.
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 0.5 } action: { _, new in
                isUnderToolbar = new
            }
            .scrollEdgeEffectHidden(edge == .band, for: .top)
            .scrollEdgeEffectStyle(edge.systemStyle, for: .top)
            .overlay(alignment: .top) {
                GeometryReader { proxy in
                    ToolbarBand(toolbarHeight: proxy.safeAreaInsets.top, isShown: edge == .band && isUnderToolbar)
                }
            }
    }
}

extension ToolbarBand {
    /// What draws the toolbar's edge over a scrolling list.
    enum ListEdge: String, CaseIterable {
        case band, hard, soft, automatic

        /// The system's style for the choices that leave the edge to the system; nil for the band, which hides it.
        var systemStyle: ScrollEdgeEffectStyle? {
            switch self {
            case .band: nil
            case .hard: .hard
            case .soft: .soft
            case .automatic: .automatic
            }
        }
    }
}

#if DEBUG
extension ToolbarBand {
    /// The tuning knobs for the toolbar's edge, defaulting to the constants above. Delete each once its value is
    /// settled.
    enum Knobs {
        static let strength = Knob.slider("toolbarBand", "strength", ToolbarBand.strength, in: 0...1, step: 0.05)
        static let hairline = Knob.slider("toolbarBand", "hairline", ToolbarBand.hairline, in: 0...1, step: 0.05)
        static let listEdge = Knob.picker("toolbarBand", "listEdge", ListEdge.band)
        static let toolbarBackground = Knob.picker("toolbarBand", "windowToolbarBackground", WindowToolbarBackground.hidden)
    }

    /// Whether the window's toolbar draws a background of its own, which the system's scroll edge effect may depend
    /// on. The window hides it; `automatic` lets the system decide.
    enum WindowToolbarBackground: String, CaseIterable {
        case hidden, automatic

        var visibility: Visibility { self == .hidden ? .hidden : .automatic }
    }
}
#endif

extension ToolbarBand {
    /// The window toolbar's background: hidden, so the list, Settings and the page share the window's color up to
    /// the top, while `ToolbarBand` shows what is under the toolbar.
    static var windowToolbarBackground: Visibility {
        #if DEBUG
        Tuning.shared.choice(Knobs.toolbarBackground, as: WindowToolbarBackground.self)?.visibility ?? .hidden
        #else
        .hidden
        #endif
    }
}
