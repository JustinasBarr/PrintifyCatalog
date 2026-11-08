import Foundation

/// Why a request failed, in the few kinds a screen treats differently.
public enum APIError: Error, Equatable, Sendable {
    case offline
    case timedOut
    /// The caller went away (the task was cancelled). A screen restores its previous state; it is not a failure.
    case cancelled
    case server(status: Int)
    case decoding(String)
    case transport(String)
    /// The endpoint could not make a URL.
    case invalidRequest

    init(transportError error: any Error) {
        if error is CancellationError {
            self = .cancelled
            return
        }
        guard let urlError = error as? URLError else {
            self = .transport(String(describing: error))
            return
        }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            self = .offline
        case .timedOut:
            self = .timedOut
        case .cancelled:
            self = .cancelled
        default:
            self = .transport(urlError.localizedDescription)
        }
    }

    /// What a person reads: what happened and what to do, never a status code.
    public var message: String {
        switch self {
        case .offline: "You're offline. Check your connection and try again."
        case .timedOut: "The server is taking too long to answer. Try again."
        case .server: "The server had a problem. Try again in a moment."
        case .decoding: "The server sent something this version can't read. Try again later."
        case .cancelled, .transport, .invalidRequest: "Something went wrong. Try again."
        }
    }
}
