import Foundation

enum CodexCLIInvocation: Equatable, Sendable {
    case start(workspace: URL)
    case resume(workspace: URL, threadID: String)
}

enum CodexCLICommand {
    static func arguments(
        for invocation: CodexCLIInvocation,
        modelID: String?,
        reasoningEffort: CodexReasoningEffort
    ) -> [String] {
        let workspace: URL
        switch invocation {
        case let .start(url), let .resume(url, _):
            workspace = url
        }

        var arguments = [
            "--sandbox", "read-only",
            "--ask-for-approval", "never",
            "--cd", workspace.path,
        ]

        if let modelID = modelID?.trimmingCharacters(in: .whitespacesAndNewlines), !modelID.isEmpty {
            arguments += ["--model", modelID]
        }

        arguments += ["--config", reasoningEffort.cliConfigurationOverride]

        arguments.append("exec")

        if case .resume = invocation {
            arguments.append("resume")
        }

        arguments += [
            "--json",
            "--ignore-user-config",
            "--ignore-rules",
            "--strict-config",
            "--skip-git-repo-check",
        ]

        if case let .resume(_, threadID) = invocation {
            arguments.append(threadID)
        }
        arguments.append("-")
        return arguments
    }
}

enum CodexCLIStreamEvent: Equatable, Sendable {
    case threadStarted(String)
    case turnStarted
    case activity(String)
    case assistantMessage(String)
    case turnCompleted
    case failure(String)
    case ignored
}

enum CodexCLIEventParser {
    static func parse(_ line: String) -> CodexCLIStreamEvent {
        guard
            let data = line.data(using: .utf8),
            let envelope = try? JSONDecoder().decode(EventEnvelope.self, from: data)
        else {
            return .ignored
        }

        switch envelope.type {
        case "thread.started":
            guard let threadID = envelope.threadID, !threadID.isEmpty else { return .ignored }
            return .threadStarted(threadID)
        case "turn.started":
            return .turnStarted
        case "item.started":
            guard let itemType = envelope.item?.type, itemType != "agent_message" else {
                return .ignored
            }
            return .activity(itemType)
        case "item.completed":
            guard
                envelope.item?.type == "agent_message",
                let text = envelope.item?.text,
                !text.isEmpty
            else {
                return .ignored
            }
            return .assistantMessage(text)
        case "turn.completed":
            return .turnCompleted
        case "turn.failed", "error":
            let message = envelope.error?.message ?? envelope.message ?? "Codex could not complete the request."
            return .failure(message)
        default:
            return .ignored
        }
    }

    private struct EventEnvelope: Decodable {
        let type: String
        let threadID: String?
        let message: String?
        let item: Item?
        let error: Failure?

        enum CodingKeys: String, CodingKey {
            case type
            case threadID = "thread_id"
            case message
            case item
            case error
        }
    }

    private struct Item: Decodable {
        let type: String
        let text: String?
    }

    private struct Failure: Decodable {
        let message: String?
    }
}

struct CodexCLIRun: Sendable {
    let events: AsyncThrowingStream<CodexCLIStreamEvent, Swift.Error>
    private let cancellation: @Sendable () -> Void

    init(
        events: AsyncThrowingStream<CodexCLIStreamEvent, Swift.Error>,
        cancellation: @escaping @Sendable () -> Void
    ) {
        self.events = events
        self.cancellation = cancellation
    }

    func cancel() {
        cancellation()
    }
}

struct CodexCLIClient: Sendable {
    enum ClientError: Swift.Error, LocalizedError, Sendable {
        case executableNotFound
        case notAuthenticated(String)
        case processFailed(String)

        var errorDescription: String? {
            switch self {
            case .executableNotFound:
                "Codex CLI was not found. Install it, or install the ChatGPT desktop app."
            case let .notAuthenticated(message):
                message.isEmpty ? "Codex CLI is not signed in. Run `codex login` in Terminal." : message
            case let .processFailed(message):
                message.isEmpty ? "Codex CLI could not complete the request." : message
            }
        }
    }

    let executableURL: URL

