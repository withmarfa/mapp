import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import MAPP

/// The size and page controls of an image's and a PDF's page: the sizes, what a typed answer means, the page label and
/// the arrows, and what each kind of file offers.
@MainActor
struct FileViewingTests {
    // MARK: Sizes

    @Test func zoomInAndOutMoveBetweenTheStepsAndStopAtTheEnds() {
        #expect(FileZoom.stepped(from: 1, up: true) == 1.5)
        #expect(FileZoom.stepped(from: 1, up: false) == 0.75)
        #expect(FileZoom.stepped(from: 4, up: true) == nil)
        #expect(FileZoom.stepped(from: 0.1, up: false) == nil)
    }

    @Test func aSizeBetweenStepsMovesToTheNextOneInThatDirection() {
        #expect(FileZoom.stepped(from: 0.34, up: true) == 0.5)
        #expect(FileZoom.stepped(from: 0.34, up: false) == 0.25)
        #expect(FileZoom.stepped(from: 8, up: false) == 4, "a small picture fitted past the range can still come down")
        #expect(FileZoom.stepped(from: 0.05, up: true) == 0.1)
    }

    @Test func aSizeThatReadsAsAStepIsNotSteppedToItself() {
        #expect(FileZoom.stepped(from: 0.7503, up: true) == 1)
        #expect(FileZoom.stepped(from: 0.7503, up: false) == 0.5)
    }

    @Test func aTypedSizeIsAPercentageHeldToTheRange() {
        #expect(FileZoom.parse("150") == 1.5)
        #expect(FileZoom.parse(" 75 % ") == 0.75)
        #expect(FileZoom.parse("33,5") == 0.335)
        #expect(FileZoom.parse("0") == 0.1)
        #expect(FileZoom.parse("5000") == 4)
        #expect(FileZoom.parse("9") == 0.1)
    }

    @Test func somethingThatIsNotASizeIsRefused() {
        for text in ["abc", "", "  ", "%", "-5", "1e3", "inf", "nan", "1.2.3", "12abc", "٣٠"] {
            #expect(FileZoom.parse(text) == nil, "\(text)")
        }
    }

    @Test func fitIsWhatShowsTheWholeFileInThePane() {
        #expect(FileZoom.fitScale(content: CGSize(width: 4000, height: 2000), in: CGSize(width: 800, height: 800)) == 0.2)
        #expect(FileZoom.fitScale(content: CGSize(width: 100, height: 100), in: CGSize(width: 800, height: 400)) == 4)
        #expect(FileZoom.fitScale(content: CGSize(width: 100, height: 100), in: .zero) == nil)
        #expect(FileZoom.fitScale(content: .zero, in: CGSize(width: 10, height: 10)) == nil)
    }

    @Test func aPhotoTakenOnItsSideSwapsItsSides() {
        #expect(FileZoom.orientedSize(width: 4000, height: 3000, orientation: 1) == CGSize(width: 4000, height: 3000))
        #expect(FileZoom.orientedSize(width: 4000, height: 3000, orientation: 6) == CGSize(width: 3000, height: 4000))
    }

    @Test func aFileOpensFittedAndReadsWhatFitGives() {
        let viewing = FileViewing(kind: .image)
        #expect(viewing.zoom == .fit)
        #expect(!viewing.canZoomIn, "nothing is known until the page measures")
        viewing.reportFit(0.4)
        #expect(viewing.sizeLabel == FileZoom.label(0.4))
        viewing.zoomIn()
        #expect(viewing.zoom == .scale(0.5))
        viewing.fit()
        #expect(viewing.zoom == .fit)
    }

    @Test func chosenSizesAreHeldToTheRange() {
        let viewing = FileViewing(kind: .image)
        viewing.setScale(50)
        #expect(viewing.zoom == .scale(4))
        viewing.setScale(0)
        #expect(viewing.zoom == .scale(0.1))
        #expect(!viewing.canZoomOut)
    }

    @Test func aSizeTheViewTookOnItsOwnBecomesTheChosenOne() {
        let viewing = FileViewing(kind: .pdf)
        viewing.adopt(scale: 1.25)
        #expect(viewing.zoom == .scale(1.25))
        #expect(viewing.isSize(1.25))
        #expect(!viewing.isSize(1.5))
    }

    // MARK: Pages

    @Test func thePageReadsTwoOfFourAndTheArrowsStopAtTheEnds() {
        let first = FilePages(count: 4, current: 1)
        #expect(first.label == "1 of 4")
        #expect(!first.canGoBack && first.canGoForward)
        let middle = FilePages(count: 4, current: 2)
        #expect(middle.label == "2 of 4")
        #expect(middle.canGoBack && middle.canGoForward)
        let last = FilePages(count: 4, current: 4)
        #expect(last.canGoBack && !last.canGoForward)
    }

