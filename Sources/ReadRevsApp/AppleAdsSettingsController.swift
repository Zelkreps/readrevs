import ReadRevsCore
import Foundation
import SwiftUI

@MainActor
final class AppleAdsSettingsController: ObservableObject {
    @Published var clientID = ""
    @Published var teamID = ""
    @Published var keyID = ""
    @Published private(set) var publicKeyPEM = ""
    @Published private(set) var accounts: [AppleAdsAccountAccess] = []
    @Published private(set) var selectedAccountID: Int64?
    @Published private(set) var researchAppAdamID: Int64?
    @Published private(set) var researchAppName: String?
    @Published private(set) var researchApps: [AppleAdsPromotableApp] = []
    @Published private(set) var isConnecting = false
    @Published private(set) var isSelectingResearchApp = false
    @Published private(set) var isSearchingResearchApps = false
    @Published private(set) var isConnected = false
    @Published private(set) var statusText: String?
    @Published private(set) var statusIsError = false

    private let credentialStore: any AppleAdsCredentialStoring
    private let client: any AppleAdsPlatformProviding
    private let keyPairGenerator: @Sendable () -> AppleAdsKeyPair
    private var privateKeyRawRepresentation: Data?

    init(
        credentialStore: any AppleAdsCredentialStoring = KeychainAppleAdsCredentialStore(),
        client: any AppleAdsPlatformProviding = AppleAdsPlatformClient.shared,
        keyPairGenerator: @escaping @Sendable () -> AppleAdsKeyPair = AppleAdsKeyPair.generate
    ) {
        self.credentialStore = credentialStore
        self.client = client
        self.keyPairGenerator = keyPairGenerator
        load()
    }

    var hasPrivateKey: Bool {
        privateKeyRawRepresentation != nil
    }

    var canConnect: Bool {
        hasPrivateKey
            && !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !teamID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !keyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isConnecting
    }

    var selectedAccount: AppleAdsAccountAccess? {
        guard let selectedAccountID else { return nil }
        return accounts.first { $0.id == selectedAccountID }
    }

