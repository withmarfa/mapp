import SwiftUI

// The trailing controls of a row. Every one is the system's: bordered buttons, menu pop-ups, switches and rounded text fields,
// at the size the boards draw: 28 points tall, which the system calls large (22 inside a table, which it calls regular).

/// What a Settings button is for. `update` is the prominent one, filled with the accent; `destructive` is the system's
/// destructive role, which draws red text, and is never the default.
enum SettingsButtonRole { case normal, destructive, update }

/// A button at a row's trailing edge. A default action, made so with `keyboardShortcut(.defaultAction)`, takes the system's
/// default look.
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
            if role == .update {
                button.buttonStyle(.borderedProminent)
            } else {
                button.buttonStyle(.bordered)
            }
        }
        .controlSize(small ? .regular : .large)
        .tint(role == .destructive ? SettingsTokens.errorRed : nil)
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
        .fixedSize()
    }
}

extension View {
    /// The system's menu pop-up at Settings' one input size: 200 wide, and 28 tall, which the large control size draws.
    /// Without the flexible sizing the system pop-up fits its title instead of filling the width.
    func settingsPopUpSize() -> some View {
        controlSize(.large)
            .buttonSizing(.flexible)
            .frame(width: SettingsTokens.Metric.controlWidth)
    }
}

/// A pop-up of choices, as the system draws it, at the one width every pop-up of Settings has, so those of a page line
/// up in a column at the rows' trailing edge. `isError` puts the red ring round it.
struct SettingsPopUp<Value: Hashable, Content: View>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    var isError = false
    @ViewBuilder let content: Content

    var body: some View {
        Picker(title, selection: $selection) { content }
            .labelsHidden()
            .pickerStyle(.menu)
            .settingsPopUpSize()
            .settingsErrorRing(isError)
    }
}

/// A switch. The system draws it, and its label is the row's title for VoiceOver.
struct SettingsToggle: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
    }
}

/// A value read at a row's trailing edge, with a dot before it where the value is a state.
struct SettingsValue: View {
    private let text: Text
    private let dot: Color?

    init(_ text: LocalizedStringKey, dot: Color? = nil) {
        self.text = Text(text)
        self.dot = dot
    }

    init(verbatim text: String, dot: Color? = nil) {
        self.text = Text(verbatim: text)
        self.dot = dot
    }

    var body: some View {
        HStack(spacing: SettingsTokens.Metric.dotGap) {
            if let dot { SettingsStatusDot(color: dot) }
            text
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
            SettingsValue(verbatim: text)
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

/// A text field, 200 wide. The system draws the field, at its own height; `isError` puts the red ring round it.
struct SettingsField: View {
    let title: LocalizedStringKey
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
    @FocusState private var isFocused: Bool
    @Environment(\.settingsTextScale) private var scale

    var body: some View {
        Group {
            if isSecure {
                SecureField(title, text: $text, prompt: Text(verbatim: prompt ?? ""))
            } else {
                TextField(title, text: $text, prompt: Text(verbatim: prompt ?? ""))
            }
        }
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .controlSize(.large)
        .font(isMonospaced ? SettingsTokens.font(.mono, scale: scale) : nil)
        .autocorrectionDisabled()
        .focused($isFocused)
        .onSubmit(onSubmit)
        .onChange(of: isFocused) { if !$1 { onEndEditing?() } }
        .frame(width: width)
        .settingsErrorRing(isError)
    }
}

/// A value shown in a field's place that can be selected and copied but not changed, such as a key shown once. It is
/// at least as tall as a field and as wide as the space it is given. It wraps onto as many lines as it needs, so every
/// character of a value that is shown once is shown.
struct SettingsReadOnlyValue: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .settingsFont(.mono)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: SettingsTokens.Metric.controlHeight, alignment: .leading)
            .background(SettingsTokens.field, in: .rect(cornerRadius: SettingsTokens.Metric.controlRadius))
            .overlay { RoundedRectangle(cornerRadius: SettingsTokens.Metric.controlRadius).strokeBorder(SettingsTokens.hairline) }
    }
}

/// A number: a field with its unit inside at the trailing edge, never minus and plus.
struct SettingsNumberField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let unit: LocalizedStringKey
    var prompt: String?
    var isError = false
    var onSubmit: () -> Void = {}
    var onEndEditing: (() -> Void)?
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(title, text: $text, prompt: Text(verbatim: prompt ?? ""))
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
            .autocorrectionDisabled()
            .focused($isFocused)
            .onSubmit(onSubmit)
            .onChange(of: isFocused) { if !$1 { onEndEditing?() } }
            .padding(.trailing, 0)
            .overlay(alignment: .trailing) {
                Text(unit)
                    .settingsFont(.title)
                    .foregroundStyle(SettingsTokens.secondaryText)
                    .padding(.trailing, 8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(width: SettingsTokens.Metric.controlWidth)
            .settingsErrorRing(isError)
    }
}

/// A slider with a small and a large "A" at its ends, 200 wide, for a size. It draws ticks only when it has a `step`, one
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