    static func live(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> Self {
        guard let executableURL = CodexCLIExecutableResolver.resolve(
            environment: environment,
            fileManager: fileManager
        ) else {
            throw ClientError.executableNotFound
        }
        return Self(executableURL: executableURL)
    }

    func verifyLogin() async throws {
        let executableURL = executableURL
        let result = try await Task.detached(priority: .userInitiated) {
            try Self.runToCompletion(
                executableURL: executableURL,
                arguments: ["login", "status"]
            )
        }.value

        guard result.status == 0 else {
            throw ClientError.notAuthenticated(result.errorOutput)
        }
    }

    func run(
        prompt: String,
        invocation: CodexCLIInvocation,
        modelID: String?,
        reasoningEffort: CodexReasoningEffort
    ) -> CodexCLIRun {
        let processBox = CodexCLIProcessBox()
        let executableURL = executableURL
        let arguments = CodexCLICommand.arguments(
            for: invocation,
            modelID: modelID,
            reasoningEffort: reasoningEffort
        )

        let events = AsyncThrowingStream<CodexCLIStreamEvent, Swift.Error> { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    let process = Process()
                    let standardInput = Pipe()
                    let standardOutput = Pipe()
                    let standardError = Pipe()

                    process.executableURL = executableURL
                    process.arguments = arguments
                    process.standardInput = standardInput
                    process.standardOutput = standardOutput
                    process.standardError = standardError
                    processBox.attach(process)

                    try process.run()
                    try standardInput.fileHandleForWriting.write(contentsOf: Data(prompt.utf8))
                    try standardInput.fileHandleForWriting.close()

                    var lineBuffer = Data()
                    while !Task.isCancelled {
                        let chunk = standardOutput.fileHandleForReading.readData(ofLength: 4_096)
                        guard !chunk.isEmpty else { break }
                        for line in Self.lines(from: chunk, buffer: &lineBuffer) {
                            continuation.yield(CodexCLIEventParser.parse(line))
                        }
                    }

                    if !lineBuffer.isEmpty, let line = String(data: lineBuffer, encoding: .utf8) {
                        continuation.yield(CodexCLIEventParser.parse(line))
                    }

                    process.waitUntilExit()
                    let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(decoding: errorData, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    if processBox.wasCancelled || Task.isCancelled {
                        continuation.finish()
                    } else if process.terminationStatus == 0 {
                        continuation.finish()
                    } else {
                        continuation.finish(
                            throwing: ClientError.processFailed(errorOutput)
                        )
                    }
                } catch {
                    if processBox.wasCancelled || Task.isCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }

            continuation.onTermination = { @Sendable _ in
                processBox.cancel()
                task.cancel()
            }
        }

        return CodexCLIRun(events: events) {
            processBox.cancel()
        }
    }

    private static func runToCompletion(
        executableURL: URL,
        arguments: [String]
    ) throws -> (status: Int32, output: String, errorOutput: String) {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()

        let output = String(
            decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let errorOutput = String(
            decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return (process.terminationStatus, output, errorOutput)
    }

    private static func lines(from chunk: Data, buffer: inout Data) -> [String] {
        buffer.append(chunk)
        var lines: [String] = []

        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newline]
            buffer.removeSubrange(...newline)
            var line = String(decoding: lineData, as: UTF8.self)
            if line.last == "\r" {
                line.removeLast()
            }
            if !line.isEmpty {
                lines.append(line)
            }
        }
        return lines
    }
}

private enum CodexCLIExecutableResolver {
    static func resolve(
        environment: [String: String],
        fileManager: FileManager
    ) -> URL? {
        var candidates: [URL] = []

        if let path = environment["PATH"] {
            candidates += path
                .split(separator: ":")
                .map { URL(fileURLWithPath: String($0), isDirectory: true).appending(path: "codex") }
        }

        candidates += [
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
        ]

        if let home = environment["HOME"] {
            let homeURL = URL(fileURLWithPath: home, isDirectory: true)
            candidates += [
                homeURL.appending(path: ".local/bin/codex"),
                homeURL.appending(path: ".npm-global/bin/codex"),
                homeURL.appending(path: ".codex/bin/codex"),
            ]
        }

        var visited = Set<String>()
        return candidates.first { candidate in
            visited.insert(candidate.path).inserted && fileManager.isExecutableFile(atPath: candidate.path)
        }
    }
}

private final class CodexCLIProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var wasCancelled: Bool {
        lock.withLock { cancelled }
    }

    func attach(_ process: Process) {
        let shouldTerminate = lock.withLock {
            self.process = process
            return cancelled
        }
        if shouldTerminate, process.isRunning {
            process.terminate()
        }
    }

    func cancel() {
        let process = lock.withLock {
            cancelled = true
            return self.process
        }
        if let process, process.isRunning {
            process.terminate()
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
