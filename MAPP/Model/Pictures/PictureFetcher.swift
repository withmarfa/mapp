import Foundation

/// A picture fetched from a web address, held in a file of its own until the cache takes it.
nonisolated struct FetchedPicture: Sendable {
    let file: URL
    let format: PictureFormat
    let width: Int
    let height: Int
}

/// Fetches one picture from a web address for a note, on the person's behalf and with as little trust in the website
/// as can be had. It is the only code in the app that fetches a picture for a note.
///
/// - Only an `https` address is fetched, only by `GET`, in a session of its own that keeps no cookies, credentials or
///   cache, with no referrer and one fixed `User-Agent`.
/// - The address is checked before the first request and at every redirect (`PictureAddressPolicy`), and at most four
///   redirects are followed.
/// - What arrives is a picture only if its first bytes say so (`PictureFormat`), whatever the server called it.
/// - At most 25 MiB and 30 seconds are taken, counted as the bytes arrive, and a picture one pixel wide or high is
///   refused as the tracking pixel it nearly always is. The 30 seconds start with the first lookup of the name, so the
///   lookups count in them, and a lookup is given at most `Limits.resolve` of them.
/// - Only a check of the server's certificate is answered: a request for a client certificate or a sign-in is
///   rejected, so nothing in the person's keychain is offered to a website.
nonisolated final class PictureFetcher: @unchecked Sendable {
    struct Limits: Sendable {
        var bytes = PictureFailure.largest
        var time = Duration.seconds(30)
        /// The longest one lookup of a name may take, within `time`.
        var resolve = Duration.seconds(10)
        var redirects = 4
    }

    static let userAgent = "MAPP"

    private let limits: Limits
    private let resolver: PictureAddressPolicy.Resolver
    private let configuration: @Sendable () -> URLSessionConfiguration

    /// `configuration` is for tests, which put a stand-in for the network in its `protocolClasses`.
    init(
        limits: Limits = Limits(),
        resolver: @escaping PictureAddressPolicy.Resolver = PictureAddressPolicy.system,
        configuration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral }
    ) {
        self.limits = limits
        self.resolver = resolver
        self.configuration = configuration
    }

    /// Fetches the picture at `address` into a new file in `folder`. The file is the caller's to move or remove.
    @concurrent func fetch(_ address: URL, into folder: URL) async throws(PictureFailure) -> FetchedPicture {
        let deadline = ContinuousClock.now.advanced(by: limits.time)
        try await PictureAddressPolicy.check(address, resolver: resolver, timeout: min(limits.resolve, limits.time))
        let left = ContinuousClock.now.duration(to: deadline)
        guard left > .zero else { throw .tooSlow }
        let configuration = configuration()
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = left.timeInterval
        configuration.timeoutIntervalForResource = left.timeInterval
        configuration.httpAdditionalHeaders = nil

        let file = folder.appending(path: ".incoming-\(UUID().uuidString)", directoryHint: .notDirectory)
        let transfer = PictureTransfer(limits: limits, resolver: resolver, file: file, deadline: deadline)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: transfer, delegateQueue: queue)
        defer { session.invalidateAndCancel() }

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let format = try await transfer.run(Self.request(for: address), in: session)
            guard let size = PictureFormat.pixelSize(of: file) else { throw PictureFailure.notAPicture }
            guard size.width > 1, size.height > 1 else { throw PictureFailure.tooSmall }
            guard size.width * size.height <= PictureFormat.largestPixelCount else { throw PictureFailure.tooManyPixels }
            return FetchedPicture(file: file, format: format, width: size.width, height: size.height)
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error as? PictureFailure ?? .failed
        }
    }

    /// The same request for the first address and for each redirect: nothing the website or the note could add.
    fileprivate static func request(for address: URL) -> URLRequest {
        var request = URLRequest(url: address, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("image/png, image/jpeg, image/gif, image/webp, image/heic, image/avif", forHTTPHeaderField: "Accept")
        return request
    }
}

