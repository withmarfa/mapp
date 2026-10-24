import SwiftUI

struct StudyHighlightPage: View {
    @Binding var note: String
    let open: (InterfaceStudy) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                StudyEyebrow(title: "Book highlight", symbol: "quote.opening")

                VStack(alignment: .leading, spacing: 26) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text("A small space asks for fewer ideas, held for longer.")
                        .font(.system(size: 40, weight: .regular, design: .serif))
                        .lineSpacing(7)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityAddTraits(.isHeader)

                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "book.closed")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 52)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Small Is Plenty").font(.headline)
                            Text("Rowan Ellis").foregroundStyle(.secondary)
                            Text("Chapter 3, page 48")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 12)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Your thought").font(.headline)
                    Text("What does this make you want to try?")
                        .foregroundStyle(.secondary)
                    TextField("Add a thought…", text: $note, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(4...9)
                        .font(.body)
                        .padding(16)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(.quaternary, lineWidth: 1)
                        }
                    Text("This sample note lasts while this window is open.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep following the idea").font(.headline).padding(.bottom, 6)
                    StudyRelatedLink(title: "The case for small, wet corners", subtitle: "Mara Quinn, Field & Street", symbol: "doc.richtext") {
                        open(.reading)
                    }
                    Divider()
                    StudyRelatedLink(title: "A garden in a small space", subtitle: "The collection this idea belongs to", symbol: "square.stack") {
                        open(.collection)
                    }
                }
                Text("Fictional book and highlight for this interface study.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 660, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 48)
            .frame(maxWidth: .infinity)
        }
    }
}
