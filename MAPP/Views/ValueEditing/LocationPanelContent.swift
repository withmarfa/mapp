import MapKit
import SwiftUI

/// The numbers the Location panel is drawn with, beside `ValueEditMetrics`.
nonisolated enum LocationMetrics {
    static let mapHeight: CGFloat = 200
    /// The height the panel opens at, before its content has measured itself.
    static let estimatedHeight: CGFloat = 360
    /// The room kept at the foot of the map for Apple's logo and its legal link, which nothing may cover.
    static let attributionRoom: CGFloat = 36
}

/// The Location panel: a search that moves an Apple map, the map with the item's pin, the place's name where the type has
/// one, the Show Coordinates switch and Clear Location. The map is always an Apple map with its logo and legal link in
/// view. The person places the pin by clicking where there is none and moves it only by dragging it, so a click or a
/// double-click that zooms never moves a point; a search result only moves the map. An item that cannot be edited shows
/// the map and its point, with no search.
struct LocationPanelContent: View {
    let model: LocationPanelModel
    let panel: ValueEditModel
    @Environment(\.interfaceTextSize) private var textSize
    @AppStorage(PageKey.showsCoordinates) private var showsCoordinates = false
    @FocusState private var focus: Field?
    @State private var position: MapCameraPosition
    @GestureState private var drag = CGSize.zero

    private enum Field: Hashable {
        case search
        case name
    }

    init(model: LocationPanelModel, panel: ValueEditModel) {
        self.model = model
        self.panel = panel
        _position = State(initialValue: .region(model.startFrame.region))
    }

