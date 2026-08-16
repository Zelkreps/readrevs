import Foundation

public enum ServiceError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case api(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: "The service URL could not be created."
        case .invalidResponse: "The service returned an invalid response."
        case let .httpStatus(status): "The service returned HTTP \(status)."
        case let .api(message): message
        }
    }
}
