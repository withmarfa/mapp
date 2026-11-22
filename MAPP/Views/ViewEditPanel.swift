import SwiftUI

/// The right sidebar while a view is edited (`ViewPanel`): its name, how it is shown, sort, group, its Properties
/// and the gallery's cards. Each change shows at once in the window beside it and, in a saved view, is written
/// as it is made; Done closes the panel (`ViewPanelToolbar`). Filters are not here: they live in the row above the list
/// (`FilterChips`). A type's list and the other places that can become a view get the same panel without a name, and
/// offer Save as View. A list also gets Density, which a view or a place may set apart from Settings.
struct ViewEditPanel: View {
    @CurrentLibrary private var library
    @StoredOrder private var order
    @Bindable var browser: Browser
    @Bindable var panel: ViewPanel
    @FocusState private var nameFocused: Bool

    var body: some View {
        let content = browser.tableContent(in: library)
        let arrangement = SavedViews.arrangement(browser, content: content, order: order)
        ScrollView {
            VStack(alignment: .leading, spacing: InspectorMetrics.sectionGap) {
                if panel.purpose != .place {
                    ViewPanelSection(title: "Name") {
                        InspectorBox {
                            TextField("View Name", text: $panel.shownName)
                                .textFieldStyle(.plain)
                                .focused($nameFocused)
                                .onSubmit { submitName() }
                                .accessibilityIdentifier("ViewPanelName")
                        }
                    }
                }
                ViewPanelLayoutSection(browser: browser, panel: panel)
                if browser.viewMode == .list {
                    ViewPanelDensity(browser: browser, panel: panel)
                }
                // The timeline and the calendar place items by time, so a sort would change nothing there.
                if browser.viewMode != .timeline && browser.viewMode != .calendar {
                    ViewPanelSort(browser: browser, content: content, sort: arrangement.sort)
                }
                if browser.viewMode != .calendar {
                    ViewPanelGroup(browser: browser)
                }
                if browser.viewMode != .calendar {
                    ViewPanelProperties(browser: browser)
                }
                if browser.viewMode == .gallery {
                    ViewPanelCards(browser: browser, panel: panel)
                }
                if panel.isNew {
                    ViewPanelUnkept(browser: browser)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .task(id: ObjectIdentifier(panel)) {
            if panel.isNew { nameFocused = true }
        }
        // A name is written when the person commits it: Return, or leaving the field.
        .onChange(of: nameFocused) { if !nameFocused, panel.viewID != nil { commitName() } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ViewEditPanel")
    }

    private func submitName() {
        if panel.isNew {
            Task { await browser.finishViewPanel(in: library, order: order) }
        } else {
            commitName()
        }
    }

    private func commitName() {
        Task { await browser.commitViewName(of: panel, in: library) }
    }
}

/// A section's heading, with a note beside it such as where its choices are kept, above its grouped box.
struct ViewPanelSection<Content: View>: View {
    let title: LocalizedStringKey
    var note: LocalizedStringKey?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.headingGap) {
            HStack(spacing: 6) {
                Text(title).interfaceFont(.body.weight(.semibold))
                Spacer(minLength: 0)
                if let note {
                    Text(note).interfaceFont(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, InspectorMetrics.headingInset)
            .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

/// The layout the window shows the place in, as a pop-up named Show As with the layout's symbol and name. The choice is
/// the window's, and this Mac keeps a saved view's as it is made.
private struct ViewPanelLayoutSection: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    let panel: ViewPanel

    var body: some View {
        ViewPanelSection(title: "Layout", note: panel.purpose == .place ? nil : "This Mac") {
            InspectorBox {
                HStack {
                    Text("Show As")
                    Spacer(minLength: 0)
                    Picker("Show As", selection: $browser.viewMode) {
                        ForEach(browser.availableViewModes(in: library), id: \.self) { mode in
                            Label(mode.title, systemImage: mode.symbol).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .accessibilityIdentifier("ViewPanelLayout")
                }
            }
        }
    }
}

/// The Group section (board N3): Group by, with By for a field grouped more than one way (a date's spans and Set or Not
/// Set, a status's words and groups), then the groups in order, each with a handle to drag and an eye, then Hide Empty
/// Groups, which this Mac keeps. The order and the hidden groups are Marfa's `group.order` and `group.hidden` in a saved
/// view, and the place's own in its default view. The timeline's grouping is the date it places items by.
private struct ViewPanelGroup: View {
    @CurrentLibrary private var library
    let browser: Browser

    var body: some View {
        ViewPanelSection(title: "Group") {
            InspectorBox {
                if browser.viewMode == .timeline {
                    HStack {
                        Text("Group by")
                        Spacer(minLength: 0)
                        timelinePicker
                    }
                } else {
                    let offer = browser.groupOffer(in: library)
                    let shown = browser.shownGrouping(in: library)
                    let found = offer.entry(for: shown)
                    HStack {
                        Text("Group by")
                        Spacer(minLength: 0)
                        Menu {
                            GroupByChoices(browser: browser, offer: offer, shown: shown)
                        } label: {
                            Text(verbatim: found?.entry.label ?? String(localized: "None"))
                        }
                        .fixedSize()
                        .accessibilityIdentifier("ViewPanelGroupBy")
                    }
                    if let found, found.entry.choices.count > 1 {
                        HStack {
                            Text("By")
                            Spacer(minLength: 0)
                            // A way a saved view cannot keep is listed, and choosing it changes nothing; the line below says why.
                            Picker("By", selection: Binding { shown } set: { grouping in
                                if found.entry.choices.first(where: { $0.grouping == grouping })?.isKept == true { browser.chooseGrouping(grouping) }
                            }) {
                                ForEach(Array(found.entry.runs.enumerated()), id: \.offset) { index, run in
                                    if index > 0 { Divider() }
                                    ForEach(run) { choice in
                                        Text(verbatim: choice.isKept ? choice.label : String(localized: "\(choice.label) (Not Kept)")).tag(choice.grouping)
                                    }
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                            .accessibilityIdentifier("ViewPanelGroupMode")
                        }
                        if found.entry.choices.contains(where: { !$0.isKept }) {
                            Text("A saved view can’t keep this grouping yet.")
                                .interfaceFont(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if shown != .none, browser.datedList == nil {
                        let hidden = browser.viewMode == .board && browser.boardLanes(in: library)?.isOwn == false
                            ? Set<String>() : browser.tableOptions[browser.item]?.hiddenGroups ?? []
                        ForEach(browser.groupRows(in: library).filter { $0.key != GroupKey.notApplicable }, id: \.key) { row in
                            GroupRow(browser: browser, key: row.key, title: row.title, isShown: !hidden.contains(row.key))
                        }
                    }
                }
                HStack {
                    Text("Hide Empty Groups")
                    Spacer(minLength: 0)
                    Text("This Mac").interfaceFont(.callout).foregroundStyle(.secondary)
                    Toggle("Hide Empty Groups", isOn: Binding { browser.hidesEmptyGroups } set: { browser.setHidesEmptyGroups($0) })
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .accessibilityIdentifier("ViewPanelHideEmptyGroups")
            }
        }
    }

    private var timelinePicker: some View {
        let place = browser.item
        let fields = browser.timelineFieldChoices(in: library)
        let selected = ItemTimelineLayout.selectedField(browser.timelineFields[place], fields: fields)
        return Picker("Group by", selection: Binding { selected ?? "" } set: { browser.timelineFields[place] = $0.isEmpty ? nil : $0 }) {
            Text("Date of Each Type").tag("")
            Divider()
            ForEach(fields, id: \.key) { Text($0.label).tag($0.key) }
        }
        .labelsHidden()
        .accessibilityIdentifier("ViewPanelGroupBy")
    }
}

/// One group in Edit View: a handle to drag it into order, its name, and the eye that shows or hides it. A hidden group
/// leaves the layout, and its items still count in the place.
private struct GroupRow: View {
    @CurrentLibrary private var library
    @Environment(\.interfaceTextSize) private var textSize
    let browser: Browser
    let key: String
    let title: String
    let isShown: Bool

    private static let prefix = "group:"

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        HStack(spacing: InspectorMetrics.gap) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11 * scale))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(verbatim: title)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isShown ? .primary : .secondary)
            Spacer(minLength: 0)
            Button {
                browser.setGroup(key, hidden: isShown, in: library)
            } label: {
                Image(systemName: isShown ? "eye" : "eye.slash")
                    .foregroundStyle(isShown ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                    .frame(width: InspectorMetrics.trailingColumn, height: InspectorMetrics.trailingColumn)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(isShown ? "Hide Group" : "Show Group")
            .accessibilityLabel(isShown ? "Hide Group" : "Show Group")
        }
        .interfaceFont(.body)
        .contentShape(.rect)
        .modifier(Arrangeable(isOn: true, id: Self.prefix + key, move: move))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ViewPanelGroup.\(key)")
    }

    private func move(_ dragged: String) -> Bool {
        guard dragged.hasPrefix(Self.prefix) else { return false }
        let moved = String(dragged.dropFirst(Self.prefix.count))
        guard moved != key else { return false }
        browser.moveGroup(moved, onto: key, in: library)
        return true
    }
}

/// What New View will not keep of the window (board N12), one row each, so nothing is a surprise once it is saved.
private struct ViewPanelUnkept: View {
    @CurrentLibrary private var library
    @StoredOrder private var order
    let browser: Browser

    var body: some View {
        let window = SavedViews.window(browser, in: library, order: order)
        let unkept = ViewDraft.draft(window, catalogue: library.catalogue, views: library.views)?.unkept ?? []
        if !unkept.isEmpty {
            ViewPanelSection(title: "Not Saved in the View", note: "\(unkept.count)") {
                InspectorBox {
                    ForEach(unkept, id: \.self) { item in
                        Label(SavedViews.describe(item), systemImage: Self.symbol(of: item))
                            .foregroundStyle(.secondary)
                            .interfaceFont(.body)
                    }
                }
            }
            .accessibilityIdentifier("ViewPanelUnkept")
        }
    }

    private static func symbol(of unkept: ViewDraft.Unkept) -> String {
        switch unkept {
        case .search: "magnifyingglass"
        case .filter, .mixedFilters, .tooManyFilters, .refused, .relativeFilter: "line.3.horizontal.decrease"
        case .sort: "arrow.up.arrow.down"
        case .group, .groupMode: "rectangle.grid.1x2"
        }
    }
}

extension ItemViewMode {
    /// The layout's name.
    var title: String {
        switch self {
        case .list: String(localized: "List")
        case .gallery: String(localized: "Gallery")
        case .table: String(localized: "Table")
        case .board: String(localized: "Board")
        case .timeline: String(localized: "Timeline")
        case .calendar: String(localized: "Calendar")
        }
    }
}
