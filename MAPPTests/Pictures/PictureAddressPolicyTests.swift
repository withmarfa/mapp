import Foundation
import Testing
@testable import MAPP

@Suite(.hangLimit) struct PictureAddressPolicyTests {
    @Test(arguments: [
        ("93.184.216.34", true), ("8.8.8.8", true), ("1.1.1.1", true), ("172.32.0.1", true), ("100.63.255.255", true),
        ("127.0.0.1", false), ("10.0.0.1", false), ("172.16.5.5", false), ("172.31.255.255", false), ("192.168.1.1", false),
        ("169.254.0.1", false), ("100.64.0.1", false), ("0.0.0.0", false), ("224.0.0.1", false), ("255.255.255.255", false),
        ("198.18.0.1", false), ("192.0.2.1", false),
        ("2606:4700:4700::1111", true), ("::1", false), ("::", false), ("fe80::1", false), ("fc00::1", false), ("fd12::1", false),
        ("ff02::1", false), ("2001:db8::1", false), ("::ffff:127.0.0.1", false), ("::ffff:10.0.0.1", false),
        ("::ffff:8.8.8.8", true), ("64:ff9b::7f00:1", false), ("64:ff9b::808:808", true), ("2002:7f00:1::", false),
        ("0:0:0:0:ffff:0:7f00:1", false), ("::ffff:0:10.0.0.1", false), ("::ffff:0:a9fe:a9fe", false),
        ("::ffff:0:808:808", true), ("0:0:0:0:ffff:0:5db8:d822", true),
    ])
    func addressesAreSortedIntoPublicAndNot(text: String, isPublic: Bool) throws {
        let address = try #require(IPAddress(literal: text))

        #expect(address.isPublic == isPublic)
    }

    @Test(arguments: ["2130706433", "0x7f.1", "127.1", "017700000001"])
    func theOldWaysOfWritingAnAddressAreRead(text: String) throws {
        let address = try #require(IPAddress(literal: text))

        #expect(!address.isPublic)
    }

    @Test(arguments: ["example.com", "", "a.b.c", "localhost"])
    func aNameIsNotAnAddress(text: String) {
        #expect(IPAddress(literal: text) == nil)
    }

    @Test func aTrailingDotDoesNotHideALocalName() async {
        await #expect(throws: PictureFailure.privateNetwork) {
            try await PictureAddressPolicy.check(URL(string: "https://printer.local./a.png")!, resolver: PictureStub.resolver)
        }
    }

    @Test(arguments: ["https://[0:0:0:0:ffff:0:7f00:1]/", "https://[::ffff:0:127.0.0.1]/a.png", "https://[::ffff:0:a00:1]/a.png"])
    func anIPv4TranslatedAddressIsJudgedByTheAddressInsideIt(address: String) async {
        await #expect(throws: PictureFailure.privateNetwork) {
            try await PictureAddressPolicy.check(URL(string: address)!, resolver: PictureStub.resolver)
        }
    }

    @Test func anIPv4TranslatedPublicAddressIsLetThrough() async throws {
        try await PictureAddressPolicy.check(URL(string: "https://[::ffff:0:808:808]/a.png")!, resolver: PictureStub.resolver)
    }

    @Test func aNameThatIsNotAnsweredInTimeIsRefusedAsTooSlow() async {
        let started = ContinuousClock.now
        await #expect(throws: PictureFailure.tooSlow) {
            try await PictureAddressPolicy.check(
                URL(string: "https://images.example.com/a.png")!, resolver: { _ in try await Task.sleep(for: .seconds(600)); return [] },
                timeout: .milliseconds(100))
        }
        #expect(ContinuousClock.now - started < .seconds(30), "the check ended at its timeout, not when the lookup did")
    }

    @Test func aLookupThatAnswersInTimeIsUsed() async {
        await #expect(throws: PictureFailure.privateNetwork) {
            try await PictureAddressPolicy.check(
                URL(string: "https://images.example.com/a.png")!, resolver: { _ in [IPAddress(bytes: [10, 0, 0, 1])] }, timeout: .seconds(30))
        }
    }

    @Test func theSystemResolverAnswersAfterTheLookupRanOffThePool() async throws {
        let addresses = try await PictureAddressPolicy.system("localhost")

        #expect(!addresses.isEmpty)
        #expect(addresses.allSatisfy { !$0.isPublic })
    }

    @Test func aPublicNameIsLetThrough() async throws {
        try await PictureAddressPolicy.check(URL(string: "https://images.example.com/a.png")!, resolver: PictureStub.resolver)
    }
}

@Suite struct PictureFormatTests {
    private func bytes(_ prefix: [UInt8], _ text: String = "", padded to: Int = 64) -> Data {
        var data = Data(prefix) + Data(text.utf8)
        while data.count < to { data.append(0) }
        return data
    }

    @Test func eachKindOfPictureIsToldByItsFirstBytes() {
        #expect(PictureFormat(sniffing: SamplePicture.png()) == .png)
        #expect(PictureFormat(sniffing: bytes([0xFF, 0xD8, 0xFF, 0xE0])) == .jpeg)
        #expect(PictureFormat(sniffing: bytes([], "GIF89a")) == .gif)
        #expect(PictureFormat(sniffing: bytes([], "GIF87a")) == .gif)
        #expect(PictureFormat(sniffing: bytes([], "RIFF\0\0\0\0WEBPVP8 ")) == .webp)
        #expect(PictureFormat(sniffing: bytes([0, 0, 0, 24], "ftypheic\0\0\0\0mif1heic")) == .heic)
        #expect(PictureFormat(sniffing: bytes([0, 0, 0, 24], "ftypavif\0\0\0\0mif1avif")) == .avif)
    }

    @Test func nothingElseIsAPicture() {
        #expect(PictureFormat(sniffing: SamplePicture.svg) == nil)
        #expect(PictureFormat(sniffing: SamplePicture.page) == nil)
        #expect(PictureFormat(sniffing: Data()) == nil)
        #expect(PictureFormat(sniffing: bytes([0, 0, 0, 24], "ftypmp42\0\0\0\0mp42isom")) == nil)
        #expect(PictureFormat(sniffing: bytes([], "RIFF\0\0\0\0WAVEfmt ")) == nil)
    }
}
