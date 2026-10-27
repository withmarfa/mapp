import Foundation

/// Why a picture at a web address was not loaded. The text is what the person reads on the picture's card.
nonisolated enum PictureFailure: Error, Hashable, Sendable {
    case notSecure
    case hasCredentials
    case privateNetwork
    case unresolved
    case tooManyRedirects
    case badStatus(Int)
    case notAPicture
    case tooLarge
    case tooSlow
    case tooSmall
    case tooManyPixels
    case failed

    /// The largest picture, in bytes, as the fetch enforces it.
    static let largest = 25 << 20

    /// Whether trying again could end differently, as opposed to a picture or address that will always be refused.
    var isTransient: Bool {
        switch self {
        case .unresolved, .badStatus, .tooSlow, .failed: true
        case .notSecure, .hasCredentials, .privateNetwork, .tooManyRedirects, .notAPicture, .tooLarge, .tooSmall,
            .tooManyPixels: false
        }
    }

    var message: String {
        switch self {
        case .notSecure: String(localized: "Only pictures at secure (https) addresses can be loaded.")
        case .hasCredentials: String(localized: "This address includes a sign-in, so it isn’t loaded.")
        case .privateNetwork: String(localized: "This address is on a private network, so it isn’t loaded.")
        case .unresolved: String(localized: "This website can’t be found.")
        case .tooManyRedirects: String(localized: "The website sent the request on too many times.")
        case .badStatus: String(localized: "The website didn’t return a picture.")
        case .notAPicture: String(localized: "The website didn’t return a picture of a kind that can be shown.")
        case .tooLarge:
            String(localized: "The picture is larger than \(Int64(Self.largest).formatted(.byteCount(style: .memory))).")
        case .tooSlow: String(localized: "The picture took too long to load.")
        case .tooSmall: String(localized: "The picture is a single pixel wide or high, so it isn’t shown.")
        case .tooManyPixels: String(localized: "The picture is too large to show.")
        case .failed: String(localized: "The picture couldn’t be loaded.")
        }
    }
}
