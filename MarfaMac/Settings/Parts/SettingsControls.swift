import SwiftUI

extension EnvironmentValues {
    @Entry var settingsCompactControls = false
    @Entry var settingsUsesSheetControls = false
}

private struct SettingsControlSize: ViewModifier {
    var small: Bool
    @Environment(\.settingsCompactControls) private var compact
    @Environment(\.settingsTextScale) private var scale

    func body(content: Content) -> some View {
        let usesSmall = (small || compact) && scale < SettingsTokens.Metric.controlScaleForLarge
        content.controlSize(usesSmall ? .regular : .large)

            .frame(minHeight: usesSmall ? SettingsTokens.Metric.smallControlHeight : nil)
    }
}

extension View {
    func settingsControlSize(small: Bool = false) -> some View { modifier(SettingsControlSize(small: small)) }
}

/// What a Settings button is for. `confirm` is a sheet's or a dialog's one main action: the accent fill and Return, so a
/// page cannot leave it gray. `update` is the accent fill without Return. `destructive` is a pale red fill with red text, the
/// destructive role, and never the default, so Return never takes it.
enum SettingsButtonRole { case normal, destructive, confirm, update }

/// A button at a row's trailing edge, a table's cell or a sheet's foot.
struct SettingsButton: View {
    private let title: Text
    private let role: SettingsButtonRole
    private let small: Bool
    /// A longer title the button keeps room for, so it does not change width as its title changes (Check for Updates while it reads
    /// Checking…).
    private let reserved: Text?
    private let action: () -> Void

    init(
        _ title: LocalizedStringKey, role: SettingsButtonRole = .normal, small: Bool = false, reserving reserved: LocalizedStringKey? = nil,
        action: @escaping () -> Void
    ) {
        self.title = Text(title)
        self.role = role
        self.small = small
        self.reserved = reserved.map { Text($0) }
        self.action = action
    }

    init(title: Text, role: SettingsButtonRole = .normal, small: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.small = small
        self.reserved = nil
        self.action = action
    }

    init(verbatim title: String, role: SettingsButtonRole = .normal, small: Bool = false, action: @escaping () -> Void) {
        self.title = Text(verbatim: title)
        self.role = role
        self.small = small
        self.reserved = nil
        self.action = action
    }

    var body: some View {
        Group {
            switch role {
            case .confirm, .update: button.buttonStyle(.borderedProminent)
            case .destructive: button.buttonStyle(.bordered).foregroundStyle(SettingsTokens.errorRed)
            case .normal: button.buttonStyle(.bordered)
            }
        }
        .settingsControlSize(small: small)
        .keyboardShortcut(role == .confirm ? .defaultAction : nil)
    }

    private var button: some View {
        Button(role: role == .destructive ? .destructive : nil, action: action) {
            ZStack {
                if let reserved { reserved.hidden() }
                title
            }
        }
    }
}

/// A row's "more actions" menu: the system's borderless pull-down with three dots, with no fill, as Finder and System
/// Settings draw it.
struct SettingsMoreMenu<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Menu {
            content
        } label: {
            Label("More", systemImage: "ellipsis").labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .settingsControlSize(small: true)
        .fixedSize()
    }
}

/// A system pop-up at the row's trailing edge, with room for its choices. `isError` puts the red ring round it.
struct SettingsPopUp<Value: Hashable, Content: View>: View {
    private let title: Text
    private let currentValueLabel: Text?
    @Binding var selection: Value
    var isError = false
    @ViewBuilder let content: Content
    @Environment(\.settingsCompactControls) private var compact
    @Environment(\.settingsTextScale) private var scale

    init(
        title: LocalizedStringKey, selection: Binding<Value>, isError: Bool = false,
        currentValueLabel: Text? = nil, @ViewBuilder content: () -> Content
    ) {
        self.init(label: Text(title), selection: selection, isError: isError, currentValueLabel: currentValueLabel, content: content)
    }

    /// For a title the server or a plugin wrote, which is never looked up as a key.
    init(verbatim title: String, selection: Binding<Value>, isError: Bool = false, @ViewBuilder content: () -> Content) {
        self.init(label: Text(verbatim: title), selection: selection, isError: isError, content: content)
    }

