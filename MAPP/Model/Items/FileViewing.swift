import CoreGraphics
import Foundation
import Observation
import UniformTypeIdentifiers

/// The kinds of file whose page has a corner of its own: an image's zoom control, and a PDF's page control with the
/// same zoom. Any other file has Focus alone.
nonisolated enum FileViewKind: Equatable, Sendable {
    case image, pdf

    /// The kind a file of `type` is shown as, tested in the order the page chooses its view.
    static func of(_ type: UTType) -> FileViewKind? {
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        return nil
    }
}

/// How large a file's page is drawn: fitted to the window, or at a size, where 1 is the file's own size (a PDF's page
/// in points, an image's pixels as points).
nonisolated enum FileZoom: Equatable, Sendable {
    case fit
    case scale(Double)

    /// The sizes a person can reach, from 10% to 400%. An image at four times its size is already tens of thousands of
    /// points across.
    static let range = 0.1...4.0
    /// The sizes the menu lists, after Fit.
    static let menuSizes: [Double] = [0.5, 0.75, 1, 1.5, 2]
    /// The sizes Zoom In and Zoom Out move between.
    static let steps: [Double] = [0.1, 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4]

    static func clamped(_ scale: Double) -> Double {
        min(max(scale, range.lowerBound), range.upperBound)
    }

    /// A size as the whole percent it is shown as.
    static func percent(of scale: Double) -> Int { Int((scale * 100).rounded()) }

    /// The size a step from `scale` reaches, or nil at the end of the range. The next step is judged on the percent
    /// shown, so a size that reads 100% is not stepped to 100%.
    static func stepped(from scale: Double, up: Bool) -> Double? {
        let shown = percent(of: scale)
        return up ? steps.first { percent(of: $0) > shown } : steps.last { percent(of: $0) < shown }
    }

    /// The size a typed answer means, such as "150", "150 %" or "1,000", held to the range, or nil where it is not a
    /// size. The locale says which mark groups thousands, which is dropped, and which is the decimal point, which is
    /// read as one; a point is also read as one where the locale does not use it for grouping. Zero and sizes past the
    /// range are not refused: they take the nearest end, which the control then shows.
    static func parse(_ text: String, locale: Locale = .current) -> Double? {
        var digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasSuffix("%") {
            digits.removeLast()
        }
        // Spaces, including the narrow and no-break ones some locales group with, never belong to the number.
        digits = String(digits.filter { !$0.isWhitespace })
        let group = locale.groupingSeparator.map { String($0.filter { !$0.isWhitespace }) } ?? ","
        let decimal = locale.decimalSeparator ?? "."
        if !group.isEmpty, group != decimal { digits = digits.replacingOccurrences(of: group, with: "") }
        if decimal != "." { digits = digits.replacingOccurrences(of: decimal, with: ".") }
        let isNumber = !digits.isEmpty
            && digits.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") }
            && digits.filter { $0 == "." }.count <= 1
        guard isNumber, let percent = Double(digits), percent.isFinite else { return nil }
        return clamped(percent / 100)
    }

    /// The size drawn, given what Fit gives.
    func scale(fit: Double) -> Double {
        switch self {
        case .fit: fit
        case .scale(let scale): scale
        }
    }

    /// The size that shows `content` whole in `pane`, or nil while either has no size.
    static func fitScale(content: CGSize, in pane: CGSize) -> Double? {
        guard content.width > 0, content.height > 0, pane.width > 0, pane.height > 0 else { return nil }
        return min(pane.width / content.width, pane.height / content.height)
    }

    /// What Fit gives an image: it never enlarges a picture past its own size, as Preview does, and the control never
    /// shows a size the range refuses.
    static func imageFit(content: CGSize, in pane: CGSize) -> Double? {
        fitScale(content: content, in: pane).map { clamped(min($0, 1)) }
    }

    /// A size as the control and the menu write it, such as "100%".
    static func label(_ scale: Double) -> String {
        (Double(percent(of: scale)) / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    /// The range as the field names it, such as "10%–400%".
    static var rangeLabel: String { "\(label(range.lowerBound))–\(label(range.upperBound))" }

    /// An image's size in pixels once its orientation is applied: a photo taken on its side has its sides swapped.
    static func orientedSize(width: Double, height: Double, orientation: Int) -> CGSize {
        (5...8).contains(orientation) ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }
}

/// Where a PDF is, as "2 of 4", and what the back and forward arrows can do.
nonisolated struct FilePages: Equatable, Sendable {
    let count: Int
    /// The page showing, from 1.
    let current: Int

    /// A document with no pages has none to show, so a count under one is read as one and the page is held to it.
    init(count: Int, current: Int = 1) {
        self.count = max(count, 1)
        self.current = min(max(current, 1), self.count)
    }

    var label: String { String(localized: "\(current) of \(count)", comment: "A PDF's page and how many it has, such as 2 of 4.") }
    var canGoBack: Bool { current > 1 }
    var canGoForward: Bool { current < count }
}

/// A file's page as the window's corner and menus reach it: the size it is drawn at and, for a PDF, the page showing.
/// The page makes one for the file it has ready and offers it to the window (`DetailsPresentation.offerFileView`), so
/// a file that is still downloading, failed to load or has no pages has none. It belongs to that file, so another
/// item's page never inherits a size or a half-typed answer.
@Observable
final class FileViewing {
    let kind: FileViewKind
    /// The size the person chose. A file opens fitted.
    private(set) var zoom: FileZoom = .fit
    /// The size Fit gives at the moment, which the page measures and reports.
    private(set) var fitScale: Double?
    /// A PDF's page showing, once it has pages.
    private(set) var pages: FilePages?
    /// Whether the size field is open, which the corner reads so Escape closes the field and nothing else.
    var isEditingSize = false
    /// Scrolls the PDF to a page, from 1, and returns the page the view then shows. The PDF's view sets it.
    @ObservationIgnored var showPage: ((Int) -> Int)?

    init(kind: FileViewKind) {
        self.kind = kind
    }

    /// The size drawn now, as a fraction of the file's own size, once it is known.
    var scale: Double? { zoom == .fit ? fitScale : zoom.scale(fit: 1) }

    /// The size the control reads. Before the page has measured it, it says what is chosen.
    var sizeLabel: String { scale.map(FileZoom.label) ?? String(localized: "Fit") }

    var canZoomIn: Bool { scale.map { FileZoom.stepped(from: $0, up: true) != nil } ?? false }
    var canZoomOut: Bool { scale.map { FileZoom.stepped(from: $0, up: false) != nil } ?? false }

    /// Whether the chosen size is `size`, for the tick in the menu.
    func isSize(_ size: Double) -> Bool {
        if case .scale(let chosen) = zoom { FileZoom.percent(of: chosen) == FileZoom.percent(of: size) } else { false }
    }

    func fit() { zoom = .fit }

    func setScale(_ scale: Double) { zoom = .scale(FileZoom.clamped(scale)) }

    func zoomIn() { step(up: true) }

    func zoomOut() { step(up: false) }

    private func step(up: Bool) {
        guard let scale, let next = FileZoom.stepped(from: scale, up: up) else { return }
        zoom = .scale(next)
    }

    /// The page measured what Fit gives.
    func reportFit(_ scale: Double) {
        if fitScale != scale { fitScale = scale }
    }

    /// The PDF's own view was zoomed, as by a pinch, to a size that is now the chosen one.
    func adopt(scale: Double) {
        if case .scale(let chosen) = zoom, abs(chosen - scale) < 0.0005 { return }
        zoom = .scale(FileZoom.clamped(scale))
    }

    // MARK: Pages

    /// The PDF has `count` pages, and is showing `current`.
    func reportPages(count: Int, current: Int) {
        let reported = FilePages(count: count, current: current)
        if pages != reported { pages = reported }
    }

    func goToNextPage() { go(by: 1) }

    func goToPreviousPage() { go(by: -1) }

    private func go(by step: Int) {
        guard let pages else { return }
        let target = pages.current + step
        guard (1...pages.count).contains(target) else { return }
        // The label says the page the view reached, which is not always the one asked for.
        reportPages(count: pages.count, current: showPage?(target) ?? pages.current)
    }
}
