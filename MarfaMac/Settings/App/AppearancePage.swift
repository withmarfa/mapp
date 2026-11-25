import SwiftUI

/// The Appearance page: the theme, the colors, the fonts of an item's text, the materials the panels are made of, the
/// window's toolbar and where each column starts.
struct AppearancePage: View {
    @AppStorage(AppearanceKey.theme) private var theme = AppTheme.standard
    @AppStorage(AppearanceKey.accent) private var accent = AccentChoice.standard
    @AppStorage(AppearanceKey.highlights) private var highlight = HighlightChoice.standard
    @AppStorage(AppearanceKey.textFont) private var textFont = ""
    @AppStorage(AppearanceKey.codeFont) private var codeFont = ""
    @AppStorage(AppearanceKey.typeChipTint) private var typeChipTint = TypeChipTint.standard
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize
    @AppStorage(InterfaceKey.valuePanelStyle) private var panelStyle = ValuePanelStyle.standard
    @AppStorage(InterfaceKey.paletteMaterial) private var paletteMaterial = PaletteMaterial.standard
    @AppStorage(InterfaceKey.showsScrolledTitle) private var showsTitle = true
    @AppStorage(InterfaceKey.showsPageToolbarBackground) private var showsBackground = true
    @AppStorage(InterfaceKey.showsSidebarHistory) private var showsHistory = true
    @AppStorage(SidebarTypeRow.subtypeIconsKey) private var showsSubtypeIcons = true
    @AppStorage(SidebarColor.key) private var sidebarColor = SidebarColor.gray
    /// Read when the page has appeared, since asking the system for every installed font is slow.
    @State private var families: [String] = []
    @State private var monospacedFamilies: [String] = []
    @State private var hasListedFonts = false
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
            SettingsSection("Text") {
                SettingsRow("Text Size", line: "The sidebar, lists and controls.") {
                    SettingsPopUp(title: "Text Size", selection: $textSize) {
                        ForEach(InterfaceStyle.textSizes, id: \.self) { Text("\($0) pt").tag($0) }
                    }
                    .accessibilityIdentifier("InterfaceTextSize")
                }
            }
            fonts
            SettingsSection("Materials") {
                SettingsRow("Value Panels", line: "Behind a date, a status or a tag you change.") {
                    SettingsPopUp(title: "Value Panels", selection: $panelStyle) {
                        Text("Glass").tag(ValuePanelStyle.glass)
                        Text("Solid").tag(ValuePanelStyle.solid)
                    }
                    .accessibilityIdentifier("ValuePanelStyle")
                }
                SettingsRow("Palettes", line: "Command Palette, Search Items and Quick Add.") {
                    SettingsPopUp(title: "Palettes", selection: $paletteMaterial) {
                        Text("Glass").tag(PaletteMaterial.glass)
                        Text("Translucent").tag(PaletteMaterial.translucent)
                        Text("Solid").tag(PaletteMaterial.solid)
                    }
                    .accessibilityIdentifier("PaletteMaterial")
                }
            }
            SettingsSection("Window") {
                SettingsRow("Sidebar", line: "Gray, or white behind a hairline.") {
                    SettingsPopUp(title: "Sidebar", selection: storedSidebarColor) {
                        ForEach(SidebarColor.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("SidebarColor")
                }
                SettingsRow("Back and Forward", line: "Over the sidebar.") {
                    SettingsToggle(title: "Back and Forward", isOn: $showsHistory).accessibilityIdentifier("SidebarHistoryToggle")
                }
                SettingsRow("Title When Scrolling", line: "On an item’s page.") {
                    SettingsToggle(title: "Title When Scrolling", isOn: $showsTitle).accessibilityIdentifier("ToolbarScrolledTitle")
                }
                SettingsRow("Toolbar Background When Scrolling") {
                    SettingsToggle(title: "Toolbar Background When Scrolling", isOn: $showsBackground)
                        .accessibilityIdentifier("ToolbarPageBackground")
                }
                SettingsRow("Symbols on Subtypes", line: "In the sidebar.") {
                    SettingsToggle(title: "Symbols on Subtypes", isOn: $showsSubtypeIcons).accessibilityIdentifier("SubtypeSymbols")
                }
            }
            layout
        }
        .accessibilityIdentifier("AppearancePage")
        .task {
            guard !hasListedFonts else { return }
            families = FontChoice.installedFamilies()
            monospacedFamilies = FontChoice.installedMonospacedFamilies()
            hasListedFonts = true
        }
    }

