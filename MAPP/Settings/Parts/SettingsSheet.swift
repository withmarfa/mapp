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
    let label: LocalizedStringKey
    @ViewBuilder let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).settingsFont(.line).foregroundStyle(SettingsTokens.secondaryText)
            field
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
