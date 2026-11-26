import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// An audio or a video file's page: the head as the first inset of a scroller of its own, then the picture of a video, or
/// the waveform of a sound, with the one playback bar at the window's foot (`PlaybackBar`). Nothing plays by itself.
/// Space plays and pauses and the arrows skip while the page has the keyboard. Leaving the item or closing its window
/// stops it and keeps its place (`MediaPlayback.leave`).
struct FileMediaPage: View {
    let url: URL
    let title: String
    let type: UTType
    let item: ItemID?
    let head: FileHeadSpace?
    @CurrentLibrary private var library
    @StoredPageStyle private var style
    @Environment(\.interfaceTextSize) private var textSize
    @State private var playback: MediaPlayback
    @State private var envelope: WaveformEnvelope?
    @State private var appName: String?
    @FocusState private var hasFocus: Bool

    init(url: URL, title: String, type: UTType, item: ItemID?, head: FileHeadSpace?) {
        self.url = url
        self.title = title
        self.type = type
        self.item = item
        self.head = head
        _playback = State(initialValue: MediaPlayback(item: item, url: url, type: type))
    }

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        GeometryReader { geometry in
            if playback.state == .unplayable {
                unplayable.padding(.top, head?.top ?? 0)
            } else {
                page(in: geometry.size, scale: scale)
            }
        }
        .overlay {
            if playback.state != .unplayable { PlaybackFoot { PlaybackBar(mode: .player(playback)) } }
        }
        .background { LeavesWithWindow(leave: playback.leave, keepPlace: playback.keepPlaceNow) }
        .task(id: url) {
            await playback.load()
            guard playback.state == .ready, !playback.hasVideo, playback.hasAudio else { return }
            envelope = await WaveformEnvelope.read(url, type: type)
        }
        .onDisappear { playback.leave() }
    }

    private func page(in pane: CGSize, scale: CGFloat) -> some View {
        let inset = head == nil ? 0 : style.horizontalInset(for: pane.width)
        let toolbar = head?.toolbar ?? 0
        let top = head?.top ?? 0
        // The foot's bar and its gap, so the last of the page scrolls clear of it.
        let foot = 44 * scale + WindowCorner<EmptyView, EmptyView>.inset * 3
        let column = CGSize(width: max(pane.width - inset * 2, 1), height: max(pane.height - toolbar - foot - 22, 120))
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                if playback.hasVideo {
                    picture(fitting: column)
                } else if playback.state == .ready {
                    WaveformView(playback: playback, envelope: envelope).padding(.top, 4)
                }
            }
            .padding(.horizontal, inset)
            .padding(.top, 22)
            .padding(.bottom, foot)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentMargins(.top, top, for: .scrollContent)
        .contentMargins(.top, toolbar, for: .scrollIndicators)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + top } action: { _, offset in head?.scrolled(offset) }
        .focusable()
        .focused($hasFocus)
        .focusEffectDisabled()
        .simultaneousGesture(TapGesture().onEnded { hasFocus = true })
        .onKeyPress(.space) { press { playback.togglePlaying() } }
        .onKeyPress(.leftArrow) { press { playback.skip(by: -PlaybackClock.skip) } }
        .onKeyPress(.rightArrow) { press { playback.skip(by: PlaybackClock.skip) } }
    }

    /// Runs a key's action while the file is ready; any other state leaves the key to the system.
    private func press(_ action: () -> Void) -> KeyPress.Result {
        guard playback.state == .ready else { return .ignored }
        action()
        return .handled
    }

    private func picture(fitting column: CGSize) -> some View {
        let natural = playback.pictureSize
        let fit = min(column.width / natural.width, column.height / natural.height)
        return PlayerPicture(player: playback.player)
            .frame(width: natural.width * fit, height: natural.height * fit)
            .clipShape(.rect(cornerRadius: 10))
            .accessibilityLabel(title)
    }

    /// A format AVFoundation cannot play: the page says so, and the file can be opened in another app.
    private var unplayable: some View {
        ContentUnavailableView {
            Label("Can’t Play This File", systemImage: "play.slash")
        } description: {
            Text("This Mac can’t play this kind of file. Open it in another app.")
        } actions: {
            if let target = openTarget {
                Button(PageOpener.title(opening: appName)) {
                    if let found = item.flatMap({ library.item($0) }) { PageOpener.open(target, for: found) }
                }
                .task(id: url) { appName = PageOpener.appName(for: target) }
            }
        }
    }

    private var openTarget: PageOpenTarget? { item == nil ? nil : .file(url) }
}

/// A video's picture, with no controls of its own: the playback bar is the one control.
private struct PlayerPicture: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> Host {
        let host = Host()
        host.playerLayer.player = player
        host.playerLayer.videoGravity = .resizeAspect
        return host
    }

    func updateNSView(_ host: Host, context: Context) {
        if host.playerLayer.player !== player { host.playerLayer.player = player }
    }

    final class Host: NSView {
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
        }

        required init?(coder: NSCoder) { nil }

        override func makeBackingLayer() -> CALayer { AVPlayerLayer() }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// Tells its page when its window closes, and when the app is about to end, which an item being left does not cover.
private struct LeavesWithWindow: NSViewRepresentable {
    let leave: () -> Void
    let keepPlace: () -> Void

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ probe: Probe, context: Context) {
        probe.leave = leave
        probe.keepPlace = keepPlace
    }

    static func dismantleNSView(_ probe: Probe, coordinator: ()) { probe.stopWatching() }

    final class Probe: NSView {
        var leave: (() -> Void)?
        var keepPlace: (() -> Void)?
        private var observers: [any NSObjectProtocol] = []

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopWatching()
            guard let window else { return }
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.leave?() }
                },
                center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.keepPlace?() }
                },
            ]
        }

        func stopWatching() {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers = []
        }
    }
}
