import SwiftUI

extension EnvironmentValues {
    /// The tallest a sheet may be: the window's height less the room kept from its edges. A sheet taller than this scrolls.
    @Entry var settingsSheetMaxHeight: CGFloat = .infinity
}

extension EnvironmentValues {
    /// How far a section's name and line sit from the card's edge: 16 on a page, nearer inside a sheet.
    @Entry var settingsSectionInset: CGFloat = SettingsTokens.Metric.inset
}

/// A sheet centered in the window for a form with several fields. The leading slot holds a destructive action or reset.
/// The trailing slot holds Cancel and any confirm button. When the sheet reaches the window's height, only the content scrolls.
struct SettingsSheet<Content: View, Leading: View, Buttons: View>: View {
    private let title: Text
    private let line: Text?
    private let isWide: Bool
    private let content: Content
    private let leading: Leading
    private let buttons: Buttons
    @Environment(\.settingsSheetMaxHeight) private var maxHeight
    @State private var headHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var buttonsHeight: CGFloat = 0

    init(
        title: Text, line: Text? = nil, isWide: Bool = false, @ViewBuilder content: () -> Content, @ViewBuilder leading: () -> Leading,
        @ViewBuilder buttons: () -> Buttons
    ) {
        self.title = title
        self.line = line
        self.isWide = isWide
        self.content = content()
        self.leading = leading()
        self.buttons = buttons()
    }

    private var scrollHeight: CGFloat {
        min(contentHeight, max(0, maxHeight - headHeight - buttonsHeight))
    }

    var body: some View {
        let padding = SettingsTokens.Metric.sheetPadding
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetHeadSpacing) {
                title.settingsFont(.headTitle).accessibilityAddTraits(.isHeader)
                if let line {
                    line.settingsFont(.small).foregroundStyle(SettingsTokens.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, padding)
            .padding(.top, padding)
            .padding(.bottom, SettingsTokens.Metric.sheetGap)
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
            HStack(spacing: SettingsTokens.Metric.buttonGap) {
                leading
                Spacer(minLength: 0)
                buttons
            }
                .padding(.horizontal, padding)
                .padding(.top, SettingsTokens.Metric.sheetGap)
                .padding(.bottom, padding)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { buttonsHeight = $0 }
        }
        .frame(width: isWide ? SettingsTokens.Metric.sheetWideWidth : SettingsTokens.Metric.sheetWidth, alignment: .leading)
        .background(SettingsTokens.card, in: .rect(cornerRadius: SettingsTokens.Metric.sheetRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsTokens.Metric.sheetRadius, style: .continuous).strokeBorder(SettingsTokens.hairline, lineWidth: 1)
        }
        .shadow(color: SettingsTokens.sheetShadow, radius: SettingsTokens.Metric.sheetShadowRadius, y: SettingsTokens.Metric.sheetShadowDrop)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

extension SettingsSheet where Leading == EmptyView {
    init(title: Text, line: Text? = nil, isWide: Bool = false, @ViewBuilder content: () -> Content, @ViewBuilder buttons: () -> Buttons) {
        self.init(title: title, line: line, isWide: isWide, content: content, leading: { EmptyView() }, buttons: buttons)
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
        VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetLabelSpacing) {
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
        HStack(spacing: SettingsTokens.Metric.dotGap) {
            SettingsStatusDot(color: isMet ? SettingsTokens.ok : SettingsTokens.tertiaryText)
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
