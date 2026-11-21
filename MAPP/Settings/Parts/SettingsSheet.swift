import SwiftUI

extension EnvironmentValues {
    /// The tallest a sheet may be: the window's height less the room kept from its edges. A sheet taller than this scrolls.
    @Entry var settingsSheetMaxHeight: CGFloat = .infinity
}

extension EnvironmentValues {
    /// How far a section's name and line sit from the card's edge: 16 on a page, nearer inside a sheet.
    @Entry var settingsSectionInset: CGFloat = SettingsTokens.Metric.inset
}

/// A sheet in the middle of the window, as an alert is, never dropping from under the toolbar: something new with
/// several fields, before it exists. Its label sits above each field, Cancel and the confirm button are gray and at the
/// trailing edge, and a destructive action stands alone at the leading edge. A sheet grows with what it holds up to the
/// window's height, then its content scrolls between the title and the buttons.
struct SettingsSheet<Content: View, Buttons: View>: View {
    private let title: Text
    private let line: Text?
    private let isWide: Bool
    private let content: Content
    private let buttons: Buttons
    @Environment(\.settingsSheetMaxHeight) private var maxHeight
    @State private var headHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var buttonsHeight: CGFloat = 0

    init(title: Text, line: Text? = nil, isWide: Bool = false, @ViewBuilder content: () -> Content, @ViewBuilder buttons: () -> Buttons) {
        self.title = title
        self.line = line
        self.isWide = isWide
        self.content = content()
        self.buttons = buttons()
    }

    private var scrollHeight: CGFloat {
        min(contentHeight, max(0, maxHeight - headHeight - buttonsHeight))
    }

    var body: some View {
        let padding = SettingsTokens.Metric.sheetPadding
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                title.settingsFont(.headTitle).accessibilityAddTraits(.isHeader)
                if let line {
                    line.settingsFont(.small).foregroundStyle(SettingsTokens.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, padding)
            .padding(.top, padding)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headHeight = $0 }
            ScrollView {
                content
                    .padding(.horizontal, padding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.settingsSectionInset, SettingsTokens.Metric.sheetSectionInset)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollEdgeEffectStyle(.soft, for: .vertical)
            .frame(height: scrollHeight)
            HStack(spacing: 8) { buttons }
                .padding(.horizontal, padding)
                .padding(.top, 16)
                .padding(.bottom, padding)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { buttonsHeight = $0 }
        }
        .frame(width: isWide ? SettingsTokens.Metric.sheetWideWidth : SettingsTokens.Metric.sheetWidth, alignment: .leading)
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
                    GeometryReader { window in
                        ZStack {
                            SettingsTokens.scrim
                                .onTapGesture {}
                            sheet
                                .environment(\.settingsSheetMaxHeight, window.size.height - 2 * SettingsTokens.Metric.sheetEdgeMargin)
                                .onExitCommand(perform: dismiss)
                        }
                    }
                    .ignoresSafeArea()
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