private nonisolated extension Duration {
    var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

/// One fetch, driven by the session's callbacks, which arrive one at a time on its queue.
nonisolated final class PictureTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let limits: PictureFetcher.Limits
    private let resolver: PictureAddressPolicy.Resolver
    private let file: URL
    private let deadline: ContinuousClock.Instant

    private let lock = NSLock()
    private var failure: PictureFailure?
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<PictureFormat, any Error>?
    private var handle: FileHandle?
    private var received = 0
    private var prefix = Data()
    private var format: PictureFormat?
    private var redirects = 0

    init(limits: PictureFetcher.Limits, resolver: @escaping PictureAddressPolicy.Resolver, file: URL, deadline: ContinuousClock.Instant) {
        self.limits = limits
        self.resolver = resolver
        self.file = file
        self.deadline = deadline
    }

    func run(_ request: URLRequest, in session: URLSession) async throws -> PictureFormat {
        let deadline = Task {
            try await Task.sleep(until: deadline)
            fail(.tooSlow)
        }
        defer { deadline.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                defer { lock.unlock() }
                if let failure {
                    continuation.resume(throwing: failure)
                    return
                }
                guard FileManager.default.createFile(atPath: file.path, contents: nil),
                      let handle = try? FileHandle(forWritingTo: file)
                else {
                    continuation.resume(throwing: PictureFailure.failed)
                    return
                }
                self.handle = handle
                self.continuation = continuation
                let task = session.dataTask(with: request)
                self.task = task
                task.resume()
            }
        } onCancel: {
            fail(.failed)
        }
    }

    /// Ends the transfer for `reason`, unless it already ended for another. The first reason is the one told.
    func fail(_ reason: PictureFailure) {
        lock.lock()
        if failure == nil { failure = reason }
        let task = task
        lock.unlock()
        task?.cancel()
    }

    // MARK: Session callbacks

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        lock.lock()
        redirects += 1
        let tooMany = redirects > limits.redirects
        lock.unlock()
        guard !tooMany, let target = request.url else {
            fail(.tooManyRedirects)
            return completionHandler(nil)
        }
        let resolver = resolver
        let timeout = min(limits.resolve, ContinuousClock.now.duration(to: deadline))
        Task {
            do {
                try await PictureAddressPolicy.check(target, resolver: resolver, timeout: timeout)
                completionHandler(PictureFetcher.request(for: target))
            } catch {
                fail(error as? PictureFailure ?? .failed)
                completionHandler(nil)
            }
        }
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard let response = response as? HTTPURLResponse else {
            fail(.failed)
            return completionHandler(.cancel)
        }
        guard response.statusCode == 200 else {
            fail(.badStatus(response.statusCode))
            return completionHandler(.cancel)
        }
        if response.expectedContentLength > Int64(limits.bytes) {
            fail(.tooLarge)
            return completionHandler(.cancel)
        }
        completionHandler(.allow)
    }

    /// Only the check of the server's certificate is answered, by the system's own rules. A request for a client
    /// certificate or a sign-in is rejected, so the system never looks in the keychain for an identity or a password
    /// to give a website. A rejected sign-in ends as the website's own refusal, a status other than 200.
    static func disposition(for protectionSpace: URLProtectionSpace) -> URLSession.AuthChallengeDisposition {
        protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust ? .performDefaultHandling : .rejectProtectionSpace
    }

    func urlSession(
        _ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(Self.disposition(for: challenge.protectionSpace), nil)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(Self.disposition(for: challenge.protectionSpace), nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let reason = take(data) { fail(reason) }
    }

    /// Writes what arrived, and says why the transfer must end if it must.
    private func take(_ data: Data) -> PictureFailure? {
        lock.lock()
        defer { lock.unlock() }
        guard failure == nil, let handle else { return nil }
        received += data.count
        guard received <= limits.bytes else { return .tooLarge }
        if format == nil {
            prefix.append(data.prefix(PictureFormat.prefixLength - prefix.count))
            if prefix.count >= PictureFormat.prefixLength {
                guard let sniffed = PictureFormat(sniffing: prefix) else { return .notAPicture }
                format = sniffed
            }
        }
        do {
            try handle.write(contentsOf: data)
        } catch {
            return .failed
        }
        return nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        try? handle?.close()
        handle = nil
        var outcome: Result<PictureFormat, PictureFailure>
        if let failure {
            outcome = .failure(failure)
        } else if let error {
            outcome = .failure((error as? URLError)?.code == .timedOut ? .tooSlow : .failed)
        } else if let format = format ?? PictureFormat(sniffing: prefix) {
            outcome = .success(format)
        } else {
            outcome = .failure(.notAPicture)
        }
        lock.unlock()
        continuation?.resume(with: outcome.mapError { $0 as any Error })
    }
}
