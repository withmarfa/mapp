import MapKit
import SwiftUI

/// The map layout: Apple's map from edge to edge under the top row, with the items that have a place as markers in their
/// type's tone and groups with a count where markers crowd (`MapController`). A quiet pill at the foot counts the items
/// the map cannot place and lists them. Choosing a marker is choosing the item (`Browser.selection`), and a double-click
/// opens it as every layout does. The placing of a large place is worked out off the main actor (`Browser.placed`), and
/// this body does not read the selection, so choosing a marker redraws the map's own views and no more.
struct ItemMap: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    var pane: FocusState<Browser.Pane?>.Binding
    @State private var controller = MapController()
    @Environment(\.topRowSpace) private var space
    @Environment(\.colorScheme) private var scheme
    @Environment(\.interfaceTextSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let placing = browser.mapPlacing(in: library) {
            canvas(placing)
        } else {
            PlaceProgress()
        }
    }

    private func canvas(_ placing: MapLayout.Placing) -> some View {
        ItemMapCanvas(
            controller: controller,
            inputs: MapController.Inputs(
                browser: browser, catalogue: library.catalogue, placing: placing, style: browser.mapStyle, groups: browser.groupsNearbyItems,
                placeToken: AnyHashable(MapPlaceToken(library: ObjectIdentifier(library), place: browser.shown)), scheme: scheme, textSize: textSize,
                reduceMotion: reduceMotion))
            .ignoresSafeArea(.container, edges: .top)
            .overlay(alignment: .top) {
                // The row's own band shows only once rows scroll under it, and the map is under it from the start.
                ToolbarBand(toolbarHeight: space.lineHeight, isShown: true, strength: 0.78)
            }
            .overlay(alignment: .bottomTrailing) { MapControls(controller: controller, browser: browser) }
            .overlay(alignment: .bottom) {
                if !placing.unplaced.isEmpty { NoLocationPill(ids: placing.unplaced, browser: browser) }
            }
            .overlay {
                if placing.pins.isEmpty, !placing.unplaced.isEmpty { NothingOnMap() }
            }
            .overlay {
                if placing.pins.isEmpty, placing.unplaced.isEmpty {
                    if browser.narrowsBySearch {
                        SearchEmptyState(browser: browser)
                    } else {
                        PlaceEmptyState(browser: browser)
                    }
                }
            }
            .searchStatus(browser)
            .filteredEmptyState(browser)
            .background(ChosenRowOpensSidebar(browser: browser))
            .onChange(of: browser.mapFitRequests) { controller.fitAll() }
            .accessibilityLabel("Map")
    }
}

private struct MapPlaceToken: Hashable {
    let library: ObjectIdentifier
    let place: PlaceView
}

/// Where the map holds nothing: items are listed and none has a place to stand on.
private struct NothingOnMap: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("Nothing to Show on the Map").interfaceFont(.headline)
            Text("None of these items has a location.").interfaceFont(.callout).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .windowGlass(in: .rect(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The map controls sit above Apple's Legal link.
private struct MapControls: View {
    let controller: MapController
    let browser: Browser
    @Environment(SelectionSummary.self) private var summary: SelectionSummary?
    @Environment(\.interfaceTextSize) private var textSize

    private func zoomButton(_ title: LocalizedStringKey, symbol: String, factor: Double) -> some View {
        Button { controller.zoom(by: factor) } label: {
            Image(systemName: symbol).frame(width: 36, height: 36).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier("Map" + (factor < 1 ? "ZoomIn" : "ZoomOut"))
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                zoomButton("Zoom Out", symbol: "minus", factor: 2)
                zoomButton("Zoom In", symbol: "plus", factor: 0.5)
            }
            .windowGlass(in: .capsule)
            .accessibilityElement(children: .contain)
            Button { browser.requestMapFit() } label: {
                Image(systemName: "scope").frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .windowGlass(.regular.interactive(), in: .circle)
            .help("Fit All Items")
            .accessibilityLabel("Fit All Items")
            .accessibilityIdentifier("MapFit")
        }
        .padding(.trailing, 14)
        // Above Apple's Legal link, and above the capsule while several items are chosen.
        .padding(.bottom, 34 + (summary?.isCapsuleShown == true ? SelectionSummary.capsuleRoom(scale: InterfaceStyle.scale(for: textSize)) - 22 : 0))
    }
}

/// The quiet pill that counts what the map cannot place, and opens those items as a list.
private struct NoLocationPill: View {
    @CurrentLibrary private var library
    let ids: [ItemID]
    let browser: Browser
    @State private var isOpen = false
    @Environment(SelectionSummary.self) private var summary: SelectionSummary?
    @Environment(\.interfaceTextSize) private var textSize

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet")
                Text("No Location")
                Text(ids.count, format: .number).foregroundStyle(.secondary).monospacedDigit()
            }
            .interfaceFont(.callout)
            .padding(.horizontal, 12)
            .frame(height: 28)
        }
        .buttonStyle(.plain)
        .windowGlass(.regular.interactive(), in: .capsule)
        .padding(.bottom, summary?.isCapsuleShown == true ? SelectionSummary.capsuleRoom(scale: InterfaceStyle.scale(for: textSize)) : 14)
        .popover(isPresented: $isOpen, arrowEdge: .top) { UnplacedList(ids: ids, browser: browser, isOpen: $isOpen) }
        .accessibilityLabel(Text("No Location, \(ids.count) items"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("MapNoLocation")
    }
}

/// The items that have no place on the map, as a list that draws only the rows in view.
private struct UnplacedList: View {
    @CurrentLibrary private var library
    let ids: [ItemID]
    let browser: Browser
    @Binding var isOpen: Bool

    var body: some View {
        List(ids, id: \.self) { id in
            if let item = library.item(id) {
                Button {
                    isOpen = false
                    browser.selection = [id]
                    _ = browser.open([id])
                } label: {
                    HStack(spacing: 6) {
                        TonedGlyph(id: library.catalogue.icon(for: item.type))
                        Text(item.displayTitle).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .frame(width: 300, height: min(CGFloat(ids.count) * 34 + 8, 360))
        .accessibilityLabel("Items With No Location")
    }
}
