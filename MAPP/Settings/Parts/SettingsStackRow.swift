import AppKit
import SwiftUI

/// A row that holds a long text under its title, as a description or a guidance does: the title, one line under it where
/// the row has one, and the text or its field across the whole card.
struct SettingsStackRow<Content: View>: View {
    private let title: Text
    private let line: Text?
    private let error: String?
    private let content: Content

    init(title: Text, line: Text? = nil, error: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.line = line
        self.error = error
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Metric.stackGap) {
            VStack(alignment: .leading, spacing: 2) {
                title.settingsFont(.title).foregroundStyle(SettingsTokens.primaryText)
                if let error {
                    Text(verbatim: error).settingsFont(.line).foregroundStyle(SettingsTokens.errorRed).fixedSize(horizontal: false, vertical: true)
                } else if let line {
                    line.settingsFont(.line).foregroundStyle(SettingsTokens.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .padding(.horizontal, SettingsTokens.Metric.inset)
        .padding(.vertical, SettingsTokens.Metric.cardGap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerValue(\.settingsRuleInset, SettingsTokens.Metric.inset)
        .accessibilityElement(children: .contain)
    }
}

/// A text that cannot be changed here, shown whole under its title: a plugin's guidance, or an ancestor's.
struct SettingsStackText: View {
    let text: String
    var isLocked = false
    /// Read the text as Markdown, inline only, so `**bold**` shows bold and nothing else changes shape. A link opens only
    /// when the person clicks it.
    var isMarkdown = false

    private var shown: Text {
        guard isMarkdown, let styled = try? AttributedString(
            markdown: text, options: .init(allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace))
        else { return Text(verbatim: text) }
        return Text(styled)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsTokens.Metric.dotGap) {
            if isLocked {
                Image(systemName: "lock").font(.system(size: SettingsTokens.Metric.lockGlyph)).foregroundStyle(SettingsTokens.tertiaryText)
                    .accessibilityHidden(true)
            }
            shown.settingsFont(.line).foregroundStyle(SettingsTokens.secondaryText).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// A text of several lines in the rounded field's look: Return starts a new line, and the text is kept when the field is left.
/// It is plain text, so what is typed is never changed into curly quotes, dashes or other substitutes: a Markdown text is kept
/// as written.
struct SettingsTextArea: View {
    let title: String.LocalizationValue
    @Binding var text: String
    var isError = false
    var lines = 6
    /// Run when the field loses focus, so a text typed and left is kept as one that was submitted.
    var onEndEditing: (() -> Void)?
    @Environment(\.settingsTextScale) private var scale

    var body: some View {
        SettingsPlainTextView(label: String(localized: title), text: $text, size: 13 * scale, onEndEditing: onEndEditing)
            .frame(height: CGFloat(lines) * 17 * scale + 14)
            .background(SettingsTokens.field, in: .rect(cornerRadius: SettingsTokens.Metric.controlRadius))
            .overlay { RoundedRectangle(cornerRadius: SettingsTokens.Metric.controlRadius).strokeBorder(SettingsTokens.hairline) }
            .settingsErrorRing(isError)
    }
}

/// The system's text view in a scroll view, set to keep exactly what is typed.
private struct SettingsPlainTextView: NSViewRepresentable {
    let label: String
    @Binding var text: String
    let size: CGFloat
    let onEndEditing: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, onEndEditing: onEndEditing) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.delegate = context.coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.textContainerInset = NSSize(width: 4, height: 6)
        view.font = .systemFont(ofSize: size)
        view.setAccessibilityLabel(label)
        view.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onEndEditing = onEndEditing
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.font?.pointSize != size { view.font = .systemFont(ofSize: size) }
        // A change made by typing is already in the view, and setting it again would move the cursor.
        if view.string != text { view.string = text }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onEndEditing: (() -> Void)?

        init(text: Binding<String>, onEndEditing: (() -> Void)?) {
            self.text = text
            self.onEndEditing = onEndEditing
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string
        }

        func textDidEndEditing(_ notification: Notification) { onEndEditing?() }
    }
}
