import SwiftUI

struct AppearancePage: View {
    @AppStorage(AppearanceKey.theme) private var theme = AppTheme.standard
    @AppStorage(AppearanceKey.accent) private var accent = AccentChoice.standard
    @AppStorage(AppearanceKey.highlights) private var highlight = HighlightChoice.standard
    @AppStorage(AppIconChoice.key) private var appIcon = AppIconChoice.sky
    @AppStorage(AppearanceKey.typeChipTint) private var typeChipTint = TypeChipTint.standard
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize
    @AppStorage(InterfaceKey.valuePanelStyle) private var panelStyle = ValuePanelStyle.standard
    @AppStorage(InterfaceKey.paletteMaterial) private var paletteMaterial = PaletteMaterial.standard
    @AppStorage(InterfaceKey.showsScrolledTitle) private var showsTitle = true
    @AppStorage(InterfaceKey.showsPageToolbarBackground) private var showsBackground = true
    @AppStorage(InterfaceKey.showsSidebarHistory) private var showsHistory = true
    @AppStorage(SidebarTypeRow.subtypeIconsKey) private var showsSubtypeIcons = true
    @AppStorage(SidebarColor.key) private var sidebarColor = SidebarColor.gray
    private var registry = ColumnWidthRegistry.shared

    /// Gray is the default, so choosing it stores nothing.
    private var storedSidebarColor: Binding<SidebarColor> {
        Binding {
            sidebarColor
        } set: { color in
            if color == .gray { UserDefaults.standard.removeObject(forKey: SidebarColor.key) } else { sidebarColor = color }
        }
    }

