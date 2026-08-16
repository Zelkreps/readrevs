import AppKit
import SwiftUI

struct AppleAdsSettingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @StateObject private var controller = AppleAdsSettingsController()
    @State private var isConfirmingKeyRegeneration = false
    @State private var isConfirmingDisconnect = false
    @State private var didCopyPublicKey = false
    @State private var researchAppQuery = ""

    private let appleAdsURL = URL(string: "https://app-ads.apple.com/cm/app")!
    private let oauthGuideURL = URL(
        string: "https://developer.apple.com/documentation/apple_ads/implementing-oauth-for-the-apple-search-ads-api"
    )!

    var body: some View {
        Form {
            connectionSection
            apiUserSection
            keySection
            credentialsSection
            accountSection
        }
        .formStyle(.grouped)
        .navigationTitle("Apple Ads")
        .confirmationDialog(
            "Generate a new API key?",
            isPresented: $isConfirmingKeyRegeneration
        ) {
            Button("Generate New Key", role: .destructive) {
                controller.generateKeyPair()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current public key will stop matching Apple Ads until you upload the new one.")
        }
        .confirmationDialog(
            "Remove Apple Ads credentials?",
            isPresented: $isConfirmingDisconnect
        ) {
            Button("Remove Local Credentials", role: .destructive) {
                controller.disconnect()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the API private key and identifiers from this Mac. It does not change your Apple Ads account.")
        }
        .task(id: controller.isConnected) {
            guard controller.isConnected else { return }
            await controller.loadResearchApps(candidates: store.library.apps)
        }
    }

    private var connectionSection: some View {
        Section {
            LabeledContent("Status") {
                HStack(spacing: 7) {
                    Image(systemName: controller.isConnected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(controller.isConnected ? .green : .secondary)
                    Text(controller.isConnected ? "Connected" : "Not Connected")
                }
            }

            LabeledContent("Access") {
                Text("Research only")
                    .foregroundStyle(.secondary)
            }

            if let statusText = controller.statusText {
                Label(
                    statusText,
                    systemImage: controller.statusIsError
                        ? "exclamationmark.triangle.fill"
                        : "info.circle"
                )
                .font(.callout)
                .foregroundStyle(controller.statusIsError ? .red : .secondary)
            }
        } header: {
            Label("Apple Ads Platform API v1", systemImage: "lock.shield")
        } footer: {
            Text("The app requests research data only and contains no campaign create, update, or delete calls.")
        }
    }

    private var apiUserSection: some View {
        Section {
            LabeledContent("API role") {
                Text("Read Only")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Link(destination: appleAdsURL) {
                    Label("Open Apple Ads", systemImage: "arrow.up.right.square")
                }

                Spacer()

                Link(destination: oauthGuideURL) {
                    Label("OAuth Guide", systemImage: "book")
                }
            }
        } header: {
            Text("1. API User")
        } footer: {
            Text("Assign API Account Read Only or limited API Read Only access, then open Account Settings > API.")
        }
    }

    private var keySection: some View {
        Section {
            if controller.hasPrivateKey {
                ScrollView {
                    Text(controller.publicKeyPEM)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(height: 116)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.22))
                }

                HStack {
                    Button {
                        copyPublicKey()
                    } label: {
                        Label(
                            didCopyPublicKey ? "Copied" : "Copy Public Key",
                            systemImage: didCopyPublicKey ? "checkmark" : "doc.on.doc"
                        )
                    }

                    Spacer()

                    Button("Generate New Key", systemImage: "arrow.triangle.2.circlepath") {
                        isConfirmingKeyRegeneration = true
                    }
                }
            } else {
                Button("Generate API Key", systemImage: "key") {
                    controller.generateKeyPair()
                }
            }
        } header: {
            Text("2. Public Key")
        } footer: {
            Text("The private half stays in this Mac's Keychain. Paste only the public key into Apple Ads.")
        }
    }

    private var credentialsSection: some View {
        Section {
            TextField("Client ID", text: $controller.clientID)
                .textContentType(.username)
            TextField("Team ID", text: $controller.teamID)
            TextField("Key ID", text: $controller.keyID)

            HStack {
                Spacer()
                Button {
                    Task { await controller.connect() }
                } label: {
                    if controller.isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(
                            controller.accounts.isEmpty ? "Connect" : "Verify Again",
                            systemImage: "link"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!controller.canConnect)
            }
        } header: {
            Text("3. Apple Credentials")
        } footer: {
            Text("Apple displays these IDs after accepting the public key. No Apple ID password is stored or requested.")
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        if controller.hasPrivateKey {
            Section {
                if !controller.accounts.isEmpty {
                    Picker(
                        "Ad Account",
                        selection: Binding(
                            get: { controller.selectedAccountID },
                            set: { accountID in
                                if let accountID {
                                    controller.selectAccount(id: accountID)
                                }
                            }
                        )
                    ) {
                        Text("Choose an account").tag(nil as Int64?)
                        ForEach(controller.accounts) { account in
                            Text(account.name).tag(account.id as Int64?)
                        }
                    }
                }

                if let account = controller.selectedAccount, !account.roles.isEmpty {
                    LabeledContent("Roles") {
                        Text(account.roles.joined(separator: ", "))
                            .foregroundStyle(.secondary)
                    }
                }

                if controller.isConnected {
                    Picker(
                        "Research App",
                        selection: Binding(
                            get: { controller.researchAppAdamID },
                            set: { appID in
                                guard let appID,
                                      let app = controller.researchApps.first(where: {
                                          $0.adamID == appID
                                      })
                                else {
                                    return
                                }
                                Task { await controller.selectResearchApp(app) }
                            }
                        )
                    ) {
                        Text("Choose an app").tag(nil as Int64?)
                        if let selectedID = controller.researchAppAdamID,
                           !controller.researchApps.contains(where: {
                               $0.adamID == selectedID
                           })
                        {
                            Text(controller.researchAppName ?? "App \(selectedID)")
                                .tag(selectedID as Int64?)
                        }
                        ForEach(controller.researchApps) { app in
                            Text(app.name).tag(app.adamID as Int64?)
                        }
                    }
                    .disabled(
                        controller.isSelectingResearchApp
                            || controller.isSearchingResearchApps
                    )

                    LabeledContent("Search Account Apps") {
                        HStack(spacing: 8) {
                            TextField(
                                "",
                                text: $researchAppQuery,
                                prompt: Text("App name (3+ characters)")
                            )
                            .labelsHidden()
                            .frame(minWidth: 220)
                            .onSubmit(searchResearchApps)

                            Button(action: searchResearchApps) {
                                Image(systemName: "magnifyingglass")
                            }
                            .disabled(
                                researchAppQuery.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).count < 3
                                    || controller.isSearchingResearchApps
                            )
                            .help("Search apps owned by the connected Apple Ads organization")
                            .accessibilityLabel("Search Account Apps")
                        }
                    }

                    if controller.isSelectingResearchApp
                        || controller.isSearchingResearchApps
                    {
                        LabeledContent("Verifying") {
                            ProgressView()
                                .controlSize(.small)
                        }
                    } else if controller.researchAppAdamID == nil {
                        Text("An eligible app is required for exact keyword popularity.")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        isConfirmingDisconnect = true
                    } label: {
                        Label("Remove Credentials", systemImage: "trash")
                    }
                }
            } header: {
                Text("4. Research Account")
            } footer: {
                Text("Apps come from the connected Apple Ads organization and are verified for read-only keyword requests. Apple requires at least three characters when searching. You can still analyze any App Store app or keyword.")
            }
        }
    }

    private func searchResearchApps() {
        let query = researchAppQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3 else { return }
        Task {
            await controller.searchResearchApps(query: query)
        }
    }

    private func copyPublicKey() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(controller.publicKeyPEM, forType: .string)
        didCopyPublicKey = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopyPublicKey = false
        }
    }
}