    private init(
        label: Text, selection: Binding<Value>, isError: Bool, currentValueLabel: Text? = nil,
        @ViewBuilder content: () -> Content
    ) {
        title = label
        _selection = selection
        self.isError = isError
        self.currentValueLabel = currentValueLabel
        self.content = content()
    }

    var body: some View {
        let width = compact ? SettingsTokens.Metric.popUpMinimumWidth * max(1, scale) : SettingsTokens.Metric.controlWidth
        Group {
            if let currentValueLabel {
                Picker(selection: $selection) { content } label: { title } currentValueLabel: {
                    currentValueLabel.lineLimit(1).truncationMode(.middle)
                }
            } else {
                Picker(selection: $selection) { content } label: { title }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .settingsControlSize()
        .buttonSizing(.flexible)
        .frame(minWidth: width, maxWidth: currentValueLabel == nil ? nil : width)
        .fixedSize(horizontal: currentValueLabel == nil, vertical: false)
        .settingsErrorRing(isError)
    }
}

/// A switch. The system draws it, and its label is the row's title for VoiceOver.
struct SettingsToggle: View {
    private let title: Text
    @Binding var isOn: Bool

    init(title: LocalizedStringKey, isOn: Binding<Bool>) {
        self.title = Text(title)
        _isOn = isOn
    }

    /// For a title the server or a plugin wrote, which is never looked up as a key.
    init(verbatim title: String, isOn: Binding<Bool>) {
        self.title = Text(verbatim: title)
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) { title }
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
    }
}

/// A value read at a row's trailing edge, with a dot before it where the value is a state.
struct SettingsValue: View {
    private let text: Text
    private let dot: Color?
    private let glyph: SettingsTextGlyph?

    init(_ text: LocalizedStringKey, dot: Color? = nil, glyph: SettingsTextGlyph? = nil) {
        self.init(text: Text(text), dot: dot, glyph: glyph)
    }

    init(verbatim text: String, dot: Color? = nil, glyph: SettingsTextGlyph? = nil) {
        self.init(text: Text(verbatim: text), dot: dot, glyph: glyph)
    }

    init(text: Text, dot: Color? = nil, glyph: SettingsTextGlyph? = nil) {
        self.text = text
        self.dot = dot
        self.glyph = glyph
    }

