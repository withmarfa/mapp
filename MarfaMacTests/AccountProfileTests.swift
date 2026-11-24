import AppKit
import Foundation
import ImageIO
import Synchronization
import Testing
import UniformTypeIdentifiers

@testable import MarfaMac

@MainActor
@Suite(.hangLimit) struct AccountProfileTests {
    private func loaded(_ bench: OwnerBench) async -> AccountModel {
        bench.calls.state.withLock { $0.profile.name = "Mira Castell" }
        let account = AccountModel(context: bench.context)
        await account.load()
        return account
    }

    @Test func aRefusedNameKeepsWhatWasTypedThroughAReadAgain() async {
        let bench = OwnerBench()
        let account = await loaded(bench)
        bench.calls.fail("setProfileName", with: .refused("The name can’t hold control characters."))
        account.nameDraft = "Mira Castell-Owen"
        await account.saveName()
        #expect(account.nameDraft == "Mira Castell-Owen")
        #expect(account.nameError != nil)
        await account.load()
        #expect(account.nameDraft == "Mira Castell-Owen")
        #expect(account.profile?.name == "Mira Castell")
    }

    @Test func aNameTypedWhileOneIsSentIsSentAfterIt() async throws {
        let bench = OwnerBench()
        let account = await loaded(bench)
        let gate = bench.calls.hold("setProfileName")
        account.nameDraft = "Mira C"
        let first = Task { await account.saveName() }
        try await eventually { bench.calls.state.withLock { $0.waiting["setProfileName"] == 1 } }
        account.nameDraft = "Mira Castell-Owen"
        await account.saveName()
        gate.open()
        try await eventually { bench.calls.state.withLock { $0.waiting["setProfileName"] == 1 } }
        gate.open()
        await first.value
        #expect(bench.calls.state.withLock { $0.namesSent } == ["Mira C", "Mira Castell-Owen"])
        #expect(account.nameDraft == "Mira Castell-Owen")
        #expect(account.profile?.name == "Mira Castell-Owen")
    }

    @Test func aNameNotSentIsHandedOverWhenSettingsCloses() async {
        let bench = OwnerBench()
        let account = await loaded(bench)
        bench.calls.fail("setProfileName", with: .unreachable)
        account.nameDraft = "Mira Castell-Owen"
        await account.saveName()
        #expect(account.takeDrafts() == [.typed(title: String(localized: "Name Not Changed"), text: "Mira Castell-Owen")])
    }

    @Test func anEmptyNameIsNeverSent() async {
        let bench = OwnerBench()
        let account = await loaded(bench)
        account.nameDraft = "   "
        await account.saveName()
        #expect(bench.calls.state.withLock { $0.namesSent }.isEmpty)
        #expect(account.nameError != nil)
        #expect(account.nameDraft == "   ")
    }

    // MARK: The picture sent

    private static func picture(_ kind: UTType, width: Int, height: Int) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(red: 0.6, green: 0.3, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, kind.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private static func described(_ data: Data) throws -> (kind: String, width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (
            try #require(CGImageSourceGetType(source) as String?), try #require(properties[kCGImagePropertyPixelWidth] as? Int),
            try #require(properties[kCGImagePropertyPixelHeight] as? Int)
        )
    }

    @Test func aPictureThatFitsIsSentAsItIs() throws {
        let png = try Self.picture(.png, width: 400, height: 300)
        #expect(ProfilePicture.prepared(png) == png)
    }

    @Test func aKindTheServerRefusesIsDrawnAgainAtItsSize() throws {
        let tiff = try Self.picture(.tiff, width: 400, height: 300)
        let sent = try #require(ProfilePicture.prepared(tiff))
        let read = try Self.described(sent)
        #expect([UTType.png.identifier, UTType.jpeg.identifier].contains(read.kind))
        #expect(read.width == 400 && read.height == 300)
    }

    @Test func aPictureLargerThanTheServerKeepsIsDrawnToFit() throws {
        let large = try Self.picture(.png, width: 5000, height: 2500)
        let sent = try #require(ProfilePicture.prepared(large))
        let read = try Self.described(sent)
        #expect(read.width == ProfilePicture.longestSide && read.height == 2048)
        #expect(sent.count <= ProfilePicture.largest)
    }

    @Test func aFileThatIsNoPictureIsNotSent() {
        #expect(ProfilePicture.prepared(Data("not a picture".utf8)) == nil)
    }
}
