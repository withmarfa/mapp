import AppKit
import SwiftUI

extension View {
    /// Gives a sidebar place its context menu: a view's own commands, the color of its mark, where it goes, Hide from
    /// Sidebar and Customize Sidebar.
    func sidebarPlaceMenu(data: SidebarPlaceRowData, groups: [SidebarGroupChoice], browser: Browser) -> some View {
        modifier(SidebarPlaceMenu(data: data, groups: groups, browser: browser))
    }
}

/// A place's context menu, drawn as an AppKit menu. A SwiftUI menu holds only commands, so it cannot hold the color row,
/// which is a view of its own that scrolls sideways; the menu's text entries are the same commands as ever, and only
/// the menu's width follows them.
private struct SidebarPlaceMenu: ViewModifier {
    @Environment(Libraries.self) private var libraries
    @Environment(\.library) private var library
    @StoredOrder private var order
    let data: SidebarPlaceRowData
    let groups: [SidebarGroupChoice]
    let browser: Browser

    func body(content: Content) -> some View {
        content.overlay { MenuAnchor { build() } }
    }

    /// Keeps the menu's targets alive until the next menu is made, since an item holds its target weakly.
    private final class Choice: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func fire(_ sender: NSMenuItem) { run() }
    }

    private func build() -> (menu: NSMenu, keeping: [AnyObject]) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        var keeping: [AnyObject] = []
        func add(_ title: String, to menu: NSMenu = menu, enabled: Bool = true, _ run: @escaping () -> Void) {
            let choice = Choice(run)
            keeping.append(choice)
            let item = NSMenuItem(title: title, action: #selector(Choice.fire(_:)), keyEquivalent: "")
            item.target = choice
            item.isEnabled = enabled
            menu.addItem(item)
        }

        let place = data.place
        if case .view(let id) = place, let library {
            add(String(localized: "Edit View")) { browser.editView(id, in: library, order: order) }
            add(String(localized: "Duplicate View"), enabled: library.reachesServer) {
                Task { await browser.duplicateView(id, in: library, order: order) }
            }
            menu.addItem(.separator())
            add(String(localized: "Delete View…"), enabled: library.reachesServer) { browser.deletingView = id }
            menu.addItem(.separator())
        }
        if place.defaultTone != nil {
            let item = NSMenuItem()
            let row = SidebarColorPicker(chosen: libraries.sidebarLayout.color(of: place)) { [weak menu, libraries] tone in
                menu?.cancelTracking()
                libraries.updateSidebarLayout { $0.setColor(tone, of: place) }
            }
            let host = SwatchHost(rootView: row)
            host.sizingOptions = []
            // Narrower than the text entries, so the menu is as wide as they need and the row stretches to it.
            host.frame = NSRect(x: 0, y: 0, width: 100, height: SidebarColorPicker.height)
            host.autoresizingMask = [.width]
            item.view = host
            menu.addItem(item)
            menu.addItem(.separator())
        }
        if !groups.isEmpty {
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for group in groups {
                add(group.name, to: submenu) { libraries.updateSidebarLayout { $0.put(place, in: group.id) } }
            }
            let item = NSMenuItem(title: String(localized: "Move to Section"), action: nil, keyEquivalent: "")
            item.submenu = submenu
            menu.addItem(item)
            menu.addItem(.separator())
        }
        add(String(localized: "Hide from Sidebar")) { libraries.updateSidebarLayout { $0.take(place) } }
        if case .view = place {
            add(String(localized: "Hide Views from Sidebar")) { libraries.updateSidebarLayout { $0.setHidden(.views, true) } }
        }
        menu.addItem(.separator())
        add(String(localized: "Customize Sidebar…"), enabled: !browser.customizesSidebar) { browser.customizesSidebar = true }
        return (menu, keeping)
    }
}

/// Opens a menu on a Control-click or a right click on the row, and passes every other event through to it.
private struct MenuAnchor: NSViewRepresentable {
    let build: () -> (menu: NSMenu, keeping: [AnyObject])

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.build = build
        return view
    }

    func updateNSView(_ view: AnchorView, context: Context) { view.build = build }

    final class AnchorView: NSView {
        var build: (() -> (menu: NSMenu, keeping: [AnyObject]))?
        private var keeping: [AnyObject] = []

        override func isAccessibilityElement() -> Bool { false }

        /// Only the events that open a menu land here; a click, a drag or a hover reaches the row.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            switch event.type {
            case .rightMouseDown: return super.hitTest(point)
            case .leftMouseDown where event.modifierFlags.contains(.control): return super.hitTest(point)
            default: return nil
            }
        }

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) { rightMouseDown(with: event) } else { super.mouseDown(with: event) }
        }

        override func rightMouseDown(with event: NSEvent) {
            guard let (menu, keeping) = build?() else { return }
            self.keeping = keeping
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }
}

/// The palette that chooses a mark's color, as the menu's own item: one row of swatches that scrolls sideways when they
/// do not fit, fading where it runs on. The chosen color has a check.
struct SidebarColorPicker: View {
    static let height: CGFloat = 28
    private static let fade: CGFloat = 18

    /// Which ends of the row have more beyond them.
    private struct Beyond: Equatable {
        var leading = false
        var trailing = false
    }

    @Environment(\.colorScheme) private var scheme
    @State private var beyond = Beyond()
    let chosen: TypeTone?
    let choose: (TypeTone) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(TypeTone.allCases, id: \.self) { tone in
                    Button { choose(tone) } label: {
                        Image(systemName: tone == chosen ? "checkmark.circle.fill" : "circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(tone.color(for: scheme))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(tone.name))
                    .accessibilityAddTraits(tone == chosen ? .isSelected : [])
                }
            }
            .padding(.horizontal, 14)
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: Beyond.self) { geometry in
            Beyond(
                leading: geometry.contentOffset.x > 1,
                trailing: geometry.contentOffset.x + geometry.containerSize.width < geometry.contentSize.width - 1)
        } action: { _, new in
            beyond = new
        }
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [beyond.leading ? .clear : .black, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: Self.fade)
                Color.black
                LinearGradient(colors: [.black, beyond.trailing ? .clear : .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: Self.fade)
            }
        }
        .frame(height: Self.height)
    }
}

extension TypeTone {
    /// What the color is called, for VoiceOver.
    var name: String {
        switch self {
        case .blue: String(localized: "Blue")
        case .green: String(localized: "Green")
        case .orange: String(localized: "Orange")
        case .red: String(localized: "Red")
        case .purple: String(localized: "Purple")
        case .teal: String(localized: "Teal")
        case .yellow: String(localized: "Yellow")
        case .pink: String(localized: "Pink")
        case .indigo: String(localized: "Indigo")
        case .gray: String(localized: "Gray")
        }
    }
}

/// Hosts the swatch row in a menu item. A menu being tracked keeps scroll events for itself and never offers them to a
/// view in an item, so the row takes the ones that land on it, and hands them to its scroll view.
private final class SwatchHost: NSHostingView<SidebarColorPicker> {
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === window, event.scrollingDeltaX != 0, bounds.contains(convert(event.locationInWindow, from: nil)),
                  let scroller = Self.scrollView(in: self)
            else { return event }
            scroller.scrollWheel(with: event)
            return nil
        }
    }

    private static func scrollView(in view: NSView) -> NSScrollView? {
        if let scroller = view as? NSScrollView { return scroller }
        return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }
}