    private var scale: CGFloat { InterfaceStyle.scale(for: textSize) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.canEdit {
                searchField
                Divider().padding(.vertical, 4 * scale)
            }
            map
            if model.canEdit { hint }
            if let problem = model.problem { problemLine(problem) }
            if model.hasNameField { nameRow }
            if let notice = model.notice { noticeArea(notice) }
            Divider().padding(.vertical, 5 * scale)
            coordinatesRow
            if model.canEdit, model.hasLocation { clearRow }
        }
        .font(.system(size: ValueEditMetrics.textSize * scale))
        .padding(ValueEditMetrics.padding * scale)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panel.measure(.total, $0) }
        .task {
            await Task.yield()
            if model.canEdit { focus = .search }
        }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 6 * scale) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search for a Place", text: Bindable(model).query)
                .textFieldStyle(.plain)
                .focused($focus, equals: .search)
                .accessibilityIdentifier("LocationSearch")
                .onChange(of: model.query) { model.queryChanged() }
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                    focus = .search
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 8 * scale)
        .frame(minHeight: ValueEditMetrics.rowHeight * scale)
    }

    @ViewBuilder private var results: some View {
        switch model.search {
        case .idle:
            EmptyView()
        case .searching:
            resultsMessage("Searching…")
        case .noResults:
            resultsMessage("No places found.")
        case .failed:
            resultsMessage("Search isn’t available right now.")
        case .found(let found):
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(found) { result in
                        LocationResultRow(result: result, scale: scale) {
                            position = .region(model.choose(result).region)
                            focus = nil
                        }
                    }
                }
                .padding(3 * scale)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: LocationMetrics.mapHeight * scale - LocationMetrics.attributionRoom * scale)
            .fixedSize(horizontal: false, vertical: true)
            .background(.regularMaterial, in: .rect(cornerRadius: 8 * scale, style: .continuous))
            .padding(6 * scale)
        }
    }

    private func resultsMessage(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10 * scale)
            .frame(height: ValueEditMetrics.rowHeight * scale)
            .background(.regularMaterial, in: .rect(cornerRadius: 8 * scale, style: .continuous))
            .padding(6 * scale)
    }

    // MARK: Map

    private var map: some View {
        MapReader { proxy in
            Map(position: $position, interactionModes: [.pan, .zoom]) {
                if let point = model.point {
                    Annotation("Location", coordinate: point.coordinate, anchor: .bottom) { pin(at: point, proxy: proxy) }
                        .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard)
            .mapControls { MapZoomStepper() }
            .onMapCameraChange(frequency: .onEnd) { model.visibleRegion = $0.region }
            // A double-click is the map's zoom, so it comes first and its first click is never taken as a click.
            .gesture(
                TapGesture(count: 2).exclusively(before: SpatialTapGesture(coordinateSpace: .local))
                    .onEnded { tap in
                        guard case .second(let click) = tap, model.canEdit, model.point == nil,
                              let coordinate = proxy.convert(click.location, from: .local),
                              let point = LocationPoint(clicked: coordinate.latitude, longitude: coordinate.longitude) else { return }
                        model.place(point)
                    })
        }
        .frame(height: LocationMetrics.mapHeight * scale)
        .clipShape(.rect(cornerRadius: 8 * scale, style: .continuous))
        .overlay(alignment: .top) { results }
        .accessibilityIdentifier("LocationMap")
    }

    /// The pin. Dragging moves it by the distance the pointer travelled, and the place it lands on is what is written.
    private func pin(at point: LocationPoint, proxy: MapProxy) -> some View {
        Image(systemName: "mappin")
            .font(.system(size: 26 * scale, weight: .semibold))
            .foregroundStyle(.red)
            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
            .offset(model.canEdit ? drag : .zero)
            .gesture(
                DragGesture(minimumDistance: 3)
                    .updating($drag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        guard model.canEdit, let tip = proxy.convert(point.coordinate, to: .local),
                              let coordinate = proxy.convert(
                                  CGPoint(x: tip.x + value.translation.width, y: tip.y + value.translation.height), from: .local),
                              let moved = LocationPoint(clicked: coordinate.latitude, longitude: coordinate.longitude) else { return }
                        model.place(moved)
                    },
                including: model.canEdit ? .all : .none)
            .accessibilityLabel("Pin")
            .accessibilityIdentifier("LocationPin")
    }

    private var hint: some View {
        Group {
            if model.point == nil { Text("Click the map to place the pin.") } else { Text("Drag the pin to move it.") }
        }
            .font(.system(size: 11 * scale))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 3 * scale)
            .padding(.top, 5 * scale)
            .accessibilityIdentifier("LocationHint")
    }

    private func problemLine(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 11 * scale))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 3 * scale)
            .padding(.top, 5 * scale)
            .accessibilityIdentifier("LocationProblem")
    }

    // MARK: Name

    @ViewBuilder private var nameRow: some View {
        if model.canEdit {
            HStack(spacing: 8 * scale) {
                Text("Name").foregroundStyle(.secondary)
                TextField("", text: Bindable(model).name, prompt: Text("Name of the place"))
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Name")
                    .focused($focus, equals: .name)
                    // Not written as the field loses focus: a click on the map would make it an edit of its own.
                    .onSubmit { model.commitName() }
                    .padding(.horizontal, 6 * scale)
                    .frame(height: 22 * scale)
                    .background(.quaternary, in: .rect(cornerRadius: 5 * scale, style: .continuous))
                    .accessibilityIdentifier("LocationName")
            }
            .padding(.horizontal, 3 * scale)
            .padding(.top, 7 * scale)
        } else if !model.name.isEmpty {
            HStack(spacing: 8 * scale) {
                Text("Name").foregroundStyle(.secondary)
                Text(verbatim: model.name).lineLimit(1).truncationMode(.tail)
            }
            .padding(.horizontal, 3 * scale)
            .padding(.top, 7 * scale)
        }
    }

    private func noticeArea(_ notice: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: notice)
                .font(.system(size: 11 * scale))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 3 * scale)
                .accessibilityIdentifier("LocationNotice")
            if model.hasNameConflict {
                HStack(spacing: 12 * scale) {
                    Button("Keep My Edit") { model.keepName() }
                    Button("Use Current Name") { model.useHeldName() }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11 * scale))
                .padding(.horizontal, 3 * scale)
                .padding(.top, 2 * scale)
            }
        }
        .padding(.top, 6 * scale)
    }

    // MARK: Settings and clearing

    private var coordinatesRow: some View {
        HStack(spacing: 8 * scale) {
            Text("Show Coordinates")
            Spacer(minLength: 8 * scale)
            Toggle("Show Coordinates", isOn: $showsCoordinates)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityIdentifier("LocationShowCoordinates")
        }
        .padding(.horizontal, 8 * scale)
        .frame(height: ValueEditMetrics.rowHeight * scale)
    }

    private var clearRow: some View {
        Button {
            model.clear()
        } label: {
            Text("Clear Location")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8 * scale)
                .frame(height: ValueEditMetrics.rowHeight * scale)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("LocationClear")
    }
}

/// One place a search found.
private struct LocationResultRow: View {
    let result: LocationSearchResult
    let scale: CGFloat
    let choose: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 7 * scale) {
            Image(systemName: "mappin.circle.fill")
                .foregroundStyle(isHovered ? AnyShapeStyle(.white) : AnyShapeStyle(.red))
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: result.title).lineLimit(1).truncationMode(.tail)
                if !result.subtitle.isEmpty {
                    Text(verbatim: result.subtitle)
                        .font(.system(size: 11 * scale))
                        .foregroundStyle(isHovered ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(isHovered ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 6 * scale)
        .padding(.vertical, 3 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: ValueEditMetrics.rowRadius * scale, style: .continuous).fill(Color.accentColor)
            }
        }
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .onTapGesture(perform: choose)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, choose)
        .accessibilityIdentifier("LocationResult")
    }
}
