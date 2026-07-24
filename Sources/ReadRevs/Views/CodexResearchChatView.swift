import SwiftUI

struct CodexResearchChatView: View {
    @FocusState private var isComposerFocused: Bool
    let model: CodexResearchChatModel
    let sessionManager: CodexResearchSessionManager
    @State private var composerInputHeight: CGFloat = 40
    @State private var isShowingHistory = false
    @State private var selectedHistoryEntry: CodexResearchHistoryEntry?

    init(
        model: CodexResearchChatModel,
        sessionManager: CodexResearchSessionManager
    ) {
        self.model = model
        self.sessionManager = sessionManager
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
            await Task.yield()
            isComposerFocused = false
        }
        .sheet(item: $selectedHistoryEntry) { entry in
            CodexResearchHistoryDetailView(entry: entry)
        }
        .overlay(alignment: .bottomTrailing) {
            if let notice = sessionManager.completionNotice {
                CodexResearchCompletionToast(
                    notice: notice,
                    onOpen: sessionManager.openCompletionNotice,
                    onDismiss: sessionManager.dismissCompletionNotice
                )
                .padding(20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: sessionManager.completionNotice?.id)
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

            Button(action: showHistory) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel("Research history")
            .help("Open previous review analyses")
            .popover(isPresented: $isShowingHistory, arrowEdge: .top) {
                CodexResearchCenterPopover(
                    sessions: sessionManager.researchCenterSessions,
                    entries: sessionManager.historyEntries,
                    errorMessage: sessionManager.historyErrorMessage,
                    onOpenSession: openSession,
                    onOpenHistory: openHistory
                )
            }

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
                sessionManager.dismissPresentation()
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
            .help(model.isRunning ? "Close; analysis continues in the background" : "Close research")
        }
        .padding(20)
    }

    @ViewBuilder
    private var conversation: some View {
        if model.messages.isEmpty, !model.isRunning, model.errorMessage == nil {
            VStack(spacing: 0) {
                researchContext

                Spacer(minLength: 20)
                CodexResearchReadyView()
                Spacer(minLength: 20)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.secondary.opacity(0.035))
        } else {
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

                        if let historyErrorMessage = model.historyErrorMessage {
                            Label(historyErrorMessage, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
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
            HStack(alignment: .center, spacing: 12) {
                TextField(
                    self.model.messages.isEmpty
                        ? "Describe the review analysis…"
                        : "Ask a follow-up about the reviews…",
                    text: model.draft,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .lineLimit(1 ... 6)
                .focused($isComposerFocused)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minHeight: 40)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(
                            isComposerFocused ? Color.accentColor : Color.primary.opacity(0.12),
                            lineWidth: isComposerFocused ? 2 : 1
                        )
                }
                .disabled(self.model.isRunning || self.model.errorMessage != nil)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: CodexComposerInputHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                }
                .onPreferenceChange(CodexComposerInputHeightPreferenceKey.self) { height in
                    composerInputHeight = max(40, height)
                }

                if self.model.isRunning {
                    Button(role: .cancel) {
                        self.model.cancel()
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(CodexComposerActionButtonStyle(height: composerInputHeight))
                    .fixedSize()
                    .accessibilityLabel("Stop")
                    .help("Stop analysis")
                } else {
                    Button {
                        self.model.sendMessage()
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(CodexComposerActionButtonStyle(height: composerInputHeight))
                    .fixedSize()
                    .disabled(!self.model.canSendMessage)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel(self.model.primaryActionTitle)
                    .help(self.model.primaryActionTitle)
                }
            }

            Text(
                self.model.messages.isEmpty
                    ? "Nothing is sent until you choose Analyze. Uses the Codex CLI account signed in on this Mac."
                    : "Uses the Codex CLI account already signed in on this Mac. Press ⌘↩ to send."
            )
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

    private func showHistory() {
        sessionManager.refreshHistory()
        isShowingHistory = true
    }

    private func openSession(_ session: CodexResearchChatModel) {
        isShowingHistory = false
        sessionManager.present(session)
    }

    private func openHistory(_ entry: CodexResearchHistoryEntry) {
        isShowingHistory = false
        selectedHistoryEntry = entry
    }
}

private struct CodexComposerInputHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 40

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct CodexComposerActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let height: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 40, height: max(40, height))
            .background(
                Color.secondary.opacity(configuration.isPressed ? 0.18 : 0.10),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08))
            }
            .opacity(isEnabled ? 1 : 0.45)
    }
}

