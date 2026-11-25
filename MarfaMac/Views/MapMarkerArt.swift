import AppKit
import SwiftUI

/// What the map draws for an item and for items grouped: a balloon in the type's tone with its symbol and the title under
/// it, a larger balloon under a card where the item is chosen, and a neutral badge with a count. A map view shows only
/// images, so each is drawn here once for the state it stands in (`MapArtist`) and held.
struct MapMarkerArt: View {
    let glyph: String?
    let tone: TypeTone
    let title: String
    let typeName: String
    let subtitle: String?
    let isChosen: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.interfaceTextSize) private var textSize

    private var scale: CGFloat { InterfaceStyle.scale(for: textSize) }

    var body: some View {
        VStack(spacing: 0) {
            if isChosen { card.padding(.bottom, 4) }
            balloon
            if !isChosen { label }
        }
        .padding(isChosen ? Self.chosenEdge : Self.edge)
    }

    static let labelHeight: CGFloat = 16
    static let edge: CGFloat = 4
    static let chosenEdge: CGFloat = 12

    /// How far the balloon's tip stands above the foot of the picture, which the map anchors on the item's point.
    static func tipFromFoot(isChosen: Bool, scale: CGFloat) -> CGFloat {
        isChosen ? chosenEdge : edge + 1 + labelHeight * scale
    }

    private var balloonSize: CGFloat { (isChosen ? 36 : 28) * scale }

    private var balloon: some View {
        VStack(spacing: -3) {
            ZStack {
                Circle().fill(tone.color(for: scheme))
                Image(typeGlyph: glyph)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .padding(balloonSize * 0.26)
            }
            .frame(width: balloonSize, height: balloonSize)
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
            Triangle()
                .fill(tone.color(for: scheme))
                .frame(width: 9 * scale, height: 8 * scale)
        }
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }

    /// The title under a marker, ringed in the map's own ground so it reads on streets and parks.
    private var label: some View {
        let ground: Color = scheme == .dark ? .black : .white
        return Text(title)
            .font(.system(size: 11 * scale, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .frame(maxWidth: 170 * scale)
            .frame(height: Self.labelHeight * scale)
            .shadow(color: ground, radius: 1.5)
            .shadow(color: ground, radius: 1.5)
            .padding(.top, 1)
    }

    private var card: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(typeGlyph: glyph).resizable().scaledToFit().frame(width: 11 * scale, height: 11 * scale)
                    Text(typeName)
                }
                .font(.system(size: 11 * scale))
                .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 14 * scale, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12 * scale))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 260 * scale, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
            Triangle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .rotationEffect(.degrees(180))
                .frame(width: 12, height: 6)
        }
        .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
    }
}

/// Items grouped where they crowd: a neutral round badge with how many it holds, larger as the count grows.
struct MapGroupArt: View {
    let count: Int

    @Environment(\.colorScheme) private var scheme
    @Environment(\.interfaceTextSize) private var textSize

    static func diameter(of count: Int) -> CGFloat {
        switch String(count).count {
        case ...2: 30
        case 3: 34
        case 4: 40
        default: 46
        }
    }

    var body: some View {
        let size = Self.diameter(of: count) * InterfaceStyle.scale(for: textSize)
        Text(count, format: .number)
            .font(.system(size: 13 * InterfaceStyle.scale(for: textSize), weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(nsColor: scheme == .dark ? .windowBackgroundColor : .white)))
            .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .padding(5)
    }
}

private nonisolated struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Draws the map's markers into images, each once for the state it stands in.
@MainActor
final class MapArtist {
    struct Drawn {
        let image: NSImage
        /// Where the marker's point stands in the image, measured up from the foot.
        let tipFromFoot: CGFloat
    }

    private var held: [String: Drawn] = [:]
    var scheme: ColorScheme = .light
    var textSize = InterfaceStyle.defaultTextSize
    var backingScale: CGFloat = 2

    /// Forgets every drawing, as a change of appearance or text size makes them stale.
    @discardableResult
    func reset(scheme: ColorScheme, textSize: Int, backingScale: CGFloat) -> Bool {
        guard scheme != self.scheme || textSize != self.textSize || backingScale != self.backingScale else { return false }
        held = [:]
        self.scheme = scheme
        self.textSize = textSize
        self.backingScale = backingScale
        return true
    }

    func marker(
        glyph: String?, tone: TypeTone, title: String, typeName: String, subtitle: String?, isChosen: Bool
    ) -> Drawn {
        let key = "m|\(glyph ?? "")|\(tone.rawValue)|\(title)|\(typeName)|\(subtitle ?? "")|\(isChosen)"
        if let drawn = held[key] { return drawn }
        let art = MapMarkerArt(glyph: glyph, tone: tone, title: title, typeName: typeName, subtitle: subtitle, isChosen: isChosen)
        let drawn = render(art, tipFromFoot: MapMarkerArt.tipFromFoot(isChosen: isChosen, scale: InterfaceStyle.scale(for: textSize)))
        remember(drawn, for: key)
        return drawn
    }

    func group(count: Int) -> Drawn {
        let key = "g|\(count)"
        if let drawn = held[key] { return drawn }
        let drawn = render(MapGroupArt(count: count), tipFromFoot: MapGroupArt.diameter(of: count) * InterfaceStyle.scale(for: textSize) / 2 + 5)
        remember(drawn, for: key)
        return drawn
    }

    /// A large library is drawn in pieces, so what is held stays bounded.
    private func remember(_ drawn: Drawn, for key: String) {
        if held.count > 4_000 { held = [:] }
        held[key] = drawn
    }

    private func render<Art: View>(_ art: Art, tipFromFoot: CGFloat) -> Drawn {
        let renderer = ImageRenderer(
            content: art.environment(\.colorScheme, scheme).environment(\.interfaceTextSize, textSize))
        renderer.scale = backingScale
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 1, height: 1))
        return Drawn(image: image, tipFromFoot: tipFromFoot)
    }
}
