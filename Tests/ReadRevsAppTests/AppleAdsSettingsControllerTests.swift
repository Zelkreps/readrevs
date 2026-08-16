import ReadRevsCore
import CryptoKit
import Foundation
import Testing
@testable import ReadRevsApp

@Suite("Apple Ads account settings")
struct AppleAdsSettingsControllerTests {
    @Test("Generates an API key locally and saves only the credential bundle")
    @MainActor
    func generatesAndStoresKeyPair() throws {
        let privateKey = try P256.Signing.PrivateKey(
            rawRepresentation: Data(repeating: 2, count: 32)
        )
        let keyPair = AppleAdsKeyPair(
            privateKeyRawRepresentation: privateKey.rawRepresentation,
            publicKeyPEM: try AppleAdsKeyPair.publicKeyPEM(
                privateKeyRawRepresentation: privateKey.rawRepresentation
            )
        )
        let store = MemoryAppleAdsCredentialStore()
        let controller = AppleAdsSettingsController(
            credentialStore: store,
            client: StubAppleAdsPlatformClient(),
            keyPairGenerator: { keyPair }
        )

        controller.generateKeyPair()

        #expect(controller.hasPrivateKey)
        #expect(controller.publicKeyPEM == keyPair.publicKeyPEM)
        #expect(try store.load()?.privateKeyRawRepresentation == keyPair.privateKeyRawRepresentation)
        #expect(controller.clientID.isEmpty)
        #expect(controller.selectedAccountID == nil)
    }

    @Test("Connect verifies OAuth, exposes only read-only accounts, and requires an explicit selection")
    @MainActor
    func connectsAndRequiresReadOnlyAccountSelection() async throws {
        let credentials = appleAdsSettingsCredentials()
        let store = MemoryAppleAdsCredentialStore(initial: credentials)
        let api = StubAppleAdsPlatformClient(accounts: [
            AppleAdsAccountAccess(
                id: 42,
                name: "Example Ads",
                organizationID: 7,
                roles: ["API Read Only"]
            ),
            AppleAdsAccountAccess(
                id: 84,
                name: "Secondary",
                organizationID: 7,
                roles: ["API Account Manager"]
            ),
        ])
        let controller = AppleAdsSettingsController(credentialStore: store, client: api)

        await controller.connect()

        #expect(!controller.isConnected)
        #expect(controller.selectedAccountID == nil)
        #expect(controller.accounts.map(\.id) == [42])
        #expect(try store.load()?.adAccountID == nil)
        #expect(await api.fetchedCredentialClientIDs == ["SEARCHADS.client"])

        controller.selectAccount(id: 42)

        #expect(controller.isConnected)
        #expect(controller.selectedAccountID == 42)
        #expect(try store.load()?.adAccountID == 42)
    }

    @Test("Connect normalizes repeated credential paste before requesting OAuth")
    @MainActor
    func normalizesRepeatedCredentialPaste() async {
        let credentials = appleAdsSettingsCredentials()
        let store = MemoryAppleAdsCredentialStore(initial: credentials)
        let api = StubAppleAdsPlatformClient(accounts: [
            AppleAdsAccountAccess(
                id: 42,
                name: "Example Ads",
                organizationID: 7,
                roles: ["API Read Only"]
            ),
        ])
        let controller = AppleAdsSettingsController(credentialStore: store, client: api)
        controller.keyID = "key-id\n\nkey-id\n\nkey-id"

        await controller.connect()

        #expect(controller.keyID == "key-id")
        #expect(await api.fetchedCredentialKeyIDs == ["key-id"])
    }

    @Test("Changing the ad account updates Keychain without another OAuth exchange")
    @MainActor
    func changesSelectedAccount() async throws {
        var credentials = appleAdsSettingsCredentials()
        credentials.adAccountID = 42
        credentials.adAccountName = "Example Ads"
        credentials.researchAppAdamID = 123
        credentials.researchAppName = "Old Research App"
        let store = MemoryAppleAdsCredentialStore(initial: credentials)
        let api = StubAppleAdsPlatformClient(accounts: [
            AppleAdsAccountAccess(
                id: 42,
                name: "Example Ads",
                organizationID: 7,
                roles: ["API Account Read Only"]
            ),
            AppleAdsAccountAccess(
                id: 84,
                name: "Secondary",
                organizationID: 7,
                roles: ["API Read Only"]
            ),
        ])
        let controller = AppleAdsSettingsController(credentialStore: store, client: api)
        await controller.connect()

        controller.selectAccount(id: 84)

        #expect(controller.selectedAccountID == 84)
        #expect(try store.load()?.adAccountName == "Secondary")
        #expect(controller.researchAppAdamID == nil)
        #expect(try store.load()?.researchAppAdamID == nil)
        #expect(await api.fetchedCredentialClientIDs.count == 1)
    }

    @Test("Selecting a research app verifies and persists it")
    @MainActor
    func selectsResearchApp() async throws {
        var credentials = appleAdsSettingsCredentials()
        credentials.adAccountID = 42
        credentials.adAccountName = "Example Ads"
        let store = MemoryAppleAdsCredentialStore(initial: credentials)
        let controller = AppleAdsSettingsController(
            credentialStore: store,
            client: StubAppleAdsPlatformClient()
        )
        let app = AppleAdsPromotableApp(
            adamID: 555_000_111,
            name: "Example Flashcards",
            developerName: "Developer",
            countryOrRegionCodes: ["US"]
        )

        await controller.selectResearchApp(app)

        #expect(controller.researchAppAdamID == app.adamID)
        #expect(controller.researchAppName == app.name)
        #expect(try store.load()?.researchAppAdamID == app.adamID)
        #expect(controller.statusText?.contains(app.name) == true)
    }

