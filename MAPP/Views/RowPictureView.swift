import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The size of a row's picture, in points.
enum RowPictureMetrics {
    static let side: CGFloat = 44
    static let radius: CGFloat = 6
}

/// The small picture at a Standard row's trailing edge, under the date: a rounded square with a hairline edge, the same
/// size whatever it holds. What fills it is whatever its content draws.
struct RowPictureFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RowPictureMetrics.radius, style: .continuous)
        Color(nsColor: .textBackgroundColor)
            .overlay { content }
            .frame(width: RowPictureMetrics.side, height: RowPictureMetrics.side)
            .clipShape(shape)
            .overlay { shape.strokeBorder(.separator, lineWidth: 0.5) }
            .accessibilityHidden(true)
    }
}

/// A row's picture, made as a gallery card's is (`GalleryArtworkCache`): off the main thread, a few at a time, kept by what
/// decides it, and only while the row is on screen. A quiet frame stands in until it is ready, and stays as the item's mark
/// where the item turns out to have none, so a row never changes height once it is drawn. It is a view of its own, so the
/// row's body, which only says that a picture is there, does none of this.
struct RowPictureView: View {
    @CurrentLibrary private var library
    @Environment(\.displayScale) private var displayScale
    let picture: RowPicture
    /// The item's type's icon, for the frame of an item whose picture cannot be made.
    let icon: String?
    @State private var artwork: GalleryArtwork?
    /// Whether making the picture has ended, with or without one, so the frame does not show its mark while it waits.
    @State private var resolved = false

    var body: some View {
        let basis = GalleryArtworkCache.basis(of: picture.item, attachments: picture.attachments, in: library)
        let shown = artwork ?? GalleryArtworkCache.peek(basis, width: RowPictureMetrics.side)
        RowPictureFrame {
            if let shown {
                Color.clear.overlay(alignment: shown.isDocument ? .top : .center) {
                    Image(decorative: shown.image, scale: displayScale).resizable().scaledToFill()
                }
                .clipped()
            } else if resolved {
                mark
            } else {
                Color.primary.opacity(0.03)
            }
        }
        .task(id: basis) {
            artwork = nil
            resolved = GalleryArtworkCache.peek(basis, width: RowPictureMetrics.side) != nil
            let made = await GalleryArtworkCache.artwork(
                for: picture.item, attachments: picture.attachments, width: RowPictureMetrics.side, scale: displayScale, in: library)
            if !Task.isCancelled {
                artwork = made
                resolved = true
            }
        }
    }

    /// A file with no picture of its own shows its kind's icon, as a card does; any other item its type's mark.
    @ViewBuilder private var mark: some View {
        if case .file(let type, _) = picture.item.content {
            Image(nsImage: NSWorkspace.shared.icon(for: type)).resizable().scaledToFit().padding(7)
        } else {
            Image(typeGlyph: icon).resizable().scaledToFit().frame(width: 16, height: 16).foregroundStyle(.quaternary)
        }
    }
}

/// A drawn picture for a preview of a row that has no item behind it: a sky, a sun and two hills, in colors of their own.
struct SamplePicture: View {
    var body: some View {
        GeometryReader { geometry in
            let side = geometry.size.width
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [Color(red: 0.55, green: 0.74, blue: 0.93), Color(red: 0.96, green: 0.84, blue: 0.68)], startPoint: .top, endPoint: .bottom)
                Circle().fill(Color(red: 1, green: 0.93, blue: 0.7)).frame(width: side * 0.3).position(x: side * 0.7, y: side * 0.3)
                Ellipse().fill(Color(red: 0.36, green: 0.58, blue: 0.45)).frame(width: side * 1.3, height: side * 0.7).offset(x: -side * 0.25, y: side * 0.3)
                Ellipse().fill(Color(red: 0.24, green: 0.44, blue: 0.36)).frame(width: side * 1.2, height: side * 0.6).offset(x: side * 0.3, y: side * 0.35)
            }
        }
        .accessibilityHidden(true)
    }
}
