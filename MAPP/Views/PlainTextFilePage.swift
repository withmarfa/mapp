import AppKit
import SwiftUI

/// File text is literal and selectable, using the same reading preferences as a note's page.
struct PlainTextFilePage: View {
    let text: String
    let title: String
    let openFile: () -> Void
    @StoredPageStyle private var style

    /// Text longer than this many UTF-8 bytes is drawn by an `NSTextView`, which lays out only what is on screen.
    /// SwiftUI's `Text` lays out all of it first: 4 MB held the window for seconds.
    static let largeTextBytes = 64 * 1024

    static func isLarge(_ text: String) -> Bool { text.utf8.count > largeTextBytes }

    var body: some View {
        if Self.isLarge(text) {
            largeBody
        } else {
            smallBody
        }
    }

    private var largeBody: some View {
        GeometryReader { geometry in
            let inset = style.horizontalInset(for: geometry.size.width)
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(verbatim: title)
                        .font(.system(size: CGFloat(style.textSize) * 1.9, weight: .bold))
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    Button("Open", systemImage: "arrow.up.forward.app", action: openFile)
                }
                .padding(.horizontal, inset)
                .padding(.top, 16)
                LargeTextView(text: text, title: title, textSize: CGFloat(style.textSize), inset: inset)
                    .accessibilityIdentifier("PlainTextFileBody")
            }
        }
        .accessibilityIdentifier("PlainTextFilePage")
    }

    private var smallBody: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(verbatim: title)
                            .font(.system(size: CGFloat(style.textSize) * 1.9, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 0)
                        Button("Open", systemImage: "arrow.up.forward.app", action: openFile)
                    }
                    Text(verbatim: text)
                        .font(.system(size: CGFloat(style.textSize)))
                        .lineSpacing(CGFloat(style.textSize) * 0.35)
                        .accessibilityIdentifier("PlainTextFileBody")
                }
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, style.horizontalInset(for: geometry.size.width))
                .padding(.top, 16)
                .padding(.bottom, 48)
            }
        }
        .accessibilityIdentifier("PlainTextFilePage")
    }
}

/// A read-only, selectable text view for text too long for SwiftUI's `Text`.
private struct LargeTextView: NSViewRepresentable {
    let text: String
    let title: String
    let textSize: CGFloat
    let inset: CGFloat

    /// What the view shows now, so an update with the same text compares nothing against the text storage.
    final class Coordinator {
        var text: String?
        var textSize: CGFloat?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        let view = scroll.documentView as! NSTextView
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.setAccessibilityLabel(title)
        apply(to: view, context.coordinator)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let view = scroll.documentView as! NSTextView
        view.setAccessibilityLabel(title)
        apply(to: view, context.coordinator)
    }

    private func apply(to view: NSTextView, _ shown: Coordinator) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = textSize * 0.35
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: textSize), .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph,
        ]
        // Setting the same text again would lay it out again and lose the person's place and selection. The last
        // text applied is kept here, since reading the text view's own string copies all of it.
        if shown.text != text || shown.textSize != textSize {
            (shown.text, shown.textSize) = (text, textSize)
            view.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
        }
        view.textContainerInset = NSSize(width: inset, height: 8)
    }
}
