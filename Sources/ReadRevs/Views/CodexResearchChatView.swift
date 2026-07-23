import SwiftUI

struct CodexResearchChatView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: CodexResearchChatModel

    init(
        bundle: CodexResearchBundle,
        appName: String,
        reviewCount: Int,
        storefrontCount: Int,
        codexModel: CodexModelConfiguration,
        reasoningEffort: CodexReasoningEffort
    ) {
        _model = State(
            initialValue: CodexResearchChatModel(
                bundle: bundle,
                appName: appName,
                reviewCount: reviewCount,
                storefrontCount: storefrontCount,
                codexModel: codexModel,
                reasoningEffort: reasoningEffort
            )
        )
    }

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            header
            Divider()
            conversation
            Divider()
            composer(model: $model)
        }
        .frame(width: 860, height: 700)
        .background(.regularMaterial)
        .task {
            model.startIfNeeded()
        }
        .onDisappear {
            model.cancel()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text("Review Research")
                    .font(.title3.weight(.semibold))
                Text("\(model.appName) · \(model.reviewCount.formatted()) reviews · \(model.storefrontCount) storefronts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label(
                "Codex CLI · \(model.codexModel.displayName) · \(model.reasoningEffort.title)",
                systemImage: "terminal.fill"
            )
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary, in: Capsule())

            Button {
                model.cancel()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close")
            .help("Close research")
        }
        .padding(20)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    researchContext

                    ForEach(model.messages) { message in
                        CodexChatBubble(message: message)
                            .id(message.id)
                    }

                    if model.isRunning {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text(model.activityText)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        .id("activity")
                    }

                    if let errorMessage = model.errorMessage {
                        errorCard(message: errorMessage)
                            .id("error")
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: model.messages.count) {
                scrollToBottom(proxy)
            }
            .onChange(of: model.isRunning) {
                scrollToBottom(proxy)
            }
            .onChange(of: model.errorMessage) {
                scrollToBottom(proxy)
            }
        }
        .background(Color.secondary.opacity(0.035))
    }

    private var researchContext: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.secondary)
            Text("Codex reads an isolated, read-only export. Review text is treated as untrusted data and cannot grant tools or permissions.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func errorCard(message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 6) {
                Text("Codex could not continue")
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            Button("Try Again") {
                model.retry()
            }
            .disabled(!model.canRetry)
        }
        .padding(14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.2))
        }
    }

    private func composer(model: Bindable<CodexResearchChatModel>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    "Ask a follow-up about the reviews…",
                    text: model.draft,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(1 ... 4)
                .disabled(self.model.isRunning || self.model.errorMessage != nil || self.model.messages.isEmpty)
                .onSubmit {
                    self.model.sendFollowUp()
                }

                if self.model.isRunning {
                    Button("Stop", role: .cancel) {
                        self.model.cancel()
                    }
                } else {
                    Button {
                        self.model.sendFollowUp()
                    } label: {
                        Label("Send", systemImage: "arrow.up.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .fixedSize()
                    .disabled(!self.model.canSendFollowUp)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }

            Text("Uses the Codex CLI account already signed in on this Mac. Press ⌘↩ to send.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if model.errorMessage != nil {
                proxy.scrollTo("error", anchor: .bottom)
            } else if model.isRunning {
                proxy.scrollTo("activity", anchor: .bottom)
            } else if let last = model.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

private struct CodexChatBubble: View {
    let message: CodexChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 90)
            } else {
                Image(systemName: "sparkles")
                    .foregroundStyle(.tint)
                    .frame(width: 24, height: 24)
            }

            messageContent
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 14))
                .frame(
                    maxWidth: message.role == .user ? 560 : .infinity,
                    alignment: message.role == .user ? .trailing : .leading
                )

            if message.role == .assistant {
                Spacer(minLength: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    @ViewBuilder
    private var messageContent: some View {
        if message.role == .assistant {
            CodexMarkdownView(markdown: message.text)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        } else {
            Text(message.text)
                .font(.body)
                .foregroundStyle(.white)
                .textSelection(.enabled)
        }
    }

    private var bubbleBackground: Color {
        message.role == .user ? Color.accentColor : Color.primary.opacity(0.055)
    }
}

private struct CodexMarkdownView: View {
    let markdown: String

    private var lines: [String] {
        markdown.components(separatedBy: .newlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                lineView(line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            Spacer()
                .frame(height: 3)
        } else if let heading = heading(in: trimmed) {
            Text(inlineMarkdown(heading.text))
                .font(heading.font)
                .fontWeight(.semibold)
                .padding(.top, heading.level == 1 ? 6 : 3)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .foregroundStyle(.secondary)
                Text(inlineMarkdown(String(trimmed.dropFirst(2))))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let numbered = numberedListItem(in: trimmed) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(numbered.marker)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(inlineMarkdown(numbered.text))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if trimmed.contains("|") {
            Text(trimmed)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(inlineMarkdown(trimmed))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func heading(in line: String) -> (text: String, level: Int, font: Font)? {
        let prefixCount = line.prefix { $0 == "#" }.count
        guard (1 ... 3).contains(prefixCount) else { return nil }
        let remainder = line.dropFirst(prefixCount)
        guard remainder.first == " " else { return nil }

        let font: Font = switch prefixCount {
        case 1: .title3
        case 2: .headline
        default: .subheadline
        }
        return (String(remainder.dropFirst()), prefixCount, font)
    }

    private func numberedListItem(in line: String) -> (marker: String, text: String)? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let number = line[..<dot]
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        let afterDot = line.index(after: dot)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        return ("\(number).", String(line[line.index(after: afterDot)...]))
    }

    private func inlineMarkdown(_ value: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: value, options: options)) ?? AttributedString(value)
    }
}
