import SwiftUI

struct ReadRevsSettingsView: View {
    @AppStorage(CodexResearchPreferences.modelIDStorageKey)
    private var selectedModelID = CodexResearchPreferences.defaultModelID

    @AppStorage(CodexReasoningEffort.storageKey)
    private var selectedReasoningEffort = CodexReasoningEffort.defaultValue.rawValue

    @State private var catalog = CodexModelCatalog.live()

    private var selectedModel: CodexModelDescriptor {
        catalog.model(id: selectedModelID) ?? catalog.defaultModel
    }

    private var reasoningEffort: CodexReasoningEffort {
        let candidate = CodexReasoningEffort.resolve(storedValue: selectedReasoningEffort)
        return selectedModel.supportedReasoningEfforts.contains(candidate)
            ? candidate
            : selectedModel.defaultReasoningEffort
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: { selectedModel.id },
            set: { selectedModelID = $0 }
        )
    }

    private var reasoningSelection: Binding<String> {
        Binding(
            get: { reasoningEffort.rawValue },
            set: { selectedReasoningEffort = $0 }
        )
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Model") {
                    Picker("Model", selection: modelSelection) {
                        ForEach(catalog.models) { model in
                            Text(model.displayName)
                                .tag(model.id)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                LabeledContent("Reasoning") {
                    Picker("Reasoning", selection: reasoningSelection) {
                        ForEach(selectedModel.supportedReasoningEfforts) { effort in
                            Text(effort.title)
                                .tag(effort.rawValue)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                LabeledContent("New conversations use") {
                    Text("\(selectedModel.displayName) · \(reasoningEffort.title)")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                Text("\(selectedModel.modelDescription) \(reasoningEffort.detail)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Label("Codex Research", systemImage: "sparkles")
            } footer: {
                Text("Models and supported reasoning levels come from the Codex catalog installed on this Mac. Both selections are saved and apply to new review-research conversations.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 390)
        .navigationTitle("ReadRevs Settings")
        .onAppear(perform: normalizeSelections)
        .onChange(of: selectedModelID) {
            normalizeSelections()
        }
    }

    private func normalizeSelections() {
        if catalog.model(id: selectedModelID) == nil {
            selectedModelID = catalog.defaultModel.id
        }

        let candidate = CodexReasoningEffort(rawValue: selectedReasoningEffort)
        if candidate.map({ !selectedModel.supportedReasoningEfforts.contains($0) }) != false {
            selectedReasoningEffort = selectedModel.defaultReasoningEffort.rawValue
        }
    }
}
