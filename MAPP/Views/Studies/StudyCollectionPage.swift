import SwiftUI

struct StudyCollectionPage: View {
    @Binding var completedWork: Set<String>
    let open: (InterfaceStudy) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 16) {
                    StudyEyebrow(title: "Sample collection", symbol: "square.stack")
                    Text("A garden in a small space")
                        .font(.system(size: 36, weight: .semibold, design: .serif))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("A few useful ideas for a quieter, greener corner. Collect what matters, try one thing, and watch what changes.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineSpacing(5)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 28) { context }
                    VStack(alignment: .leading, spacing: 16) { context }
                }

                Divider()

                HStack(spacing: 32) {
                    count(3, title: "Readings")
                    count(2, title: "Highlights")
                    count(3, title: "Notes")
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("The next small steps").font(.title3.weight(.semibold))
                        Spacer()
                        Text("\(completedWork.count) of 3")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text("Make room for observation before making a plan.")
                        .foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        work("rain", title: "Watch the corner after rain", subtitle: "Notice where the water goes and how long it stays.")
                        Divider()
                        work("plants", title: "Choose three plants to compare", subtitle: "Start with the light and moisture they need.")
                        Divider()
                        work("chair", title: "Try the chair in a different place", subtitle: "Find the afternoon light before committing.")
                    }
                    .padding(.horizontal, 18)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                    Text("Checkmarks are part of this study and last while the window is open.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Ideas to keep close").font(.title3.weight(.semibold)).padding(.bottom, 6)
                    StudyRelatedLink(title: "The case for small, wet corners", subtitle: "A practical place to start, from Field & Street", symbol: "doc.richtext") {
                        open(.reading)
                    }
                    Divider()
                    StudyRelatedLink(title: "Fewer ideas, held for longer", subtitle: "A highlight from Small Is Plenty", symbol: "quote.opening") {
                        open(.highlight)
                    }
                }

                Button("Explore All 8 Sample Items", systemImage: "magnifyingglass") {
                    open(.search)
                }
                Text("Fictional collection for this interface study.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 44)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var context: some View {
        Label("Exploring", systemImage: "circle.lefthalf.filled")
            .font(.subheadline.weight(.medium))
        Label("Personal project", systemImage: "folder")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        Label("Garden notebook", systemImage: "book.closed")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private func count(_ value: Int, title: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value, format: .number).font(.title2.monospacedDigit())
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func work(_ id: String, title: LocalizedStringResource, subtitle: LocalizedStringResource) -> some View {
        Toggle(isOn: Binding(
            get: { completedWork.contains(id) },
            set: { isComplete in
                if isComplete { completedWork.insert(id) }
                else { completedWork.remove(id) }
            }
        )) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .strikethrough(completedWork.contains(id))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 15)
    }
}
