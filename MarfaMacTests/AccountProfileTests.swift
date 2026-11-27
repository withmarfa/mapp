import Foundation
import ImageIO
import Synchronization
import Testing

@testable import MarfaMac

@MainActor
@Suite(.hangLimit) struct AccountProfileTests {
    private func loaded(_ bench: OwnerBench) async -> AccountModel {
        if bench.scopes.isEmpty { bench.scopes = ["profile:write"] }
        bench.calls.state.withLock { $0.profile.name = "Mira Castell" }
        let account = AccountModel(context: bench.context)
        await account.load()
        return account
    }

    @Test func changingTheUsernameNeedsItsOwnScope() {
        #expect(ProfileField.email.mayWrite(holding: ["profile:write"].contains))
        #expect(!ProfileField.username.mayWrite(holding: ["profile:write", "profile.username:read"].contains))
        #expect(ProfileField.username.mayWrite(holding: ["profile.username:write"].contains))
    }

    @Test func clearingEmailWritesOnceAndKeepsTheUsername() async {
        let bench = OwnerBench()
        bench.calls.state.withLock { $0.profile.email = "someone@example.com" }
        let account = await loaded(bench)
        account.contactDrafts[.email] = ""
        await account.saveContact(.email)
        await account.saveContact(.email)
        #expect(account.profile?.email == nil)
        #expect(account.profile?.username == "mira")
        #expect(bench.calls.calls.filter { $0 == "setProfileContact" }.count == 1)
    }

    @Test func refusedContactEditsSurviveReloadAndHandover() async {
        let bench = OwnerBench()
        bench.calls.state.withLock {
            $0.profile.emailIsReadable = true
        }
        let account = await loaded(bench)
        #expect(account.picture == nil)
        #expect(account.profile?.email == nil)
        account.contactDrafts[.email] = "edited@example.com"
        bench.calls.fail("setProfileContact", with: .unreachable)
        await account.saveContact(.email)
        await account.load()
        #expect(account.contactDrafts[.email] == "edited@example.com")
        #expect(account.contactErrors[.email] != nil)
        #expect(account.takeDrafts().contains(.typed(title: "Email Not Changed", text: "edited@example.com")))
    }