    func generateKeyPair() {
        let keyPair = keyPairGenerator()
        let credentials = AppleAdsCredentials(
            clientID: clientID,
            teamID: teamID,
            keyID: keyID,
            privateKeyRawRepresentation: keyPair.privateKeyRawRepresentation
        )
        do {
            try credentialStore.save(credentials)
            privateKeyRawRepresentation = keyPair.privateKeyRawRepresentation
            publicKeyPEM = keyPair.publicKeyPEM
            accounts = []
            selectedAccountID = nil
            researchAppAdamID = nil
            researchAppName = nil
            researchApps = []
            isConnected = false
            setStatus(
                "Key generated on this Mac. Upload the public key in Apple Ads, then enter the three IDs Apple returns.",
                isError: false
            )
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    func connect() async {
        guard let credentials = currentCredentials() else {
            setStatus(
                "Generate a key and enter Client ID, Team ID, and Key ID first.",
                isError: true
            )
            return
        }

        clientID = credentials.clientID
        teamID = credentials.teamID
        keyID = credentials.keyID

        isConnecting = true
        setStatus("Verifying OAuth and loading accessible ad accounts...", isError: false)
        defer { isConnecting = false }

        do {
            try credentialStore.save(credentials)
            let accessibleAccounts = try await client.fetchAccounts(credentials: credentials)
                .filter(\.grantsReadOnlyAPIAccess)
            guard !accessibleAccounts.isEmpty else {
                var disconnectedCredentials = credentials
                disconnectedCredentials.adAccountID = nil
                disconnectedCredentials.adAccountName = nil
                disconnectedCredentials.researchAppAdamID = nil
                disconnectedCredentials.researchAppName = nil
                try credentialStore.save(disconnectedCredentials)
                accounts = []
                selectedAccountID = nil
                researchAppAdamID = nil
                researchAppName = nil
                researchApps = []
                throw AppleAdsSettingsError.noReadOnlyAccounts
            }

            accounts = accessibleAccounts
            if let selected = accessibleAccounts.first(where: { $0.id == credentials.adAccountID }) {
                var connectedCredentials = credentials
                connectedCredentials.adAccountID = selected.id
                connectedCredentials.adAccountName = selected.name
                try credentialStore.save(connectedCredentials)
                selectedAccountID = selected.id
                researchAppAdamID = connectedCredentials.researchAppAdamID
                researchAppName = connectedCredentials.researchAppName
                isConnected = true
                setStatus(
                    "Connected to \(selected.name) with read-only access.",
                    isError: false
                )
            } else {
                var verifiedCredentials = credentials
                verifiedCredentials.adAccountID = nil
                verifiedCredentials.adAccountName = nil
                verifiedCredentials.researchAppAdamID = nil
                verifiedCredentials.researchAppName = nil
                try credentialStore.save(verifiedCredentials)
                selectedAccountID = nil
                researchAppAdamID = nil
                researchAppName = nil
                researchApps = []
                isConnected = false
                setStatus(
                    "OAuth verified. Choose the read-only ad account to use for research.",
                    isError: false
                )
            }
        } catch {
            isConnected = false
            setStatus(error.localizedDescription, isError: true)
        }
    }

    func selectAccount(id: Int64) {
        guard let account = accounts.first(where: {
            $0.id == id && $0.grantsReadOnlyAPIAccess
        }),
              var credentials = currentCredentials()
        else {
            return
        }
        credentials.adAccountID = account.id
        credentials.adAccountName = account.name
        if selectedAccountID != account.id {
            credentials.researchAppAdamID = nil
            credentials.researchAppName = nil
            researchApps = []
        }
        do {
            try credentialStore.save(credentials)
            selectedAccountID = id
            researchAppAdamID = credentials.researchAppAdamID
            researchAppName = credentials.researchAppName
            isConnected = true
            setStatus("Using \(account.name) for read-only research.", isError: false)
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    func loadResearchApps(candidates: [TrackedApp]) async {
        guard let credentials = currentCredentials(), credentials.isConnected else { return }
        var queries = candidates
            .filter { $0.kind == .owned }
            .map(\.name)
        if let researchAppName {
            queries.append(researchAppName)
        }
        await searchResearchApps(
            credentials: credentials,
            queries: queries,
            autoSelectFirst: researchAppAdamID == nil
        )
    }

    func searchResearchApps(query: String) async {
        guard let credentials = currentCredentials(), credentials.isConnected else { return }
        await searchResearchApps(
            credentials: credentials,
            queries: [query],
            autoSelectFirst: researchAppAdamID == nil
        )
    }

    func selectResearchApp(_ app: AppleAdsPromotableApp) async {
        guard let credentials = currentCredentials(), credentials.isConnected else { return }
        guard !isSelectingResearchApp else { return }
        isSelectingResearchApp = true
        defer { isSelectingResearchApp = false }
        do {
            let resolved = try await AppleAdsResearchAppResolver(
                client: client,
                credentialStore: credentialStore
            ).select(
                credentials: credentials,
                app: app,
                target: StoreTarget(language: "en", store: preferredStore(for: app))
            )
            researchAppAdamID = resolved.researchAppAdamID
            researchAppName = resolved.researchAppName
            setStatus("Using \(app.name) as the Apple Ads research app.", isError: false)
        } catch is CancellationError {
            return
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    func disconnect() {
        do {
            try credentialStore.delete()
            clientID = ""
            teamID = ""
            keyID = ""
            privateKeyRawRepresentation = nil
            publicKeyPEM = ""
            accounts = []
            selectedAccountID = nil
            researchAppAdamID = nil
            researchAppName = nil
            researchApps = []
            isConnected = false
            setStatus("Apple Ads credentials were removed from this Mac.", isError: false)
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    private func load() {
        do {
            guard let credentials = try credentialStore.load() else { return }
            clientID = credentials.clientID
            teamID = credentials.teamID
            keyID = credentials.keyID
            privateKeyRawRepresentation = credentials.privateKeyRawRepresentation
            publicKeyPEM = try AppleAdsKeyPair.publicKeyPEM(
                privateKeyRawRepresentation: credentials.privateKeyRawRepresentation
            )
            selectedAccountID = credentials.adAccountID
            researchAppAdamID = credentials.researchAppAdamID
            researchAppName = credentials.researchAppName
            isConnected = credentials.isConnected
            if let accountID = credentials.adAccountID {
                accounts = [
                    AppleAdsAccountAccess(
                        id: accountID,
                        name: credentials.adAccountName ?? "Apple Ads Account \(accountID)",
                        organizationID: 0,
                        roles: []
                    ),
                ]
            }
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    private func currentCredentials() -> AppleAdsCredentials? {
        guard let privateKeyRawRepresentation else { return nil }
        return AppleAdsCredentials(
            clientID: clientID,
            teamID: teamID,
            keyID: keyID,
            privateKeyRawRepresentation: privateKeyRawRepresentation,
            adAccountID: selectedAccountID,
            adAccountName: selectedAccount?.name,
            researchAppAdamID: researchAppAdamID,
            researchAppName: researchAppName
        )
    }

    private func searchResearchApps(
        credentials: AppleAdsCredentials,
        queries: [String],
        autoSelectFirst: Bool
    ) async {
        guard !isSearchingResearchApps else { return }
        isSearchingResearchApps = true
        defer { isSearchingResearchApps = false }

        do {
            let resolver = AppleAdsResearchAppResolver(
                client: client,
                credentialStore: credentialStore
            )
            let discovered = try await resolver.eligibleApps(
                credentials: credentials,
                queries: queries,
                target: StoreTarget(language: "en", store: "us")
            )
            var merged = Dictionary(uniqueKeysWithValues: researchApps.map { ($0.adamID, $0) })
            for app in discovered {
                merged[app.adamID] = app
            }
            researchApps = merged.values.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            if autoSelectFirst, let first = researchApps.first {
                await selectResearchApp(first)
                return
            }
            setStatus(
                discovered.isEmpty
                    ? "No eligible owned apps matched that Apple Ads search."
                    : "Loaded \(discovered.count) eligible app\(discovered.count == 1 ? "" : "s") from Apple Ads.",
                isError: false
            )
        } catch is CancellationError {
            return
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    private func preferredStore(for app: AppleAdsPromotableApp) -> String {
        if app.countryOrRegionCodes.contains(where: { $0.caseInsensitiveCompare("US") == .orderedSame }) {
            return "us"
        }
        return app.countryOrRegionCodes.first?.lowercased() ?? "us"
    }

    private func setStatus(_ text: String, isError: Bool) {
        statusText = text
        statusIsError = isError
    }
}

private enum AppleAdsSettingsError: LocalizedError {
    case noReadOnlyAccounts

    var errorDescription: String? {
        "No read-only Apple Ads accounts are available. Assign API Account Read Only or API Read Only access and try again."
    }
}
