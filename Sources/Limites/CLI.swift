import Foundation

enum CLIError: LocalizedError {
    case notFound(String)
    case timedOut
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let name): return String(localized: "\(name) is not installed")
        case .timedOut: return String(localized: "No response")
        case .failed(let message): return message
        }
    }
}

/// Finds and runs the CLIs. An app opened from Finder inherits a minimal PATH,
/// so the usual install directories are searched too.
enum CLI {
    static let searchDirs: [String] = {
        let home = NSHomeDirectory()
        return [
            "\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin",
            "\(home)/.npm-global/bin", "\(home)/.bun/bin", "\(home)/.volta/bin",
            "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        ]
    }()

    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        var dirs = searchDirs
        for dir in (env["PATH"] ?? "").split(separator: ":").map(String.init) where !dirs.contains(dir) {
            dirs.append(dir)
        }
        env["PATH"] = dirs.joined(separator: ":")
        env["NO_COLOR"] = "1"
        return env
    }

    private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    static func locate(_ name: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[name], FileManager.default.isExecutableFile(atPath: hit) { return hit }
        for dir in searchDirs {
            let path = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) {
                cache[name] = path
                return path
            }
        }
        // Last resort: the user's login shell knows where it is.
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-lc", "command -v \(name)"]
        let pipe = Pipe()
        shell.standardOutput = pipe
        shell.standardError = FileHandle.nullDevice
        guard (try? shell.run()) != nil else { return nil }
        shell.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty, FileManager.default.isExecutableFile(atPath: out) else { return nil }
        cache[name] = out
        return out
    }

    /// Runs a process and returns its stdout. With `until`, the process is stopped
    /// as soon as the buffer satisfies the condition (for servers that never exit).
    static func run(
        _ path: String,
        _ arguments: [String],
        input: Data? = nil,
        keepStdinOpen: Bool = false,
        environment overrides: [String: String?] = [:],
        timeout: TimeInterval,
        until done: (@Sendable (Data) -> Bool)? = nil
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            var env = environment
            for (key, value) in overrides { env[key] = value }
            process.environment = env
            process.currentDirectoryURL = FileManager.default.temporaryDirectory
            let stdout = Pipe()
            let stdin = Pipe()
            process.standardOutput = stdout
            process.standardError = FileHandle.nullDevice
            process.standardInput = stdin

            let once = Once(continuation)

            DispatchQueue.global(qos: .utility).async {
                do {
                    try process.run()
                } catch {
                    once.resume(.failure(CLIError.failed(error.localizedDescription)))
                    return
                }
                if let input { try? stdin.fileHandleForWriting.write(contentsOf: input) }
                if !keepStdinOpen { try? stdin.fileHandleForWriting.close() }

                var buffer = Data()
                let reader = stdout.fileHandleForReading
                while true {
                    let chunk = reader.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    if let done, done(buffer) { break }
                }
                if process.isRunning { process.terminate() }
                try? stdin.fileHandleForWriting.close()
                once.resume(.success(buffer))
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                once.resume(.failure(CLIError.timedOut))
                if process.isRunning { process.terminate() }
            }
        }
    }
}

private final class Once: @unchecked Sendable {
    private var continuation: CheckedContinuation<Data, Error>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<Data, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
