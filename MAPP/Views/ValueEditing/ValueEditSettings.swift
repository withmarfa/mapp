import CoreGraphics

/// How a value is edited in a panel under it. The variants are for trying: step two keeps one and deletes the rest.
enum ValueEditVariant: String, CaseIterable {
    /// A panel of our own, drawn as the design library draws it.
    case designed = "Designed"
    /// The system's menu for a list of words, and its popover for a date, people or tags; nothing drawn by hand.
    case system = "System"
    /// The designed panel's shape and place on the system's glass, with a menu's row metrics.
    case blend = "Blend"
    /// The system's popover holding the designed panel's content for every kind.
    case popover = "Popover"
}

/// The numbers a value panel is built from. Debug builds read them from the Tuning panel as a panel opens, and
/// Release uses the constants.
struct ValueEditSettings: Equatable {
    var variant = ValueEditVariant.designed
    var panelRadius: CGFloat = 12
    var gap: CGFloat = 4
    var clearGlass = false
    var widthFloor: CGFloat = 220
    var widthCeiling: CGFloat = 320

    static var current: ValueEditSettings {
        #if DEBUG
        Tuning.shared.valueEditing
        #else
        ValueEditSettings()
        #endif
    }
}

/// What a row of a list is drawn with, which is the one thing the designed and the blend panel differ in besides the
/// material.
struct ValueEditMetrics: Equatable {
    var rowHeight: CGFloat
    var rowRadius: CGFloat
    var padding: CGFloat
    var headerHeight: CGFloat
    var textSize: CGFloat
    /// Whether hover and the keyboard row both fill with the accent color, as a menu's do, rather than hover being a
    /// quiet fill and only the keyboard row accented.
    var hoverIsAccent: Bool

    /// The design library's `.m-option` and `.m-popover`: 28 point rows with 7 point corners, 6 points of padding.
    static let designed = ValueEditMetrics(rowHeight: 28, rowRadius: 7, padding: 6, headerHeight: 24, textSize: 13, hoverIsAccent: false)

    /// A system menu as macOS 27 measures one: 24 point rows (an item, a section header) between 5 points of padding,
    /// set in the 13 point menu font. The corner radius of a row is read from how a menu draws it.
    static let menu = ValueEditMetrics(rowHeight: 24, rowRadius: 6, padding: 5, headerHeight: 24, textSize: 13, hoverIsAccent: true)
}

#if DEBUG
extension Tuning {
    /// The `Value Editing` group.
    enum ValueEditing {
        static let group = "Value Editing"
        static let variant = Knob.picker(group, "Variant", ValueEditSettings().variant)
        static let radius = Knob.slider(group, "Panel corner radius", ValueEditSettings().panelRadius, in: 6...26, step: 1)
        static let gap = Knob.slider(group, "Gap under the value", ValueEditSettings().gap, in: 0...12, step: 1)
        static let clear = Knob.toggle(group, "Clear glass (Blend)", ValueEditSettings().clearGlass)
        static let floor = Knob.slider(group, "Width floor", ValueEditSettings().widthFloor, in: 160...320, step: 10)
        static let ceiling = Knob.slider(group, "Width ceiling", ValueEditSettings().widthCeiling, in: 240...480, step: 10)

        static let knobs = [variant, radius, gap, clear, floor, ceiling]
    }

    /// The panel's settings with every knob's value applied; a change reaches the next panel that opens.
    var valueEditing: ValueEditSettings {
        var settings = ValueEditSettings()
        settings.variant = choice(ValueEditing.variant, as: ValueEditVariant.self) ?? settings.variant
        settings.panelRadius = number(ValueEditing.radius)
        settings.gap = number(ValueEditing.gap)
        settings.clearGlass = self[ValueEditing.clear] == .flag(true)
        settings.widthFloor = number(ValueEditing.floor)
        settings.widthCeiling = max(number(ValueEditing.ceiling), settings.widthFloor)
        return settings
    }
}
#endif