private struct CodexResearchReadyView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.bubble")
                .font(.system(size: 30, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)

            Text("Ready to analyze")
                .font(.title3.weight(.semibold))

            Text("Review or edit the prefilled request below, then choose Analyze.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct CodexResearchCenterPopover: View {
    @FocusState private var isPopoverFocused: Bool
    let sessions: [CodexResearchChatModel]
    let entries: [CodexResearchHistoryEntry]
    let errorMessage: String?
    let onOpenSession: (CodexResearchChatModel) -> Void
    let onOpenHistory: (CodexResearchHistoryEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Review Research", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                if totalCount > 0 {
                    Text(totalCount.formatted())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .focusable()
            .focusEffectDisabled()
            .focused($isPopoverFocused)

            Divider()

            if sessions.isEmpty, savedEntries.isEmpty, errorMessage == nil {
                CodexResearchHistoryStatusView(
                    title: "No research yet",
                    message: "Running and completed analyses will appear here.",
                    systemImage: "clock"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !sessions.isEmpty {
                            CodexResearchSectionHeader(title: "Current")

                            ForEach(sessions) { session in
                                Button {
                                    onOpenSession(session)
                                } label: {
                                    CodexResearchSessionRow(session: session)
                                }
                                .buttonStyle(.plain)

                                if session.id != sessions.last?.id {
                                    Divider()
                                        .padding(.leading, 56)
                                }
                            }
                        }

                        if !savedEntries.isEmpty {
                            if !sessions.isEmpty {
                                Divider()
                            }
                            CodexResearchSectionHeader(title: "Saved")

                            ForEach(savedEntries) { entry in
                                Button {
                                    onOpenHistory(entry)
                                } label: {
                                    CodexResearchHistoryRow(entry: entry)
                                }
                                .buttonStyle(.plain)

                                if entry.id != savedEntries.last?.id {
                                    Divider()
                                        .padding(.leading, 56)
                                }
                            }
                        }

                        if let errorMessage {
                            if !sessions.isEmpty || !savedEntries.isEmpty {
                                Divider()
                            }
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(14)
                        }
                    }
                }
            }
        }
        .frame(width: 380, height: popoverHeight)
        .task {
            await Task.yield()
            isPopoverFocused = true
        }
    }

    private var savedEntries: [CodexResearchHistoryEntry] {
        let currentIDs = Set(sessions.map(\.id))
        return entries.filter { !currentIDs.contains($0.id) }
    }

    private var totalCount: Int {
        sessions.count + savedEntries.count
    }

    private var popoverHeight: CGFloat {
        if sessions.isEmpty, savedEntries.isEmpty {
            210
        } else {
            min(460, max(240, CGFloat(totalCount) * 82 + 104))
        }
    }

}

private struct CodexResearchSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 5)
    }
}

private struct CodexResearchSessionRow: View {
    let session: CodexResearchChatModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(session.appName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(session.updatedAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)

                Text("\(session.reviewCount.formatted()) reviews · \(session.codexModel.displayName) · \(session.reasoningEffort.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 5)
        }
        .padding(14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this research conversation")
    }

    @ViewBuilder
    private var statusIcon: some View {
        if session.isRunning {
            ProgressView()
                .controlSize(.small)
        } else if session.errorMessage != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
        } else if session.hasCompletedResponse {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
        } else {
            Image(systemName: "doc.text")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        if session.isRunning {
            session.activityText
        } else if session.errorMessage != nil {
            "Needs attention"
        } else if session.hasCompletedResponse {
            "Ready for a follow-up"
        } else {
            "Draft · Not started"
        }
    }

    private var statusColor: Color {
        session.errorMessage == nil ? .secondary : .orange
    }
}

private struct CodexResearchHistoryStatusView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 27, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct CodexResearchHistoryRow: View {
    let entry: CodexResearchHistoryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.appName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(entry.updatedAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("\(entry.reviewCount.formatted()) reviews · \(entry.codexModel.displayName) · \(entry.reasoningEffort.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let summary = entry.messages.last(where: { $0.role == .assistant })?.text {
                    Text(summary.replacingOccurrences(of: "\n", with: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 5)
        }
        .padding(14)
        .contentShape(Rectangle())
    }
}

struct CodexResearchCompletionToast: View {
    let notice: CodexResearchCompletionNotice
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Analysis complete")
                    .font(.subheadline.weight(.semibold))
                Text(notice.appName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button("Open", action: onOpen)
                .buttonStyle(.borderless)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 14)
        .padding(.trailing, 9)
        .padding(.vertical, 11)
        .frame(width: 330)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.12))
        }
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
    }
}

struct CodexResearchHistoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let entry: CodexResearchHistoryEntry

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.appName)
                        .font(.title3.weight(.semibold))
                    Text("Saved \(entry.updatedAt.formatted(date: .abbreviated, time: .shortened)) · \(entry.reviewCount.formatted()) reviews")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(entry.codexModel.displayName) · \(entry.reasoningEffort.title)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: Capsule())

                Button {
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
                .accessibilityLabel("Close saved analysis")
            }
            .padding(20)

            Divider()

            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(entry.messages) { message in
                        CodexChatBubble(message: message)
                    }
                }
                .padding(24)
            }
            .background(Color.secondary.opacity(0.035))
        }
        .frame(width: 820, height: 680)
        .background(.regularMaterial)
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