    var body: some View {
        SettingsPageColumn {
            SettingsSection("Theme") {
                ChoiceTiles(
                    choices: [
                        .init(value: .system, title: Text("System"), picture: AnyView(SettingsSystemThemePicture())),
                        .init(value: .light, title: Text("Light"), picture: AnyView(SettingsThemePicture(look: .light))),
                        .init(value: .dark, title: Text("Dark"), picture: AnyView(SettingsThemePicture(look: .dark))),
                    ],
                    selection: $theme)
                    .accessibilityIdentifier("Theme")
            }
            color
            SettingsSection("Size") {
                SettingsRow("Interface text size") {
                    SettingsPopUp(title: "Interface text size", selection: $textSize) {
                        ForEach(InterfaceStyle.textSizes, id: \.self) { Text("\($0) pt").tag($0) }
                    }
                    .accessibilityIdentifier("InterfaceTextSize")
                }
            }
            SettingsSection("Materials") {
                SettingsRow("Value panels", line: "Behind a date, a status or a tag you change.") {
                    SettingsPopUp(title: "Value panels", selection: $panelStyle) {
                        Text("Glass").tag(ValuePanelStyle.glass)
                        Text("Solid").tag(ValuePanelStyle.solid)
                    }
                    .accessibilityIdentifier("ValuePanelStyle")
                }
                SettingsRow("Palettes", line: "Command Palette, Search Items and New Item.") {
                    SettingsPopUp(title: "Palettes", selection: $paletteMaterial) {
                        Text("Glass").tag(PaletteMaterial.glass)
                        Text("Translucent").tag(PaletteMaterial.translucent)
                        Text("Solid").tag(PaletteMaterial.solid)
                    }
                    .accessibilityIdentifier("PaletteMaterial")
                }
            }
            SettingsSection("Window") {
                SettingsRow("Sidebar color") {
                    SettingsPopUp(title: "Sidebar color", selection: storedSidebarColor) {
                        ForEach(SidebarColor.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("SidebarColor")
                }
                SettingsRow("Back and forward over the sidebar") {
                    SettingsToggle(title: "Back and forward over the sidebar", isOn: $showsHistory).accessibilityIdentifier("SidebarHistoryToggle")
                }
                SettingsRow("Show item title when scrolling") {
                    SettingsToggle(title: "Show item title when scrolling", isOn: $showsTitle).accessibilityIdentifier("ToolbarScrolledTitle")
                }
                SettingsRow("Toolbar background when scrolling") {
                    SettingsToggle(title: "Toolbar background when scrolling", isOn: $showsBackground)
                        .accessibilityIdentifier("ToolbarPageBackground")
                }
                SettingsRow("Symbols on subtypes in the sidebar") {
                    SettingsToggle(title: "Symbols on subtypes in the sidebar", isOn: $showsSubtypeIcons).accessibilityIdentifier("SubtypeSymbols")
                }
            }
            layout
        }
        .accessibilityIdentifier("AppearancePage")
    }

    // MARK: Color

    private var color: some View {
        SettingsSection("Color") {
            SettingsRow("Accent") {
                SettingsSwatches(
                    swatches: [.init(value: .system, color: SettingsTokens.systemAccent, title: Text("System"))]
                        + AccentChoice.Offered.swatched.map { offered in
                            .init(value: .offered(offered), color: Color(nsColor: offered.nsColor), title: Text(verbatim: Self.name(of: offered)))
                        },
                    selection: $accent,
                    custom: (
                        isSelected: { if case .custom = accent { true } else { false } }(),
                        color: Binding { accent.color ?? SettingsTokens.systemAccent } set: { accent = .custom($0) }),
                    title: "Accent"
                )
                .accessibilityIdentifier("Accent")
            }
            SettingsRow("App icon", line: "In the Dock.") {
                SettingsIconChoices(
                    choices: AppIconChoice.allCases.map {
                        .init(value: $0, asset: $0.previewAsset, title: Text($0.title))
                    },
                    selection: Binding { appIcon } set: { $0.store() },
                    title: "App icon"
                )
                .accessibilityIdentifier("AppIcon")
            }
            SettingsRow("Highlight color") {
                SettingsPopUp(title: "Highlight color", selection: $highlight) {
                    Text("Yellow").tag(HighlightChoice.yellow)
                    Text("Orange").tag(HighlightChoice.orange)
                    Text("Green").tag(HighlightChoice.green)
                    Text("Blue").tag(HighlightChoice.blue)
                    Text("Pink").tag(HighlightChoice.pink)
                    Text("Purple").tag(HighlightChoice.purple)
                    Divider()
                    Text("Accent").tag(HighlightChoice.accent)
                }
                .accessibilityIdentifier("Highlights")
            }
            SettingsRow("Type chip color") {
                SettingsPopUp(title: "Type chip color", selection: $typeChipTint) {
                    Text("Tinted").tag(TypeChipTint.tinted)
                    Text("Gray").tag(TypeChipTint.gray)
                }
                .accessibilityIdentifier("TypeChipTint")
            }
        }
    }

    private static func name(of offered: AccentChoice.Offered) -> String {
        switch offered {
        case .blue: String(localized: "Blue")
        case .purple: String(localized: "Purple")
        case .pink: String(localized: "Pink")
        case .red: String(localized: "Red")
        case .orange: String(localized: "Orange")
        case .yellow: String(localized: "Yellow")
        case .green: String(localized: "Green")
        case .graphite: String(localized: "Graphite")
        }
    }

    // MARK: Window layout

    private var layout: some View {
        SettingsSection("Window Layout", footer: "New windows open at these widths.") {
            ForEach(ColumnWidth.allCases) { ColumnWidthRow(column: $0) }
            SettingsRow("From the front window") {
                SettingsButton("Use Current Widths") {
                    guard let front = registry.front else { return }
                    for column in ColumnWidth.allCases {
                        UserDefaults.standard.set(Double(column.resolved(Double(front.width(of: column)))), forKey: column.key)
                    }
                }
                .disabled(registry.front == nil)
                .help(registry.front == nil ? "Open a window to use its column widths." : "Make the front window’s widths the defaults for new windows.")
                .accessibilityIdentifier("ColumnWidthsUseCurrent")
            }
            SettingsRow("Default widths", line: "\(Int(ColumnWidth.sidebar.defaultWidth)) and \(Int(ColumnWidth.list.defaultWidth)) pt.") {
                SettingsButton("Reset") {
                    for column in ColumnWidth.allCases { UserDefaults.standard.removeObject(forKey: column.key) }
                }
                .accessibilityIdentifier("ColumnWidthsReset")
            }
        }
    }
}

/// One column's default width, clamped to the range it allows.
private struct ColumnWidthRow: View {
    let column: ColumnWidth
    @AppStorage private var stored: Double
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.settingsTextScale) private var scale

    init(column: ColumnWidth) {
        self.column = column
        _stored = AppStorage(wrappedValue: Double(column.defaultWidth), column.key)
    }

    private var title: LocalizedStringKey {
        switch column {
        case .sidebar: "Sidebar width"
        case .list: "List width"
        }
    }

    private var width: Double { Double(column.resolved(stored)) }

    var body: some View {
        SettingsRow(title) {
            SettingsNumberField(title: title, text: $text, unit: "pt", onSubmit: commit)
                // The native rounded field clips larger type in dark mode.
                .font(SettingsTokens.font(.title, scale: min(scale, SettingsTokens.Metric.controlScaleForLarge)))
                .focused($focused)
                .onAppear { text = String(Int(width)) }
                .onChange(of: stored) { if !focused { text = String(Int(width)) } }
                .onChange(of: focused) { if !focused { commit() } }
        }
        .accessibilityIdentifier("ColumnWidth-\(column.rawValue)")
    }

    private func commit() {
        if let typed = Double(text.trimmingCharacters(in: .whitespaces)) { stored = Double(column.resolved(typed)) }
        text = String(Int(width))
    }
}
