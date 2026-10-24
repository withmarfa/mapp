import SwiftUI

/// File text is literal and selectable, using the same reading preferences as a note's page.
struct PlainTextFilePage: View {
    let text: String
    let title: String
    let openFile: () -> Void
    @StoredPageStyle private var style

    var body: some View {
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
        .background(.windowBackground)
        .accessibilityIdentifier("PlainTextFilePage")
    }
}
