import SwiftUI

/// A sheet in the middle of the window, as an alert is, never dropping from under the toolbar: something new with
/// several fields, before it exists. Its label sits above each field, Cancel and the confirm button are gray and at the
/// trailing edge, and a destructive action stands alone at the leading edge.
struct SettingsSheet<Content: View, Buttons: View>: View {
    private let title: Text
    private let line: Text?
    private let isWide: Bool
    private let content: Content
    private let buttons: Buttons

    init(title: Text, line: Text? = nil, isWide: Bool = false, @ViewBuilder content: () -> Content, @ViewBuilder buttons: () -> Buttons) {
        self.title = title
        self.line = line
        self.isWide = isWide
        self.content = content()
        self.buttons = buttons()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                title.settingsFont(.headTitle).accessibilityAddTraits(.isHeader)
                if let line {
                    line.settingsFont(.small).foregroundStyle(SettingsTokens.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
            }
            content
            HStack(spacing: 8) { buttons }
        }
        .padding(20)
        .frame(width: isWide ? 560 : 440, alignment: .leading)
        .background(SettingsTokens.card, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(SettingsTokens.hairline, lineWidth: 1) }
        .shadow(color: .black.opacity(0.22), radius: 24, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// A field in a sheet, with its label above it.
struct SettingsSheetField<Field: View>: View {
    private let label: Text
    /// Why the input was refused, in one line under the field. The field takes the red ring itself.
    private let error: String?
    private let field: Field

    init(label: LocalizedStringKey, error: String? = nil, @ViewBuilder field: () -> Field) {
        self.label = Text(label)
        self.error = error
        self.field = field()
    }

    /// A label that is the person's own text, shown as it is.
    init(verbatim label: String, error: String? = nil, @ViewBuilder field: () -> Field) {
        self.label = Text(verbatim: label)
        self.error = error
        self.field = field()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            label.settingsFont(.line).foregroundStyle(SettingsTokens.secondaryText)
            field
            if let error {
                Text(verbatim: error).settingsFont(.line).foregroundStyle(SettingsTokens.errorRed).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A line in a sheet that says how the input stands: a dot, green where it is fine, and the words.
struct SettingsSheetStatus: View {
    let text: Text
    var isMet = true

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(isMet ? SettingsTokens.ok : SettingsTokens.tertiaryText).frame(width: 7, height: 7).accessibilityHidden(true)
            text.settingsFont(.line).foregroundStyle(SettingsTokens.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsSheetPresentation<Sheet: View>: ViewModifier {
    let isPresented: Bool
    let dismiss: () -> Void
    let sheet: Sheet

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    ZStack {
                        SettingsTokens.scrim
                            .ignoresSafeArea()
                            .onTapGesture {}
                        sheet
                            .onExitCommand(perform: dismiss)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: isPresented)
    }
}

extension View {
    /// Shows `sheet` in the middle of this view, over a scrim, which Escape dismisses.
    func settingsSheet(isPresented: Bool, dismiss: @escaping () -> Void, @ViewBuilder sheet: () -> some View) -> some View {
        modifier(SettingsSheetPresentation(isPresented: isPresented, dismiss: dismiss, sheet: sheet()))
    }
}
