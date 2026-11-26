import AVFoundation
import Foundation
import Observation
import UniformTypeIdentifiers

/// What a file's media can be opened as. A Marfa file is kept under its hash with no extension, so AVFoundation is told
/// the type the library gave it.
nonisolated enum FileMedia {
    /// Whether the file's page is the playback page: audio, or video.
    static func handles(_ type: UTType) -> Bool {
        type.conforms(to: .audio) || type.conforms(to: .movie) || type.conforms(to: .video)
    }

    static func asset(at url: URL, type: UTType?) -> AVURLAsset {
        let options = type?.preferredMIMEType.map { [AVURLAssetOverrideMIMETypeKey: $0] }
        return AVURLAsset(url: url, options: options)
    }
}

/// One audio or video file being played in one page: its position, speed and state, and the place it keeps (`PlaybackPlaces`).
/// Nothing plays until `play()` is called. Only one plays at a time in the app, so starting one pauses another.
/// The place is written when playback pauses and when the page is left (`leave()`), never on every tick.
@MainActor @Observable final class MediaPlayback {
    enum State: Equatable {
        /// Reading the file's tracks and length.
        case loading
        case ready
        /// AVFoundation cannot play the file.
        case unplayable
    }

    private(set) var state = State.loading
    /// In seconds, from the start.
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var isPlaying = false
    private(set) var speed: Double = 1
    private(set) var hasVideo = false
    private(set) var hasAudio = false
    /// The picture's size as shown, where the file has a video track.
    private(set) var pictureSize = CGSize.zero
    @ObservationIgnored let player = AVPlayer()

    @ObservationIgnored private let item: ItemID?
    @ObservationIgnored private let url: URL
    @ObservationIgnored private let type: UTType?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var isLeft = false
    @ObservationIgnored private var isScrubbing = false
    /// Where the latest move is going while the player has not yet landed there, which is where the file is until it does.
    @ObservationIgnored private var pendingTarget: Double?
    @ObservationIgnored private var moves = 0
    private static weak var playing: MediaPlayback?

    init(item: ItemID?, url: URL, type: UTType?, defaults: UserDefaults = .standard) {
        self.item = item
        self.url = url
        self.type = type
        self.defaults = defaults
        player.actionAtItemEnd = .pause
    }

    /// Reads the file and opens it at its kept place, paused.
    func load() async {
        isLeft = false
        state = .loading
        let asset = FileMedia.asset(at: url, type: type)
        do {
            let playable = try await asset.load(.isPlayable)
            let length = try await asset.load(.duration).seconds
            let audio = try await asset.loadTracks(withMediaType: .audio)
            let video = try await asset.loadTracks(withMediaType: .video)
            guard !Task.isCancelled, !isLeft else { return }
            guard playable, length.isFinite, length > 0 else { return fail() }
            var picture = CGSize.zero
            if let track = video.first {
                let natural = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let size = natural.applying(transform)
                picture = CGSize(width: abs(size.width), height: abs(size.height))
            }
            guard !Task.isCancelled, !isLeft else { return }
            duration = length
            hasAudio = !audio.isEmpty
            hasVideo = !video.isEmpty && picture.width >= 1 && picture.height >= 1
            pictureSize = picture
            player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
            observe()
            let opening = PlaybackPlaces.opening(kept: item.flatMap { PlaybackPlaces.place(of: $0, in: defaults) }, duration: length)
            if opening > 0 { await player.seek(to: CMTime(seconds: opening, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
            guard !Task.isCancelled, !isLeft else { return }
            position = opening
            state = .ready
        } catch {
            fail()
        }
    }

    private func fail() {
        state = .unplayable
    }

    // MARK: Controls

    func togglePlaying() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        guard state == .ready, !isLeft else { return }
        if let other = Self.playing, other !== self { other.pause() }
        Self.playing = self
        // A file that ended starts again from its start.
        if position >= duration - 0.05 { seek(to: 0) }
        player.defaultRate = Float(speed)
        player.play()
        isPlaying = true
    }

    /// Pauses and keeps the place.
    func pause() {
        guard state == .ready else { return }
        player.pause()
        isPlaying = false
        position = currentPosition()
        keepPlace()
    }

    func skip(by seconds: Double) {
        seek(to: position + seconds)
    }

    /// Moves to `time`, held to the file's length. A move leaves playing as it was.
    func seek(to time: Double) {
        guard state == .ready else { return }
        move(to: clamped(time), tolerance: .zero)
    }

    /// A move while a drag is in progress, which the player may land near rather than on. The drag ends with `endScrub`.
    func scrub(to time: Double) {
        guard state == .ready else { return }
        isScrubbing = true
        move(to: clamped(time), tolerance: CMTime(seconds: 0.5, preferredTimescale: 600))
    }

    private func move(to target: Double, tolerance: CMTime) {
        position = target
        pendingTarget = target
        moves += 1
        let move = moves
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.moves == move else { return }
                self.pendingTarget = nil
            }
        }
    }

    private func currentPosition() -> Double {
        pendingTarget ?? clamped(player.currentTime().seconds)
    }

    /// Ends a drag at `time`, which the player lands on exactly.
    func endScrub(at time: Double) {
        isScrubbing = false
        seek(to: time)
    }

    func setSpeed(_ speed: Double) {
        self.speed = speed
        player.defaultRate = Float(speed)
        if isPlaying { player.rate = Float(speed) }
    }

    /// The page is going: playback stops and the place is kept. Called when the item is left and when its window closes.
    func leave() {
        guard !isLeft else { return }
        if state == .ready {
            player.pause()
            isPlaying = false
            position = currentPosition()
            keepPlace()
        }
        isLeft = true
        if Self.playing === self { Self.playing = nil }
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        player.replaceCurrentItem(with: nil)
    }

    /// Keeps the place now, where the app is about to end.
    func keepPlaceNow() {
        guard state == .ready, !isLeft else { return }
        keepPlace()
    }

    // MARK: Place

    private func clamped(_ time: Double) -> Double {
        time.isFinite ? min(max(time, 0), duration) : 0
    }

    /// Keeps where the file is, or nothing where it is at its start or its end: a finished file opens at its start.
    private func keepPlace() {
        guard let item else { return }
        PlaybackPlaces.keep(position >= duration - 0.5 ? 0 : position, of: item, in: defaults)
    }

    // MARK: Watching the player

    private func observe() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        guard let current = player.currentItem else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: current, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.ended() }
            },
            center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: current, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.failedWhilePlaying() }
            },
        ]
    }

    private func tick() {
        guard state == .ready, !isLeft else { return }
        let stillPlaying = player.timeControlStatus != .paused
        // Something outside the page paused the player: the place is kept as a pause keeps it.
        if isPlaying, !stillPlaying {
            isPlaying = false
            position = currentPosition()
            keepPlace()
        } else if isPlaying, !isScrubbing, pendingTarget == nil {
            position = clamped(player.currentTime().seconds)
        }
    }

    private func ended() {
        guard state == .ready, !isLeft else { return }
        isPlaying = false
        position = duration
        keepPlace()
        seek(to: 0)
    }

    private func failedWhilePlaying() {
        guard !isLeft else { return }
        player.pause()
        isPlaying = false
        state = .unplayable
    }
}