    @Test("Research app choices contain only apps returned by Apple Ads")
    @MainActor
    func loadsResearchAppsFromAppleAdsInsteadOfTheLocalLibrary() async {
        var credentials = appleAdsSettingsCredentials()
        credentials.adAccountID = 42
        credentials.adAccountName = "Example Ads"
        let store = MemoryAppleAdsCredentialStore(initial: credentials)
        let exampleApp = AppleAdsPromotableApp(
            adamID: 555_000_111,
            name: "Example Flashcards",
            developerName: "Developer",
            countryOrRegionCodes: ["US", "CZ"]
        )
        let api = StubAppleAdsPlatformClient(ownedApps: [exampleApp])
        let controller = AppleAdsSettingsController(credentialStore: store, client: api)
        let localApps = [
            settingsTestApp(id: 555_000_222, name: "Other Public App"),
            settingsTestApp(id: exampleApp.adamID, name: exampleApp.name),
            settingsTestApp(id: 555_000_333, name: "Example Strategy Game"),
        ]

        await controller.loadResearchApps(candidates: localApps)

        #expect(controller.researchApps == [exampleApp])
        #expect(controller.researchAppAdamID == exampleApp.adamID)
        #expect(await api.searchedOwnedAppQueries.count == 3)
    }

    @Test("Write-capable Apple Ads roles are rejected")
    @MainActor
    func rejectsWriteCapableRoles() async throws {
        var credentials = appleAdsSettingsCredentials()
        credentials.adAccountID = 42
        credentials.adAccountName = "Previously Read Only"
        let store = MemoryAppleAdsCredentialStore(initial: credentials)
        let api = StubAppleAdsPlatformClient(accounts: [
            AppleAdsAccountAccess(
                id: 42,
                name: "Writable Account",
                organizationID: 7,
                roles: ["API Account Manager"]
            ),
        ])
        let controller = AppleAdsSettingsController(credentialStore: store, client: api)

        await controller.connect()

        #expect(!controller.isConnected)
        #expect(controller.accounts.isEmpty)
        #expect(controller.selectedAccountID == nil)
        #expect(controller.statusIsError)
        #expect(controller.statusText?.contains("read-only") == true)
        #expect(try store.load()?.adAccountID == nil)
    }

    @Test("Disconnect removes the local credential bundle")
    @MainActor
    func disconnectsLocally() throws {
        let store = MemoryAppleAdsCredentialStore(initial: appleAdsSettingsCredentials())
        let controller = AppleAdsSettingsController(
            credentialStore: store,
            client: StubAppleAdsPlatformClient()
        )

        controller.disconnect()

        #expect(!controller.hasPrivateKey)
        #expect(!controller.isConnected)
        #expect(try store.load() == nil)
    }
}

private func appleAdsSettingsCredentials() -> AppleAdsCredentials {
    let privateKey = try! P256.Signing.PrivateKey(rawRepresentation: Data(repeating: 3, count: 32))
    return AppleAdsCredentials(
        clientID: "SEARCHADS.client",
        teamID: "SEARCHADS.team",
        keyID: "key-id",
        privateKeyRawRepresentation: privateKey.rawRepresentation
    )
}

private func settingsTestApp(id: Int64, name: String) -> TrackedApp {
    TrackedApp(
        adamID: id,
        name: name,
        developerName: "Developer",
        bundleID: "com.example.\(id)",
        primaryStore: "us",
        kind: .owned
    )
}

private final class MemoryAppleAdsCredentialStore: AppleAdsCredentialStoring, @unchecked Sendable {
    private var credentials: AppleAdsCredentials?

    init(initial: AppleAdsCredentials? = nil) {
        credentials = initial
    }

    func load() throws -> AppleAdsCredentials? {
        credentials
    }

    func save(_ credentials: AppleAdsCredentials) throws {
        self.credentials = credentials
    }

    func delete() throws {
        credentials = nil
    }
}

private actor StubAppleAdsPlatformClient: AppleAdsPlatformProviding {
    let accounts: [AppleAdsAccountAccess]
    let ownedApps: [AppleAdsPromotableApp]
    private(set) var fetchedCredentialClientIDs: [String] = []
    private(set) var fetchedCredentialKeyIDs: [String] = []
    private(set) var searchedOwnedAppQueries: [String] = []

    init(
        accounts: [AppleAdsAccountAccess] = [],
        ownedApps: [AppleAdsPromotableApp] = []
    ) {
        self.accounts = accounts
        self.ownedApps = ownedApps
    }

    func fetchAccounts(credentials: AppleAdsCredentials) async throws -> [AppleAdsAccountAccess] {
        fetchedCredentialClientIDs.append(credentials.clientID)
        fetchedCredentialKeyIDs.append(credentials.keyID)
        return accounts
    }

    func searchOwnedApps(
        matching query: String,
        credentials: AppleAdsCredentials
    ) async throws -> [AppleAdsPromotableApp] {
        searchedOwnedAppQueries.append(query)
        return ownedApps
    }

    func fetchKeywordSuggestions(
        terms: [String],
        promotedObjectID: Int64,
        target: StoreTarget,
        credentials: AppleAdsCredentials
    ) async throws -> [AppleAdsKeywordSuggestion] {
        []
    }

    func fetchSearchTermPopularity(
        target: StoreTarget,
        genre: String,
        credentials: AppleAdsCredentials
    ) async throws -> [AppleAdsSearchTermPopularity] {
        []
    }
}