    @Test func aOnePagePDFReadsOneOfOneWithBothArrowsDimmed() {
        let only = FilePages(count: 1)
        #expect(only.label == "1 of 1")
        #expect(!only.canGoBack && !only.canGoForward)
    }

    @Test func aPageOutsideTheDocumentIsHeldInside() {
        #expect(FilePages(count: 3, current: 9).current == 3)
        #expect(FilePages(count: 3, current: 0).current == 1)
        #expect(FilePages(count: 0).count == 1)
    }

    @Test func nextAndPreviousMoveOnePageAndTellTheView() {
        let viewing = FileViewing(kind: .pdf)
        var shown: [Int] = []
        viewing.showPage = { shown.append($0) }
        viewing.goToNextPage()
        #expect(shown.isEmpty, "a file without pages has nowhere to go")

        viewing.reportPages(count: 3, current: 1)
        viewing.goToPreviousPage()
        #expect(shown.isEmpty)
        viewing.goToNextPage()
        viewing.goToNextPage()
        viewing.goToNextPage()
        #expect(shown == [2, 3])
        #expect(viewing.pages?.label == "3 of 3")
        viewing.goToPreviousPage()
        #expect(shown == [2, 3, 2])
    }

    @Test func scrollingMovesThePageTheLabelReads() {
        let viewing = FileViewing(kind: .pdf)
        viewing.reportPages(count: 12, current: 1)
        viewing.reportPages(count: 12, current: 7)
        #expect(viewing.pages?.label == "7 of 12")
    }

    // MARK: Which controls and commands

    @Test func theKindOfFileIsToldByItsType() {
        #expect(FileViewKind.of(.pdf) == .pdf)
        #expect(FileViewKind.of(.png) == .image)
        #expect(FileViewKind.of(.jpeg) == .image)
        #expect(FileViewKind.of(.plainText) == nil)
        #expect(FileViewKind.of(.data) == nil)
    }

    @Test func theCornerHoldsWhatTheKindOfFileNeedsThenFocus() {
        #expect(PageCorner.buttons(layout: .file, hasReader: false, file: .image) == [.zoom, .focus])
        #expect(PageCorner.buttons(layout: .file, hasReader: false, file: .pdf) == [.pages, .zoom, .focus])
        #expect(PageCorner.buttons(layout: .file, hasReader: false, file: nil) == [.focus], "a file that is not ready, or any other, has Focus alone")
    }

    @Test func anImageOffersSizeCommandsAndAPDFAddsItsPages() {
        #expect(FileViewCommand.offered(for: .image) == [.zoomIn, .zoomOut, .actualSize, .zoomToFit])
        #expect(FileViewCommand.offered(for: .pdf) == [.zoomIn, .zoomOut, .actualSize, .zoomToFit, .nextPage, .previousPage])
    }

    @Test func theSizeKeysAreTheTextSizeKeysAndAFilePageTakesThem() {
        #expect(FileViewCommand.zoomIn.shortcut == KeyboardShortcut("+"))
        #expect(FileViewCommand.zoomOut.shortcut == KeyboardShortcut("-"))
        #expect(FileViewCommand.actualSize.shortcut == KeyboardShortcut("0"))
        #expect(FileViewCommand.nextPage.shortcut == nil)
    }

    @Test func aCommandIsEnabledOnlyWhereItChangesSomething() {
        let viewing = FileViewing(kind: .pdf)
        viewing.reportFit(0.5)
        viewing.reportPages(count: 2, current: 1)
        #expect(FileViewCommand.zoomToFit.isEnabled(on: viewing) == false)
        #expect(FileViewCommand.actualSize.isEnabled(on: viewing))
        #expect(FileViewCommand.previousPage.isEnabled(on: viewing) == false)
        #expect(FileViewCommand.nextPage.isEnabled(on: viewing))
        FileViewCommand.actualSize.perform(on: viewing)
        #expect(viewing.zoom == .scale(1))
        #expect(FileViewCommand.actualSize.isEnabled(on: viewing) == false)
    }

    // MARK: The window

    @Test func theWindowOffersAFileToItsItemAndWithdrawsIt() {
        let details = DetailsPresentation()
        let item = ItemID.mint()
        let viewing = FileViewing(kind: .image)
        details.offerFileView(viewing, for: item)
        #expect(details.fileViewing(of: item) === viewing)
        #expect(details.fileViewing(of: .mint()) == nil)
        details.withdrawFileView(FileViewing(kind: .image))
        #expect(details.fileViewing(of: item) === viewing, "another file's page going away leaves it")
        details.withdrawFileView(viewing)
        #expect(details.fileViewing(of: item) == nil)
    }

    @Test func movingToAnotherItemDropsTheFilesControls() {
        let details = DetailsPresentation()
        let item = ItemID.mint()
        details.offerFileView(FileViewing(kind: .pdf), for: item)
        details.pageShows(item)
        #expect(details.fileViewing(of: item) != nil)
        details.pageShows(.mint())
        #expect(details.fileViewing(of: item) == nil)
    }
}