    // MARK: Color

    private var color: some View {
        SettingsSection("Color") {
            SettingsRow("Accent", line: "Switches, sliders and the text cursor.") {
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
            SettingsRow("Highlights", line: "Behind highlighted text.") {
                SettingsPopUp(title: "Highlights", selection: $highlight) {
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
            SettingsRow("Type Chips", line: "The type you give an item.") {
                SettingsPopUp(title: "Type Chips", selection: $typeChipTint) {
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

    // MARK: Fonts

    private var fonts: some View {
        SettingsSection("Fonts", line: "The rest of the app uses the system font.") {
            SettingsRow("Text Font", line: "An item’s text.") {
                fontPopUp("Text Font", selection: $textFont, defaultName: String(localized: "System"), installed: families)
                    .accessibilityIdentifier("TextFont")
            }
            SettingsRow("Code Font", line: "Code and Markdown marks.") {
                fontPopUp("Code Font", selection: $codeFont, defaultName: "SF Mono", installed: monospacedFamilies)
                    .accessibilityIdentifier("CodeFont")
            }
        }
    }

    /// A pop-up of the installed families after the default. A family chosen once and not installed now is listed and said
    /// to be missing, while the page and the editor use the default.
    private func fontPopUp(_ title: LocalizedStringKey, selection: Binding<String>, defaultName: String, installed: [String]) -> some View {
        SettingsPopUp(title: title, selection: selection) {
            Text(verbatim: defaultName).tag("")
            Divider()
            ForEach(installed, id: \.self) { Text(verbatim: $0).tag($0) }
            if !selection.wrappedValue.isEmpty, !installed.contains(selection.wrappedValue) {
                Divider()
                // Until the installed fonts are listed, the chosen one cannot be said to be missing.
                Text(verbatim: hasListedFonts ? MissingChoice.label(selection.wrappedValue) : selection.wrappedValue)
                    .tag(selection.wrappedValue)
            }
        }
    }

    // MARK: Window layout

    private var layout: some View {
        SettingsSection("Window Layout", footer: "New windows open at these widths.") {
            ForEach(ColumnWidth.allCases) { ColumnWidthRow(column: $0) }
            SettingsRow("From This Window", line: "The widths this window has now.") {
                SettingsButton("Use Current Widths") {
                    guard let front = registry.front else { return }
                    for column in ColumnWidth.allCases {
                        UserDefaults.standard.set(Double(column.resolved(Double(front.width(of: column)))), forKey: column.key)
                    }
                }
                .disabled(registry.front == nil)
                .help(registry.front == nil ? "Open a window to use its column widths." : "Make the widths set in this window the defaults for new windows.")
                .accessibilityIdentifier("ColumnWidthsUseCurrent")
            }
            SettingsRow("Reset Widths", line: "Back to \(ColumnWidth.allCases.map { Int($0.defaultWidth).formatted() }.formatted(.list(type: .and))).") {
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

    init(column: ColumnWidth) {
        self.column = column
        _stored = AppStorage(wrappedValue: Double(column.defaultWidth), column.key)
    }

    private var title: LocalizedStringKey {
        switch column {
        case .sidebar: "Sidebar"
        case .list: "List"
        }
    }

    private var width: Double { Double(column.resolved(stored)) }

    var body: some View {
        SettingsRow(title) {
            SettingsNumberField(title: title, text: $text, unit: "pt", onSubmit: commit)
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
