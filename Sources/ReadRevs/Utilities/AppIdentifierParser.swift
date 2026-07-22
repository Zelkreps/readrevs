import Foundation

enum AppIdentifierParser {
    enum Error: Swift.Error, Equatable, LocalizedError, Sendable {
        case invalidIdentifier

        var errorDescription: String? {
            "Enter a numeric App Store ID or paste an Apple App Store link."
        }
    }

    static func parse(_ input: String) throws -> Int64 {
        let candidate = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if
            !candidate.isEmpty,
            candidate.allSatisfy(\.isNumber),
            let appID = Int64(candidate),
            appID > 0
        {
            return appID
        }

        guard
            let components = URLComponents(string: candidate),
            let scheme = components.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            let host = components.host?.lowercased(),
            host == "apple.com" || host.hasSuffix(".apple.com")
        else {
            throw Error.invalidIdentifier
        }

        for component in components.path.split(separator: "/").reversed() {
            guard component.hasPrefix("id") else { continue }
            let digits = component.dropFirst(2)
            if
                !digits.isEmpty,
                digits.allSatisfy(\.isNumber),
                let appID = Int64(digits),
                appID > 0
            {
                return appID
            }
        }

        throw Error.invalidIdentifier
    }
}
