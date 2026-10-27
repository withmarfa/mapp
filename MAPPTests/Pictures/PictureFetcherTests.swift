import Foundation
import Testing
@testable import MAPP

@Suite struct PictureFetcherTests {
    let folder: TemporaryFolder

    init() throws {
        folder = try TemporaryFolder()
    }

    private func fetcher(
        limits: PictureFetcher.Limits = .init(), resolver: @escaping PictureAddressPolicy.Resolver = PictureStub.resolver
    ) -> PictureFetcher {
        PictureFetcher(limits: limits, resolver: resolver, configuration: PictureStub.configuration)
    }

    private func failure(_ address: String, using fetcher: PictureFetcher? = nil) async -> PictureFailure? {
        do {
            _ = try await (fetcher ?? self.fetcher()).fetch(URL(string: address)!, into: folder.url)
            return nil
        } catch {
            return error
        }
    }

    private var leftovers: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.url.path)) ?? []
    }

    // MARK: What is fetched

    @Test func aPictureIsFetchedIntoAFileOfItsOwn() async throws {
        let address = "https://\(PictureStub.newHost())/a.png"
        PictureStub.answer(address, with: .body([SamplePicture.png(width: 12, height: 7)]))

        let picture = try await fetcher().fetch(URL(string: address)!, into: folder.url)

        #expect(picture.format == .png)
        #expect(picture.width == 12)
        #expect(picture.height == 7)
        #expect(try Data(contentsOf: picture.file) == SamplePicture.png(width: 12, height: 7))
    }

    @Test func theRequestCarriesNothingOfThePersonOrTheNote() async throws {
        let address = "https://\(PictureStub.newHost())/a.png"
        PictureStub.answer(address, with: .body([SamplePicture.png()]))

        _ = try await fetcher().fetch(URL(string: address)!, into: folder.url)

        let request = try #require(PictureStub.requests(to: address).first)
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "MAPP")
        #expect(request.value(forHTTPHeaderField: "Referer") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.httpShouldHandleCookies == false)
    }

    @Test func theKindIsToldByTheFirstBytesNotByTheServer() async throws {
        let address = "https://\(PictureStub.newHost())/a"
        PictureStub.answer(address, with: .body([SamplePicture.png()], type: "text/html"))

        let picture = try await fetcher().fetch(URL(string: address)!, into: folder.url)

        #expect(picture.format == .png)
    }

    @Test func aPictureArrivingInPiecesIsKeptWhole() async throws {
        let address = "https://\(PictureStub.newHost())/a.png"
        let png = SamplePicture.png(width: 20, height: 20)
        let middle = png.count / 2
        PictureStub.answer(address, with: .body([png.prefix(10), png[10..<middle], png[middle...]].map { Data($0) }, announce: false))

        let picture = try await fetcher().fetch(URL(string: address)!, into: folder.url)

        #expect(try Data(contentsOf: picture.file) == png)
    }

    // MARK: Where it may be fetched from

    @Test func anAddressWithoutTLSIsRefusedBeforeAnyRequest() async {
        let address = "http://\(PictureStub.newHost())/a.png"
        PictureStub.answer(address, with: .body([SamplePicture.png()]))

        #expect(await failure(address) == .notSecure)
        #expect(PictureStub.requests(to: address).isEmpty)
    }

    @Test func aSignInInTheAddressIsRefused() async {
        let host = PictureStub.newHost()
        let address = "https://person:secret@\(host)/a.png"
        PictureStub.answer("https://\(host)/a.png", with: .body([SamplePicture.png()]))

        #expect(await failure(address) == .hasCredentials)
        #expect(PictureStub.requests(to: "https://\(host)/").isEmpty)
    }

    @Test(arguments: [
        "https://127.0.0.1/a.png", "https://10.1.2.3/a.png", "https://192.168.0.10/a.png", "https://172.16.0.1/a.png",
        "https://169.254.169.254/latest/meta-data", "https://100.64.0.1/a.png", "https://0.0.0.0/a.png",
        "https://2130706433/a.png", "https://0x7f.1/a.png", "https://[::1]/a.png", "https://[fe80::1]/a.png",
        "https://[fd00::1]/a.png", "https://[ff02::1]/a.png", "https://[::ffff:10.0.0.1]/a.png",
        "https://localhost/a.png", "https://printer.local/a.png", "https://intranet/a.png", "https://app.localhost/a.png",
    ])
    func anAddressOnThisMachineOrANetworkNearItIsRefused(address: String) async {
        #expect(await failure(address) == .privateNetwork)
    }

    @Test func aNameThatResolvesToAPrivateAddressIsRefusedBeforeAnyRequest() async {
        let address = "https://\(PictureStub.newHost())/a.png"
        PictureStub.answer(address, with: .body([SamplePicture.png()]))

        let reason = await failure(address, using: fetcher(resolver: { _ in [IPAddress(bytes: [10, 0, 0, 5])] }))

        #expect(reason == .privateNetwork)
        #expect(PictureStub.requests(to: address).isEmpty)
    }

    @Test func aNameWithOnePrivateAddressAmongPublicOnesIsRefused() async {
        let address = "https://\(PictureStub.newHost())/a.png"
        PictureStub.answer(address, with: .body([SamplePicture.png()]))

        let reason = await failure(
            address, using: fetcher(resolver: { _ in [IPAddress(bytes: [93, 184, 216, 34]), IPAddress(bytes: [192, 168, 1, 1])] }))

        #expect(reason == .privateNetwork)
    }

    @Test func aNameThatDoesNotResolveIsRefused() async {
        let address = "https://\(PictureStub.newHost())/a.png"

        #expect(await failure(address, using: fetcher(resolver: { _ in throw PictureFailure.unresolved })) == .unresolved)
        #expect(await failure(address, using: fetcher(resolver: { _ in [] })) == .unresolved)
    }

    @Test func aLookupCountsInTheTimeLimitAndEndsAtIt() async {
        let address = "https://\(PictureStub.newHost())/a.png"
        PictureStub.answer(address, with: .body([SamplePicture.png()]))
        let started = ContinuousClock.now

        let reason = await failure(
            address, using: fetcher(limits: .init(time: .milliseconds(300)), resolver: { _ in try await Task.sleep(for: .seconds(600)); return [] }))

        #expect(reason == .tooSlow)
        #expect(ContinuousClock.now - started < .seconds(30), "it did not wait for the lookup")
        #expect(PictureStub.requests(to: address).isEmpty)
        #expect(leftovers.isEmpty)
    }

    @Test func aLookupIsGivenItsOwnLimitWithinTheTimeLimit() async {
        let address = "https://\(PictureStub.newHost())/a.png"

        let reason = await failure(
            address,
            using: fetcher(limits: .init(time: .seconds(300), resolve: .milliseconds(100)), resolver: { _ in try await Task.sleep(for: .seconds(600)); return [] }))

        #expect(reason == .tooSlow)
    }

    // MARK: Sign-ins and certificates

    private func disposition(of method: String) -> URLSession.AuthChallengeDisposition {
        PictureTransfer.disposition(for: URLProtectionSpace(host: "example.com", port: 443, protocol: "https", realm: nil, authenticationMethod: method))
    }

    @Test(arguments: [
        NSURLAuthenticationMethodClientCertificate, NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest,
        NSURLAuthenticationMethodNTLM, NSURLAuthenticationMethodNegotiate, NSURLAuthenticationMethodDefault,
    ])
    func aRequestForACertificateOrASignInIsRejected(method: String) {
        #expect(disposition(of: method) == .rejectProtectionSpace)
    }

    @Test func onlyTheCheckOfTheServersCertificateIsLeftToTheSystem() {
        #expect(disposition(of: NSURLAuthenticationMethodServerTrust) == .performDefaultHandling)
    }

    /// The delegate's own methods, as the session calls them, for a challenge of each kind and for both levels.
    @Test(arguments: [NSURLAuthenticationMethodClientCertificate, NSURLAuthenticationMethodHTTPBasic])
    func theSessionsChallengesAreAnsweredWithoutACredential(method: String) async {
        let transfer = PictureTransfer(limits: .init(), resolver: PictureStub.resolver, file: folder.url.appending(path: "f"), deadline: .now.advanced(by: .seconds(30)))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "https://example.com/a.png")!)
        let challenge = URLAuthenticationChallenge(
            protectionSpace: URLProtectionSpace(host: "example.com", port: 443, protocol: "https", realm: nil, authenticationMethod: method),
            proposedCredential: nil, previousFailureCount: 0, failureResponse: nil, error: nil, sender: ChallengeSender())

        let answers = await withCheckedContinuation { (continuation: CheckedContinuation<[String], Never>) in
            transfer.urlSession(session, didReceive: challenge) { first, credential in
                transfer.urlSession(session, task: task, didReceive: challenge) { second, other in
                    continuation.resume(returning: ["\(first)", "\(credential == nil)", "\(second)", "\(other == nil)"])
                }
            }
        }

        #expect(answers == ["\(URLSession.AuthChallengeDisposition.rejectProtectionSpace)", "true", "\(URLSession.AuthChallengeDisposition.rejectProtectionSpace)", "true"])
    }

    // MARK: Redirects

    @Test func aRedirectToAPrivateAddressIsRefusedAndNotFollowed() async {
        let start = "https://\(PictureStub.newHost())/a.png"
        PictureStub.answer(start, with: .redirect("https://169.254.169.254/latest/meta-data"))

        #expect(await failure(start) == .privateNetwork)
        #expect(PictureStub.requests(to: start).count == 1)
    }

    @Test func aRedirectToANameThatResolvesPrivatelyIsRefusedAndNotFollowed() async {
        let inner = PictureStub.newHost()
        let start = "https://\(PictureStub.newHost())/a.png"
        PictureStub.answer(start, with: .redirect("https://\(inner)/b.png"))
        PictureStub.answer("https://\(inner)/b.png", with: .body([SamplePicture.png()]))
        let resolver: PictureAddressPolicy.Resolver = { name in
            name == inner ? [IPAddress(bytes: [10, 0, 0, 9])] : [IPAddress(bytes: [93, 184, 216, 34])]
        }

        #expect(await failure(start, using: fetcher(resolver: resolver)) == .privateNetwork)
        #expect(PictureStub.requests(to: "https://\(inner)/").isEmpty)
    }

    @Test func aRedirectToAnAddressWithoutTLSIsRefused() async {
        let start = "https://\(PictureStub.newHost())/a.png"
        PictureStub.answer(start, with: .redirect("http://\(PictureStub.newHost())/b.png"))

        #expect(await failure(start) == .notSecure)
    }

    private func chain(of length: Int) -> String {
        let host = PictureStub.newHost()
        for step in 0..<length {
            PictureStub.answer("https://\(host)/\(step)", with: .redirect("https://\(host)/\(step + 1)"))
        }
        PictureStub.answer("https://\(host)/\(length)", with: .body([SamplePicture.png()]))
        return "https://\(host)/0"
    }

    @Test func fourRedirectsAreFollowed() async throws {
        let picture = try await fetcher().fetch(URL(string: chain(of: 4))!, into: folder.url)

        #expect(picture.format == .png)
    }

    @Test func aFifthRedirectIsRefused() async {
        let start = chain(of: 5)

        #expect(await failure(start) == .tooManyRedirects)
        #expect(PictureStub.requests(to: start).count == 5)
    }

    // MARK: What arrives

    @Test func aPageThatIsNotAPictureIsRefusedWhateverTheServerCalledIt() async {
        let address = "https://\(PictureStub.newHost())/a.png"
        PictureStub.answer(address, with: .body([SamplePicture.page], type: "image/png"))

        #expect(await failure(address) == .notAPicture)
        #expect(leftovers.isEmpty)
    }

    @Test func anSVGIsRefusedEvenWhenItIsServedAsOne() async {
        let address = "https://\(PictureStub.newHost())/a.svg"
        PictureStub.answer(address, with: .body([SamplePicture.svg], type: "image/svg+xml"))

        #expect(await failure(address) == .notAPicture)
        #expect(leftovers.isEmpty)
    }

    @Test func aStatusOtherThanOKIsRefused() async {
        let address = "https://\(PictureStub.newHost())/a.png"
        PictureStub.answer(address, with: .body([SamplePicture.png()], status: 404))

        #expect(await failure(address) == .badStatus(404))
    }

    @Test func aPictureAnnouncedAsTooLargeIsRefusedBeforeItsBodyIsRead() async {
        let address = "https://\(PictureStub.newHost())/a.png"
        let png = SamplePicture.png(width: 64, height: 64)
        PictureStub.answer(address, with: .body([png]))

        #expect(await failure(address, using: fetcher(limits: .init(bytes: png.count - 1))) == .tooLarge)
        #expect(leftovers.isEmpty)
    }

    @Test func aBodyThatPassesTheLimitWhileItArrivesIsStopped() async {
        let address = "https://\(PictureStub.newHost())/a.png"
        let png = SamplePicture.png(width: 64, height: 64)
        let pieces = stride(from: 0, to: png.count, by: 64).map { Data(png[$0..<min($0 + 64, png.count)]) }
        PictureStub.answer(address, with: .body(pieces, announce: false))

        #expect(await failure(address, using: fetcher(limits: .init(bytes: png.count / 2))) == .tooLarge)
        #expect(leftovers.isEmpty)
    }

    @Test func aBodyThatNeverFinishesIsStoppedAtTheTimeLimit() async {
        let address = "https://\(PictureStub.newHost())/a.png"
        PictureStub.answer(address, with: .stall(SamplePicture.png().prefix(80)))

        #expect(await failure(address, using: fetcher(limits: .init(time: .milliseconds(300)))) == .tooSlow)
        #expect(leftovers.isEmpty)
    }

    @Test(arguments: [(1, 40), (40, 1), (1, 1)])
    func aPictureOnePixelWideOrHighIsRefused(width: Int, height: Int) async {
        let address = "https://\(PictureStub.newHost())/a.png"
        PictureStub.answer(address, with: .body([SamplePicture.png(width: width, height: height)]))

        #expect(await failure(address) == .tooSmall)
        #expect(leftovers.isEmpty)
    }

    @Test func aFailedFetchLeavesNothingInTheFolder() async {
        let address = "https://\(PictureStub.newHost())/a.png"
        PictureStub.answer(address, with: .body([SamplePicture.page]))

        _ = await failure(address)

        #expect(leftovers.isEmpty)
    }
}

/// Receives what a challenge reports to its sender, which a test of the delegate does not use.
private final class ChallengeSender: NSObject, URLAuthenticationChallengeSender, @unchecked Sendable {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}
