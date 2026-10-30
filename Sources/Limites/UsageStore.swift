import Foundation
import Observation

struct ProviderState: Equatable {
    var snapshot: ProviderSnapshot?
    var error: String?
}

@MainActor
@Observable
final class UsageStore {
    var claude: [String: ProviderState] = [:]
    var codex = ProviderState()
    var isRefreshing = false
    var lastUpdated: Date?

    @ObservationIgnored private var timer: Timer?
    private static let interval: TimeInterval = 5 * 60

    init() {
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    /// The highest usage across every window: the limit that will stop you first.
    var highestUsage: Double? {
        let all = (claude.values.map(\.snapshot) + [codex.snapshot]).compactMap { $0 }.flatMap(\.windows).map(\.usedPercent)
        return all.max()
    }

    func refreshIfStale() {
        guard let lastUpdated else { return refresh() }
        if Date.now.timeIntervalSince(lastUpdated) > 60 { refresh() }
    }

    func refresh() {
        guard !Demo.isEnabled else {
            for account in ClaudeAccount.all { claude[account.id] = ProviderState(snapshot: Demo.claude) }
            codex = ProviderState(snapshot: Demo.codex)
            lastUpdated = .now
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            async let codexResult = Self.capture { try await CodexProvider.fetch() }
            let claudeNow = await withTaskGroup(of: (String, Result<ProviderSnapshot, Error>).self) { group in
                for account in ClaudeAccount.all {
                    group.addTask { (account.id, await Self.capture { try await ClaudeProvider.fetch(account: account) }) }
                }
                var results: [String: Result<ProviderSnapshot, Error>] = [:]
                for await (id, result) in group { results[id] = result }
                return results
            }
            for (id, result) in claudeNow {
                claude[id] = Self.merge(claude[id] ?? ProviderState(), result)
            }
            codex = Self.merge(codex, await codexResult)
            lastUpdated = .now
            isRefreshing = false
        }
    }

    private nonisolated static func capture(_ work: @Sendable () async throws -> ProviderSnapshot) async -> Result<ProviderSnapshot, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }

    /// A transient failure keeps the last good numbers and shows the error next to them.
    private static func merge(_ old: ProviderState, _ result: Result<ProviderSnapshot, Error>) -> ProviderState {
        switch result {
        case .success(let snapshot):
            return ProviderState(snapshot: snapshot, error: nil)
        case .failure(let error):
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if case .notFound = error as? CLIError { return ProviderState(snapshot: nil, error: message) }
            return ProviderState(snapshot: old.snapshot, error: message)
        }
    }
}