    @Test func refusedContactsSurviveTheReleaseOfTheirAccountPage() async {
        let bench = OwnerBench()
        bench.scopes = ["profile:write", "profile.username:write"]
        let drafts = OwnerDrafts()
        weak var released: AccountModel?
        do {
            let account = await loaded(bench)
            released = account
            drafts.register(account)
            bench.calls.fail("setProfileContact", with: .unreachable)
            for (field, text) in [(ProfileContactField.email, "edited@example.com"), (.username, "castell")] {
                account.contactDrafts[field] = text
                await account.saveContact(field)
            }
            drafts.pageLeft(account)
        }
        #expect(released == nil)
        let kept = drafts.takeAll()
        #expect(kept.contains(.typed(title: "Email Not Changed", text: "edited@example.com")))
        #expect(kept.contains(.typed(title: "Username Not Changed", text: "castell")))
        #expect(drafts.takeAll().isEmpty)
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

    @Test func anEmailRefusedAfterLeavingThePageArrivesOnce() async throws {
        let bench = OwnerBench()
        let account = await loaded(bench)
        let drafts = OwnerDrafts()
        drafts.register(account)
        let gate = bench.calls.hold("setProfileContact")
        defer { gate.open() }
        account.contactDrafts[.email] = "edited@example.com"
        let saving = Task { await account.saveContact(.email) }
        try #require(await eventually { bench.calls.state.withLock { $0.waiting["setProfileContact"] == 1 } })
        drafts.pageLeft(account)
        #expect(drafts.takeAll().isEmpty)
        bench.calls.fail("setProfileContact", with: .unreachable)
        gate.open()
        await saving.value
        #expect(bench.late == [.typed(title: "Email Not Changed", text: "edited@example.com")])
        #expect(account.takeDrafts().isEmpty)
    }

    @Test func twoQuickSubmitsSendOneSave() async {
        let bench = OwnerBench()
        let account = await loaded(bench)
        let gate = bench.calls.hold("setProfileName")
        account.nameDraft = "Mira Castell-Owen"
        let first = Task { await account.saveName() }
        #expect(await eventually { bench.calls.state.withLock { $0.waiting["setProfileName"] == 1 } })
        #expect(account.isSavingName, "the field takes no typing while the name is sent")
        await account.saveName()
        gate.open()
        await first.value
        #expect(bench.calls.state.withLock { $0.namesSent } == ["Mira Castell-Owen"])
        #expect(account.profile?.name == "Mira Castell-Owen")
        #expect(!account.isSavingName)
    }

    @Test func aNameNotSentIsHandedOverWhenSettingsCloses() async {
        let bench = OwnerBench()
        let account = await loaded(bench)
        bench.calls.fail("setProfileName", with: .unreachable)
        account.nameDraft = "Mira Castell-Owen"
        await account.saveName()
        #expect(account.takeDrafts() == [.typed(title: String(localized: "Name Not Changed"), text: "Mira Castell-Owen")])
    }

    @Test func aNameWithAControlCharacterIsRefusedBeforeItIsSentAndHandedBackAsTyped() async {
        let bench = OwnerBench()
        let account = await loaded(bench)
        account.nameDraft = "Mira Castell\t"
        await account.saveName()
        #expect(account.nameError == ProfileName.Problem.hidden.line)
        #expect(account.nameDraft == "Mira Castell\t")
        #expect(!bench.calls.calls.contains("setProfileName"))
        #expect(account.takeDrafts() == [.typed(title: String(localized: "Name Not Changed"), text: "Mira Castell\t")])
    }

    @Test func aNameStillSentAtCloseIsHandedOverWhenItsSendFails() async {
        let bench = OwnerBench()
        let account = await loaded(bench)
        let gate = bench.calls.hold("setProfileName")
        bench.calls.state.withLock { $0.namesRefused = ["Mira C"] }
        account.nameDraft = "Mira C"
        let first = Task { await account.saveName() }
        #expect(await eventually { bench.calls.state.withLock { $0.waiting["setProfileName"] == 1 } })
        #expect(account.takeDrafts().isEmpty)
        gate.open()
        await first.value
        #expect(bench.late == [.typed(title: String(localized: "Name Not Changed"), text: "Mira C")])
    }

    @Test func aPictureTheServerTakesIsSentByteForByteAndOnlyASmallCopyIsKept() async throws {
        let bench = OwnerBench()
        let account = await loaded(bench)
        let original = try #require(Self.png(side: 600))
        #expect(ProfilePicture.isTaken(original))
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
        try original.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        await account.setPicture(from: file)
        #expect(bench.calls.state.withLock { $0.picturesSent } == [original])
        let kept = try #require(account.picture)
        let source = try #require(CGImageSourceCreateWithData(kept as CFData, nil))
        let width = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])?[kCGImagePropertyPixelWidth] as? Int
        #expect(width == ProfilePicture.shownSide)
    }

    @Test func onlyAPictureTheServerWouldRefuseIsDrawnAgain() throws {
        let png = try #require(Self.png(side: 8))
        #expect(ProfilePicture.prepared(png) == png)
        let animated = Self.animatedWebP()
        #expect(ProfilePicture.isTaken(animated))
        #expect(ProfilePicture.prepared(animated) == animated)
        let trailing = png + Data([0])
        #expect(!ProfilePicture.isTaken(trailing))
        let redrawn = try #require(ProfilePicture.prepared(trailing))
        #expect(redrawn != trailing)
        #expect(ProfilePicture.isTaken(redrawn))
        let gif = try #require(Self.encoded(side: 8, as: "com.compuserve.gif"))
        #expect(!ProfilePicture.isTaken(gif))
        #expect(ProfilePicture.prepared(gif).map(ProfilePicture.isTaken) == true)
    }

    private static func png(side: Int) -> Data? { encoded(side: side, as: "public.png") }

    private static func encoded(side: Int, as kind: String) -> Data? {
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(red: 0.4, green: 0.2, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side / 2, height: side))
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, kind as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// An animated WebP's marks, as the server reads them: a canvas and one frame that holds an image of its size.
    private static func animatedWebP() -> Data {
        func chunk(_ name: String, _ data: [UInt8]) -> [UInt8] {
            var out = Array(name.utf8) + withUnsafeBytes(of: UInt32(data.count).littleEndian, Array.init) + data
            if data.count % 2 == 1 { out.append(0) }
            return out
        }
        func le24(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value >> 16 & 0xFF)] }
        let bits = UInt32(7) | UInt32(7) << 14
        let image = chunk("VP8L", [0x2F] + withUnsafeBytes(of: bits.littleEndian, Array.init))
        let canvas = chunk("VP8X", [0x02, 0, 0, 0] + le24(7) + le24(7))
        let frame = chunk("ANMF", le24(0) + le24(0) + le24(7) + le24(7) + le24(0) + [0] + image)
        let body = Array("WEBP".utf8) + canvas + frame
        return Data(Array("RIFF".utf8) + withUnsafeBytes(of: UInt32(body.count).littleEndian, Array.init) + body)
    }
}
