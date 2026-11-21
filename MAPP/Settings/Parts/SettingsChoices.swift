import SwiftUI

/// Choices drawn as pictures filling a section's card, for a look the person should see, such as a theme or a row style.
/// The chosen one takes a gray ring, never the accent.
struct ChoiceTiles<Value: Hashable>: View {
    struct Choice: Identifiable {
        let value: Value
        let title: Text
        let picture: AnyView
        var id: Value { value }
    }

    let choices: [Choice]
    @Binding var selection: Value
    /// How many tiles the card has room for, where that is more than there are choices: the tiles keep their size and the
    /// empty places stay empty, so two row styles are not stretched to fill the card.
    var columns: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(choices) { choice in
                Button { selection = choice.value } label: {
                    VStack(spacing: 6) {
                        choice.picture
                            .frame(maxWidth: .infinity)
                            .aspectRatio(SettingsTokens.Metric.choiceAspect, contentMode: .fit)
                            .clipShape(.rect(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(
                                        selection == choice.value ? SettingsTokens.primaryText.opacity(0.55) : SettingsTokens.hairline,
                                        lineWidth: selection == choice.value ? 2 : 1)
                            }
                        choice.title.settingsFont(.small).fontWeight(selection == choice.value ? .semibold : .regular)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == choice.value ? .isSelected : [])
            }
            ForEach(0..<max(0, (columns ?? choices.count) - choices.count), id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity).accessibilityHidden(true)
            }
        }
        .padding(SettingsTokens.Metric.inset)
    }
}

/// A list of words or patterns changed in place: double-click or Return edits a line, the add row adds one, a handle on
/// each line shows where order matters (the last match wins), and a line Marfa can't read has its error under it.
struct PatternList: View {
    @Binding var lines: [String]
    let addTitle: LocalizedStringKey
    var showsHandles = false
    /// The reason a line, by its position, can't be read.
    var errors: [Int: String] = [:]

    @State private var selected: Int?
    @State private var editing: Int?
    @State private var draft = ""
    @State private var dragged: Int?
    @FocusState private var focused: Int?

    var body: some View {
        SettingsCard {
            ForEach(lines.indices, id: \.self) { index in
                line(index)
            }
            Button(action: add) {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .medium))
                    Text(addTitle)
                    Spacer(minLength: 0)
                }
                .settingsFont(.title)
                .foregroundStyle(SettingsTokens.secondaryText)
                .padding(.horizontal, SettingsTokens.Metric.inset)
                .frame(maxWidth: .infinity, minHeight: SettingsTokens.Metric.rowHeightCompact, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private func line(_ index: Int) -> some View {
        let isEditing = editing == index
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                if showsHandles {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsTokens.tertiaryText)
                        .accessibilityHidden(true)
                }
                if isEditing {
                    TextField("Pattern", text: $draft)
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .font(SettingsTokens.font(.mono))
                        .focused($focused, equals: index)
                        .onSubmit { finish(index, keeping: true) }
                        .onExitCommand { finish(index, keeping: false) }
                        .padding(.horizontal, 6)
                        .frame(height: 24)
                        .background(SettingsTokens.field, in: .rect(cornerRadius: 5))
                        .settingsErrorRing(errors[index] != nil)
                } else {
                    Text(verbatim: lines[index])
                        .font(SettingsTokens.font(.mono))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            if let error = errors[index] {
                Text(verbatim: error).settingsFont(.line).foregroundStyle(SettingsTokens.errorRed)
            }
        }
        .padding(.horizontal, SettingsTokens.Metric.inset)
        .frame(maxWidth: .infinity, minHeight: SettingsTokens.Metric.rowHeightCompact, alignment: .leading)
        .background(selected == index && !isEditing ? SettingsTokens.selection : Color.clear)
        .contentShape(.rect)
        .onTapGesture(count: 2) { begin(index) }
        .onTapGesture { selected = index }
        .focusable(!isEditing)
        .onKeyPress(.return) {
            guard selected == index, !isEditing else { return .ignored }
            begin(index)
            return .handled
        }
        .onKeyPress(.delete) {
            guard selected == index, !isEditing else { return .ignored }
            lines.remove(at: index)
            selected = nil
            return .handled
        }
        .contextMenu {
            Button("Edit") { begin(index) }
            if index > 0 { Button("Move Up") { lines.swapAt(index, index - 1) } }
            if index < lines.count - 1 { Button("Move Down") { lines.swapAt(index, index + 1) } }
            Divider()
            Button("Remove", role: .destructive) { lines.remove(at: index) }
        }
        .containerValue(\.settingsRuleInset, SettingsTokens.Metric.inset)
        .draggable(showsHandles ? String(index) : "") {
            Text(verbatim: lines[index]).font(SettingsTokens.font(.mono)).padding(6)
        }
        .dropDestination(for: String.self) { items, _ in
            guard showsHandles, let from = items.first.flatMap(Int.init), from != index, lines.indices.contains(from) else { return false }
            lines.move(fromOffsets: [from], toOffset: from < index ? index + 1 : index)
            return true
        }
    }

    private func begin(_ index: Int) {
        draft = lines[index]
        editing = index
        focused = index
    }

    private func add() {
        lines.append("")
        begin(lines.count - 1)
    }

    private func finish(_ index: Int, keeping: Bool) {
        guard lines.indices.contains(index) else { return }
        let text = draft.trimmingCharacters(in: .whitespaces)
        if keeping, !text.isEmpty {
            lines[index] = text
        } else if lines[index].isEmpty {
            lines.remove(at: index)
        }
        editing = nil
    }
}

/// The tile of a row style: a small list in the density it names. Standard has a title and a quieter line under each row,
/// and Compact a title alone, so more rows fit.
struct SettingsRowStylePicture: View {
    let isCompact: Bool

    private typealias Metric = SettingsTokens.Metric
    private typealias Preview = SettingsTokens.RowPreview

    var body: some View {
        GeometryReader { space in
            VStack(alignment: .leading, spacing: Metric.rowPreviewGap) {
                ForEach(0..<(isCompact ? 5 : 3), id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Metric.rowPreviewInner) {
                        bar(Preview.title, share: Metric.rowPreviewTitle, in: space.size.width)
                        if !isCompact { bar(Preview.line, share: Metric.rowPreviewLine, in: space.size.width) }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Metric.rowPreviewPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Preview.page)
        }
    }

    private func bar(_ color: Color, share: CGFloat, in width: CGFloat) -> some View {
        Capsule().fill(color).frame(width: (width - Metric.rowPreviewPadding * 2) * share, height: Metric.rowPreviewBar)
    }
}
