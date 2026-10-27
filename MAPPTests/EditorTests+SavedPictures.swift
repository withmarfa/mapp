import Foundation
import Testing
@testable import MAPP

/// A picture saved as a file on the item, on the page.
extension EditorTests {
    @Test func aSavedPictureReplacesItsAddressOnThePageAndTheSettingAnswersAgainWhenItGoes() async throws {
        let folder = try TemporaryFolder()
        let defaults = try #require(UserDefaults(suiteName: "SavedPicturePage-\(UUID().uuidString)"))
        defaults.set(RemotePictureSetting.never.rawValue, forKey: RemotePictureSetting.key)
        let site = PictureStub.newHost()
        let address = "https://\(site)/a.png"
        PictureStub.answer(address, with: .body([SamplePicture.png()]))
        let directory = folder.url.appending(path: "saved", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let saved = directory.appending(path: "pic.png")
        try SamplePicture.png(width: 5, height: 2).write(to: saved)
        let page = try await Page(pictures: WebPictures(
            cache: PictureCache(folder: folder.url.appending(path: "Cache")),
            fetcher: PictureFetcher(resolver: PictureStub.resolver, configuration: PictureStub.configuration),
            defaults: defaults))
        let note = page.library.add("![](\(address))\n")
        page.editor.load(note)
        let images = "document.querySelectorAll('.inkkit-file[data-inkkit-file-kind=image]').length"
        let labels = "[...document.querySelectorAll('.inkkit-file-label')].map(e => e.textContent)"

        let off = try await settle(page.editor, labels, as: [String].self) { $0 == ["\(site): Remote Pictures Are Off"] }
        #expect(off == ["\(site): Remote Pictures Are Off"], "with no file, the setting answers")

        let attached = page.library.attachPicture(saved, to: note.id, from: address)
        let shown = try await settle(page.editor, images, as: Int.self) { $0 == 1 }
        #expect(shown == 1, "the picture shows once its file is attached, with the note untouched")
        #expect(try await page.markdown() == nil)

        page.library.items[try #require(page.library.items.firstIndex { $0.id == attached })].state = .trashed
        let gone = try await settle(page.editor, labels, as: [String].self) { $0 == ["\(site): Remote Pictures Are Off"] }
        #expect(gone == ["\(site): Remote Pictures Are Off"], "a binned file leaves the setting to answer again")
        #expect(PictureStub.requests(to: address).isEmpty, "the website was never asked")
    }
}