    var body: some View {
        HStack(spacing: SettingsTokens.Metric.lockGap) {
            if let dot { SettingsStatusDot(color: dot) }
            text.withSettingsGlyph(glyph)
                .settingsFont(.title)
                .foregroundStyle(SettingsTokens.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

/// The small dot before a value or a status line: its color says how it stands.
struct SettingsStatusDot: View {
    let color: Color

    var body: some View {
        Circle().fill(color).frame(width: SettingsTokens.Metric.statusDot, height: SettingsTokens.Metric.statusDot).accessibilityHidden(true)
    }
}

/// A value that is set elsewhere and can't be changed here, with a small lock before it, such as a key's source.
struct SettingsLockedValue: View {
    let text: String

    var body: some View {
        HStack(spacing: SettingsTokens.Metric.dotGap) {
            Image(systemName: "lock").font(.system(size: SettingsTokens.Metric.lockGlyph)).foregroundStyle(SettingsTokens.tertiaryText).accessibilityHidden(true)
            Text(verbatim: text).settingsFont(.small).foregroundStyle(SettingsTokens.secondaryText)
        }
    }
}

/// The chevron at the trailing edge of a row that opens a page of its own.
struct SettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(SettingsTokens.tertiaryText)
            .accessibilityHidden(true)
    }
}

extension View {
    /// The red ring of a refused input. The line that says why is the row's `error`.
    func settingsErrorRing(_ isError: Bool) -> some View {
        overlay {
            if isError {
                RoundedRectangle(cornerRadius: SettingsTokens.Metric.controlRadius, style: .continuous)
                    .strokeBorder(SettingsTokens.errorRed, lineWidth: 1.5)
                    .padding(-0.5)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// A text field, 160 wide. The system draws the field, at its own height; `isError` puts the red ring round it.
struct SettingsField: View {
    private let title: Text
    @Binding var text: String
    /// A hint that says something the label does not. With none, the field is empty: the label is never repeated in it.
    var prompt: String?
    var isError = false
    var isSecure = false
    var isMonospaced = false
    var width: CGFloat? = SettingsTokens.Metric.controlWidth
    var onSubmit: () -> Void = {}
    /// Run when the field loses focus, so a value typed and left is kept as one that was submitted.
    var onEndEditing: (() -> Void)?
    var onCancel: (() -> Void)?
    @FocusState private var isFocused: Bool
    @State private var cancelMonitor = SettingsKeyMonitor()
    @State private var cancelAnchor = NSView()
    @Environment(\.settingsTextScale) private var scale

    init(
        title: LocalizedStringKey, text: Binding<String>, prompt: String? = nil, isError: Bool = false, isSecure: Bool = false,
        isMonospaced: Bool = false, width: CGFloat? = SettingsTokens.Metric.controlWidth, onSubmit: @escaping () -> Void = {},
        onEndEditing: (() -> Void)? = nil, onCancel: (() -> Void)? = nil
    ) {
        self.init(
            label: Text(title), text: text, prompt: prompt, isError: isError, isSecure: isSecure, isMonospaced: isMonospaced, width: width,
            onSubmit: onSubmit, onEndEditing: onEndEditing, onCancel: onCancel)
    }

    /// For a title the server or a plugin wrote, which is never looked up as a key.
    init(
        verbatim title: String, text: Binding<String>, prompt: String? = nil, isError: Bool = false, isSecure: Bool = false,
        isMonospaced: Bool = false, width: CGFloat? = SettingsTokens.Metric.controlWidth, onSubmit: @escaping () -> Void = {},
        onEndEditing: (() -> Void)? = nil
    ) {
        self.init(
            label: Text(verbatim: title), text: text, prompt: prompt, isError: isError, isSecure: isSecure, isMonospaced: isMonospaced,
            width: width, onSubmit: onSubmit, onEndEditing: onEndEditing)
    }

    private init(
        label: Text, text: Binding<String>, prompt: String?, isError: Bool, isSecure: Bool, isMonospaced: Bool, width: CGFloat?,
        onSubmit: @escaping () -> Void, onEndEditing: (() -> Void)?, onCancel: (() -> Void)? = nil
    ) {
        title = label
        _text = text
        self.prompt = prompt
        self.isError = isError
        self.isSecure = isSecure
        self.isMonospaced = isMonospaced
        self.width = width
        self.onSubmit = onSubmit
        self.onEndEditing = onEndEditing
        self.onCancel = onCancel
    }

    var body: some View {
        Group {
            if isSecure {
                SecureField(text: $text, prompt: Text(verbatim: prompt ?? "")) { title }
            } else {
                TextField(text: $text, prompt: Text(verbatim: prompt ?? "")) { title }
            }
        }
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .settingsControlSize()
        .font(isMonospaced ? SettingsTokens.font(.mono, scale: scale) : nil)
        .autocorrectionDisabled()
        .focused($isFocused)
        .appFocusRing(isFocused: isFocused)
        .onSubmit(onSubmit)
        .onChange(of: isFocused) { _, focused in
            if focused, let onCancel {
                let anchor = cancelAnchor
                cancelMonitor.start { [weak anchor] event in
                    guard let window = anchor?.window, event.windowNumber == window.windowNumber, event.isEscape else { return false }
                    onCancel()
                    return true
                }
            } else if !focused {
                cancelMonitor.stop()
                onEndEditing?()
            }
        }
        .onDisappear { cancelMonitor.stop() }
        .background {
            if onCancel != nil { CancelAnchor(view: cancelAnchor).allowsHitTesting(false) }
        }
        .frame(width: width)
        .settingsErrorRing(isError)
    }

    private struct CancelAnchor: NSViewRepresentable {
        let view: NSView

        func makeNSView(context: Context) -> NSView { view }
        func updateNSView(_ view: NSView, context: Context) {}
    }
}

/// A read-only value shown in a field's place. The text is selectable by default and wraps unless the caller sets a line limit.
struct SettingsReadOnlyValue: View {
    let text: String
    /// False for a value that leaves only through its own button, such as a command that holds a key.
    var isSelectable = true

    var body: some View {
        selectable(Text(verbatim: text).settingsFont(.mono))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: SettingsTokens.Metric.controlHeight, alignment: .leading)
            .background(SettingsTokens.field, in: .rect(cornerRadius: SettingsTokens.Metric.controlRadius))
            .overlay { RoundedRectangle(cornerRadius: SettingsTokens.Metric.controlRadius).strokeBorder(SettingsTokens.hairline) }
    }

    @ViewBuilder private func selectable(_ text: some View) -> some View {
        if isSelectable { text.textSelection(.enabled) } else { text.textSelection(.disabled) }
    }
}

/// A number: a narrow field with its unit after it, never inside it and never minus and plus. A number with no unit takes the
/// row-end width.
struct SettingsNumberField: View {
    private let title: Text
    @Binding var text: String
    /// What the number counts, shown after the field; nil where the server names none.
    let unit: LocalizedStringKey?
    var prompt: String?
    var isError = false
    var onSubmit: () -> Void = {}
    var onEndEditing: (() -> Void)?
    @FocusState private var isFocused: Bool
    @Environment(\.settingsCompactControls) private var compact
    @Environment(\.settingsTextScale) private var scale

    init(
        title: LocalizedStringKey, text: Binding<String>, unit: LocalizedStringKey?, prompt: String? = nil, isError: Bool = false,
        onSubmit: @escaping () -> Void = {}, onEndEditing: (() -> Void)? = nil
    ) {
        self.init(label: Text(title), text: text, unit: unit, prompt: prompt, isError: isError, onSubmit: onSubmit, onEndEditing: onEndEditing)
    }

    /// For a title the server or a plugin wrote, which is never looked up as a key.
    init(
        verbatim title: String, text: Binding<String>, unit: LocalizedStringKey?, prompt: String? = nil, isError: Bool = false,
        onSubmit: @escaping () -> Void = {}, onEndEditing: (() -> Void)? = nil
    ) {
        self.init(
            label: Text(verbatim: title), text: text, unit: unit, prompt: prompt, isError: isError, onSubmit: onSubmit,
            onEndEditing: onEndEditing)
    }

    private init(
        label: Text, text: Binding<String>, unit: LocalizedStringKey?, prompt: String?, isError: Bool, onSubmit: @escaping () -> Void,
        onEndEditing: (() -> Void)?
    ) {
        title = label
        _text = text
        self.unit = unit
        self.prompt = prompt
        self.isError = isError
        self.onSubmit = onSubmit
        self.onEndEditing = onEndEditing
    }

    private var fieldWidth: CGFloat {
        if unit == nil { return SettingsTokens.Metric.controlWidth }
        return compact ? SettingsTokens.Metric.smallNumberWidth * max(1, scale) : SettingsTokens.Metric.numberWidth
    }

    var body: some View {
        HStack(spacing: SettingsTokens.Metric.buttonGap) {
            TextField(text: $text, prompt: Text(verbatim: prompt ?? "")) { title }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .settingsControlSize()
                .multilineTextAlignment(unit == nil ? .leading : .trailing)
                .autocorrectionDisabled()
                .focused($isFocused)
                .appFocusRing(isFocused: isFocused)
                .onSubmit(onSubmit)
                .onChange(of: isFocused) { if !$1 { onEndEditing?() } }
                .frame(width: fieldWidth)
                .settingsErrorRing(isError)
            if let unit {
                Text(unit)
                    .settingsFont(.title)
                    .foregroundStyle(SettingsTokens.secondaryText)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// A slider with a small and a large "A" at its ends, 160 wide, for a size. It draws ticks only when it has a `step`, one
/// at each of the few values it can take; a size that moves smoothly has none.
struct SettingsSizeSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?

    var body: some View {
        HStack(spacing: 8) {
            Text("A").settingsFont(.line).foregroundStyle(SettingsTokens.secondaryText).accessibilityHidden(true)
            slider
            Text("A").settingsFont(.largeGlyph).foregroundStyle(SettingsTokens.secondaryText).accessibilityHidden(true)
        }
        .frame(width: SettingsTokens.Metric.controlWidth)
    }

    @ViewBuilder private var slider: some View {
        if let step {
            Slider(value: $value, in: range, step: step) { Text(title) }.labelsHidden()
        } else {
            Slider(value: $value, in: range) { Text(title) }.labelsHidden()
        }
    }
}
