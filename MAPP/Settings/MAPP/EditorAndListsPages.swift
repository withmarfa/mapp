import SwiftUI

/// The Editor page: how an item's page is laid out, its text, links and pictures.
struct EditorPage: View {
    @AppStorage(PageKey.fullWidth) private var fullWidth = PageStyle().fullWidth
    @AppStorage(PageKey.readingWidth) private var readingWidth = PageStyle().readingWidth
    @AppStorage(PageKey.titleLines) private var titleLines = TitleLines.standard
    @AppStorage(PageKey.textSize) private var textSize = PageStyle().textSize
    @AppStorage(PageKey.checksSpelling) private var checksSpelling = PageStyle().checksSpelling
    @AppStorage(PageKey.linkLook) private var linkLook = PageStyle().linkLook
    @AppStorage(RemotePictureSetting.key) private var pictures = RemotePictureSetting.standard

    var body: some View {
        SettingsPageColumn {
            SettingsSection("Page Layout") {
                SettingsRow("Page Width") {
                    SettingsPopUp(title: "Page Width", selection: $fullWidth) {
                        Text("Standard").tag(false)
                        Text("Full Width").tag(true)
                    }
                    .accessibilityIdentifier("PageWidth")
                }
                SettingsRow("Standard Width", line: "How wide Standard pages run. Full Width leaves it aside.", look: fullWidth ? .off : .normal) {
                    let range = PageStyle.readingWidths
                    SettingsSizeSlider(
                        title: "Standard Width",
                        value: Binding { Double(readingWidth) } set: { readingWidth = Int($0.rounded()) },
                        range: Double(range.lowerBound)...Double(range.upperBound)
                    )
                    .accessibilityLabel("Standard Width")
                    .accessibilityIdentifier("ReadingWidth")
                }
                SettingsRow("Title Length") {
                    SettingsPopUp(title: "Title Length", selection: Binding { TitleLines.resolved(titleLines) } set: { titleLines = $0 }) {
                        ForEach(TitleLines.choices, id: \.self) { Text("\($0) Lines").tag($0) }
                    }
                    .accessibilityIdentifier("TitleLines")
                }
            }
            SettingsSection("Text") {
                SettingsRow("Text Size") {
                    SettingsPopUp(title: "Text Size", selection: $textSize) {
                        ForEach(PageStyle.textSizes, id: \.self) { Text("\($0) pt").tag($0) }
                    }
                    .accessibilityIdentifier("TextSize")
                }
                SettingsRow("Check Spelling While Typing") {
                    SettingsToggle(title: "Check Spelling While Typing", isOn: $checksSpelling).accessibilityIdentifier("CheckSpelling")
                }
            }
            SettingsSection(
                "Links",
                footer: "How a link to another item looks in an item’s text. A link to an item that doesn’t exist keeps its dashed line in every look."
            ) {
                SettingsRow("Look") {
                    SettingsPopUp(title: "Look", selection: $linkLook) {
                        ForEach(LinkLook.allCases) { option in
                            switch option {
                            case .mark: Text("Mark").tag(option)
                            case .underline: Text("Underline").tag(option)
                            case .tintedPill: Text("Tinted Pill").tag(option)
                            case .pill: Text("Pill").tag(option)
                            case .quiet: Text("Quiet").tag(option)
                            case .text: Text("Text").tag(option)
                            }
                        }
                    }
                    .accessibilityIdentifier("LinkLook")
                }
            }
            SettingsSection(
                "Pictures",
                footer: "An item’s text can name a picture at a web address. MAPP loads it only when you choose to, or always for items in the Inbox. Pictures you have loaded stay on this Mac until you disconnect the library."
            ) {
                SettingsRow("Remote Pictures") {
                    SettingsPopUp(title: "Remote Pictures", selection: $pictures) {
                        ForEach(RemotePictureSetting.allCases) { option in
                            switch option {
                            case .ask: Text("Ask").tag(option)
                            case .always: Text("Always").tag(option)
                            case .never: Text("Never").tag(option)
                            }
                        }
                    }
                    .accessibilityIdentifier("RemotePictures")
                }
            }
        }
        .accessibilityIdentifier("EditorPage")
    }
}

/// The Lists page: how much each row says, what every list shows, and where an item opens.
struct ListsPage: View {
    @AppStorage(ListKey.density) private var density = Density.standard
    @AppStorage(ListKey.openItemsIn) private var openItemsIn = ItemOpening.standard
    @AppStorage(OrderKey.sort) private var sort = ItemOrder().sort
    @AppStorage(OrderKey.groupsByDate) private var groupsByDate = ItemOrder().groupsByDate

    var body: some View {
        SettingsPageColumn {
            SettingsSection("Density") {
                SettingsRow("Density") {
                    SettingsPopUp(title: "Density", selection: $density) {
                        ForEach(Density.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("ListsDensity")
                }
            }
            SettingsSection("In Every List") {
                SettingsRow("Sort By") {
                    SettingsPopUp(title: "Sort By", selection: $sort) {
                        ForEach(ItemSort.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("ItemSort")
                }
                SettingsRow("Group By", look: sort == .title ? .off : .normal) {
                    SettingsPopUp(title: "Group By", selection: $groupsByDate) {
                        Text("None").tag(false)
                        Text("Date").tag(true)
                    }
                    .accessibilityIdentifier("GroupBy")
                }
                SettingsRow("Open Items In") {
                    SettingsPopUp(title: "Open Items In", selection: $openItemsIn) {
                        ForEach(ItemOpening.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("ListsOpenItemsIn")
                }
            }
        }
        .accessibilityIdentifier("ListsPage")
    }
}
