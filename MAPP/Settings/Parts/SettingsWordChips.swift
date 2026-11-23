import SwiftUI

/// One word at a row's trailing edge: the type's own, which can be changed, or one a type above gives, which is locked.
struct SettingsWord: Identifiable, Hashable {
    let id: String
    let title: String
    /// What the word means, as its help.
    var meaning: String?
    var isLocked: Bool
}

/// A row's words as chips, in the order given: a locked word with a small lock before it and no fill, an own word on a gray
/// fill, then a small plus that adds a word in place. While a word is typed, its field takes the plus's place; Return keeps
/// it and Escape leaves it. A refusal puts the red ring on the field and keeps what was typed.
struct SettingsWordChips: View {
    let words: [SettingsWord]
    let addTitle: LocalizedStringKey
    /// Whether the plus is offered; a type that cannot change has no plus.
    var canAdd = true
    var isAdding: Bool
    @Binding var draft: String
    var isError = false
    var begin: () -> Void
    var commit: () -> Void
    var cancel: () -> Void
    /// What an own word's menu offers, for the word with this id.
    var menu: ((SettingsWord) -> AnyView)?
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: SettingsTokens.Metric.chipGap) {
            ForEach(words) { word in chip(word) }
            if isAdding {
                TextField("New Word", text: $draft)
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .settingsFont(.line)
                    .padding(.horizontal, SettingsTokens.Metric.chipPadding)
                    .frame(width: SettingsTokens.Metric.chipFieldWidth, height: SettingsTokens.Metric.chipHeight)
                    .background(SettingsTokens.field, in: .rect(cornerRadius: SettingsTokens.Metric.chipRadius))
                    .overlay { RoundedRectangle(cornerRadius: SettingsTokens.Metric.chipRadius).strokeBorder(isError ? SettingsTokens.errorRed : SettingsTokens.focusRing, lineWidth: isError ? 1.5 : 1) }
                    .focused($isFocused)
                    .onSubmit(commit)
                    .onExitCommand(perform: cancel)
                    .onAppear { isFocused = true }
                    .onChange(of: isFocused) { if !$1 { commit() } }
            } else if canAdd {
                Button(action: begin) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .medium))
                        .frame(width: SettingsTokens.Metric.chipHeight, height: SettingsTokens.Metric.chipHeight)
                        .overlay { RoundedRectangle(cornerRadius: SettingsTokens.Metric.chipRadius).strokeBorder(SettingsTokens.hairline) }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(SettingsTokens.secondaryText)
                .accessibilityLabel(Text(addTitle))
            }
        }
    }

    @ViewBuilder private func chip(_ word: SettingsWord) -> some View {
        let label = HStack(spacing: SettingsTokens.Metric.dotGap) {
            if word.isLocked {
                Image(systemName: "lock").font(.system(size: SettingsTokens.Metric.lockGlyph)).foregroundStyle(SettingsTokens.tertiaryText)
                    .accessibilityHidden(true)
            }
            Text(verbatim: word.title).settingsFont(.line).lineLimit(1).truncationMode(.tail)
                .foregroundStyle(word.isLocked ? SettingsTokens.secondaryText : SettingsTokens.primaryText)
        }
        if word.isLocked {
            label.frame(maxWidth: SettingsTokens.Metric.chipMaxWidth).fixedSize(horizontal: true, vertical: false).help(word.meaning ?? "")
        } else {
            label
                .padding(.horizontal, SettingsTokens.Metric.chipPadding)
                .frame(height: SettingsTokens.Metric.chipHeight)
                .frame(maxWidth: SettingsTokens.Metric.chipMaxWidth)
                .fixedSize(horizontal: true, vertical: false)
                .background(SettingsTokens.buttonFill, in: .rect(cornerRadius: SettingsTokens.Metric.chipRadius))
                .help(word.meaning ?? "")
                .contextMenu { menu?(word) }
        }
    }
}
