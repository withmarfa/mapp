import SwiftUI

/// The Appearance page: text, panels, the toolbar, where each column starts and how dates read, as the parts draw them.
struct AppearancePage: View {
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize
    @AppStorage(InterfaceKey.valuePanelStyle) private var panelStyle = ValuePanelStyle.standard
    @AppStorage(InterfaceKey.paletteMaterial) private var paletteMaterial = PaletteMaterial.standard
    @AppStorage(InterfaceKey.showsScrolledTitle) private var showsTitle = true
    @AppStorage(InterfaceKey.showsPageToolbarBackground) private var showsBackground = true
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    private var registry = ColumnWidthRegistry.shared

    var body: some View {
        SettingsPageColumn {
            SettingsSection("Text", footer: "Changes text in the sidebar, lists, and controls. Text size on item pages is set in Editor.") {
                SettingsRow("Base Text Size") {
                    SettingsPopUp(title: "Base Text Size", selection: $textSize) {
                        ForEach(InterfaceStyle.textSizes, id: \.self) { Text("\($0) pt").tag($0) }
                    }
                    .accessibilityIdentifier("InterfaceTextSize")
                }
            }
            SettingsSection(
                "Panels",
                footer: "Glass lets what is behind a panel show through, and Solid is the window’s own color. Palettes also offer Translucent, the system’s popover material."
            ) {
                SettingsRow("Value Panels", line: "Open under a date, status, or tag.") {
                    SettingsPopUp(title: "Value Panels", selection: $panelStyle) {
                        Text("Glass").tag(ValuePanelStyle.glass)
                        Text("Solid").tag(ValuePanelStyle.solid)
                    }
                    .accessibilityIdentifier("ValuePanelStyle")
                }
                SettingsRow("Palettes", line: "Command palette, Search Items, and New Item.") {
                    SettingsPopUp(title: "Palettes", selection: $paletteMaterial) {
                        Text("Glass").tag(PaletteMaterial.glass)
                        Text("Translucent").tag(PaletteMaterial.translucent)
                        Text("Solid").tag(PaletteMaterial.solid)
                    }
                    .accessibilityIdentifier("PaletteMaterial")
                }
            }
            SettingsSection("Toolbar", footer: "For item pages. Lists always keep their background.") {
                SettingsRow("Show Title When Scrolling") {
                    SettingsToggle(title: "Show Title When Scrolling", isOn: $showsTitle).accessibilityIdentifier("ToolbarScrolledTitle")
                }
                SettingsRow("Show Toolbar Background When Scrolling") {
                    SettingsToggle(title: "Show Toolbar Background When Scrolling", isOn: $showsBackground)
                        .accessibilityIdentifier("ToolbarPageBackground")
                }
            }
            SettingsSection(
                "Default Column Widths",
                footer: "Where each column starts in a new window. Dragging a column to a new width changes only that window."
            ) {
                ForEach(ColumnWidth.allCases) { ColumnWidthRow(column: $0) }
                SettingsRow("From This Window", line: "Or back to \(ColumnWidth.allCases.map { Int($0.defaultWidth).formatted() }.formatted(.list(type: .and))).") {
                    HStack(spacing: 8) {
                        SettingsButton("Reset Widths") {
                            for column in ColumnWidth.allCases { UserDefaults.standard.removeObject(forKey: column.key) }
                        }
                        .accessibilityIdentifier("ColumnWidthsReset")
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
                }
            }
            SettingsSection(
                "Dates",
                footer: "Automatic uses words in lists and tables, such as “Yesterday”, and abbreviated dates elsewhere. Times follow your Mac’s 12 or 24 hour setting."
            ) {
                SettingsRow("Date Format") {
                    SettingsPopUp(title: "Date Format", selection: $dateFormat) {
                        ForEach(DateFormat.allCases) { option in
                            switch option {
                            case .automatic: Text("Automatic").tag(option)
                            case .relative: Text("Relative").tag(option)
                            case .short: Text("Short").tag(option)
                            case .long: Text("Long").tag(option)
                            }
                        }
                    }
                    .accessibilityIdentifier("DateFormat")
                }
            }
        }
        .accessibilityIdentifier("AppearancePage")
    }
}

/// One column's default width, a field with its unit inside. A width outside what the column allows is brought inside it.
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
        SettingsRow(title, line: "\(Int(column.range.lowerBound)) to \(Int(column.range.upperBound)) points") {
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
