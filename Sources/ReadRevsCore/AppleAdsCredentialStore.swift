import Foundation
import Security

public protocol AppleAdsCredentialStoring: Sendable {
    func load() throws -> AppleAdsCredentials?
    func save(_ credentials: AppleAdsCredentials) throws
    func delete() throws
}

public struct KeychainAppleAdsCredentialStore: AppleAdsCredentialStoring {
    public static let defaultService = "com.asoresearch.apple-ads-platform-v1"

    private let service: String
    private let account: String

    public init(
        service: String = KeychainAppleAdsCredentialStore.defaultService,
        account: String = "credentials"
    ) {
        self.service = service
        self.account = account
    }

    public func load() throws -> AppleAdsCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw AppleAdsCredentialStoreError.keychain(status)
        }
        guard let data = result as? Data else {
            throw AppleAdsCredentialStoreError.invalidStoredValue
        }
        do {
            return try JSONDecoder().decode(AppleAdsCredentials.self, from: data)
        } catch {
            throw AppleAdsCredentialStoreError.invalidStoredValue
        }
    }

    public func save(_ credentials: AppleAdsCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw AppleAdsCredentialStoreError.keychain(updateStatus)
        }

        var insertion = baseQuery
        insertion[kSecValueData as String] = data
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let insertionStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard insertionStatus == errSecSuccess else {
            throw AppleAdsCredentialStoreError.keychain(insertionStatus)
        }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppleAdsCredentialStoreError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

public enum AppleAdsCredentialStoreError: LocalizedError, Equatable, Sendable {
    case keychain(OSStatus)
    case invalidStoredValue

    public var errorDescription: String? {
        switch self {
        case let .keychain(status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            return "Apple Ads credentials could not be accessed in Keychain: \(detail)"
        case .invalidStoredValue:
            return "The Apple Ads credentials stored in Keychain are invalid."
        }
    }
}
