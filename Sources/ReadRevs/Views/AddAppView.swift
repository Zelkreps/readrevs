import SwiftUI

struct AddAppView: View {
    @Environment(\.dismiss) private var dismiss

    let client: any AppleReviewClientProtocol
    let onAdd: (AppMetadata) -> Void

    @State private var identifier = ""
    @State private var storefront = Storefront.unitedStates
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add App")
                        .font(.title2.weight(.semibold))
                    Text("Read public written reviews without an Apple developer account.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(24)

            Divider()

            Form {
                TextField("App Store ID or URL", text: $identifier, prompt: Text("284910350 or https://apps.apple.com/…/id284910350"))
                    .textContentType(.URL)

                Picker("Primary storefront", selection: $storefront) {
                    ForEach(Storefront.priority) { storefront in
                        Text(storefront.displayName).tag(storefront)
                    }
                }

                LabeledContent("Review coverage") {
                    Text("Latest 50 written reviews from 10 storefronts")
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Text("You can remove the app locally at any time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await addApp() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Add App")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }
            .padding(20)
        }
        .frame(width: 520, height: 390)
    }

    @MainActor
    private func addApp() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let appID = try AppIdentifierParser.parse(identifier)
            let app = try await client.lookup(appID: appID, storefront: storefront)
            onAdd(app)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
