import SwiftUI

enum InterfaceStudy: String, CaseIterable, Identifiable {
    case reading, highlight, search, collection

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .reading: "Reading page"
        case .highlight: "Highlight page"
        case .search: "Search"
        case .collection: "Collection overview"
        }
    }

    var symbol: String {
        switch self {
        case .reading: "doc.richtext"
        case .highlight: "quote.opening"
        case .search: "magnifyingglass"
        case .collection: "square.stack"
        }
    }
}

struct InterfaceStudiesView: View {
    @State private var selection: InterfaceStudy? = .reading
    @State private var readerOptions = StudyReaderOptions()
    @State private var highlightNote = ""
    @State private var searchQuery = ""
    @State private var searchKind: StudyRecord.Kind?
    @State private var searchSelection: String?
    @State private var completedWork: Set<String> = []

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Interface Studies") {
                    ForEach(InterfaceStudy.allCases) { study in
                        NavigationLink(value: study) {
                            Label { Text(study.title) } icon: { Image(systemName: study.symbol) }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 270)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Sample content", systemImage: "square.dashed")
                        .font(.caption.weight(.medium))
                    Text("A place to compare native layouts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        } detail: {
            Group {
                switch selection ?? .reading {
                case .reading:
                    StudyReadingPage(options: $readerOptions, open: open)
                case .highlight:
                    StudyHighlightPage(note: $highlightNote, open: open)
                case .search:
                    StudySearchPage(query: $searchQuery, kind: $searchKind,
                                    selection: $searchSelection, open: open)
                case .collection:
                    StudyCollectionPage(completedWork: $completedWork, open: open)
                }
            }
            .navigationTitle(Text((selection ?? .reading).title))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func open(_ study: InterfaceStudy) {
        selection = study
    }
}

struct StudyEyebrow: View {
    let title: LocalizedStringResource
    let symbol: String

    var body: some View {
        Label { Text(title) } icon: { Image(systemName: symbol) }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
    }
}

struct StudyRelatedLink: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 5)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Native interface studies") {
    InterfaceStudiesView()
        .frame(width: 1180, height: 820)
}
