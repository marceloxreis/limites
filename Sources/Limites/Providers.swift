import Foundation

struct UsageWindow: Identifiable, Equatable {
    let id: String
    let title: String
    let usedPercent: Double
    let resetsAt: Date?
}

struct ProviderSnapshot: Equatable {
    var windows: [UsageWindow]
    var plan: String?
    var footnote: String?
}

// MARK: - Claude Code

/// `claude -p /usage` is a local command: it never calls the model and uses no tokens.
/// With no setting sources and no MCP config it runs no hooks and starts no servers.
enum ClaudeProvider {
    static func fetch(account: ClaudeAccount) async throws -> ProviderSnapshot {
        guard let binary = CLI.locate("claude") else { throw CLIError.notFound("Claude Code") }
        // nil removes CLAUDE_CONFIG_DIR, so the default account keeps its own Keychain item.
        let overrides: [String: String?] = ["CLAUDE_CONFIG_DIR": account.configDir]
        let data = try await CLI.run(binary, [
            "-p", "/usage",
            "--output-format", "json",
            "--no-session-persistence",
            "--permission-mode", "plan",
            "--setting-sources", "",
            "--strict-mcp-config",
        ], environment: overrides, timeout: 45)

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CLIError.failed(String(localized: "Unexpected response from Claude Code"))
        }
        let text = object["result"] as? String ?? ""
        let windows = parse(text)
        if windows.isEmpty {
            let lower = text.lowercased()
            if lower.contains("log in") || lower.contains("not logged") || lower.contains("login") {
                throw CLIError.failed(String(localized: "Sign in to Claude Code"))
            }
            throw CLIError.failed(String(localized: "Limits unavailable"))
        }
        return ProviderSnapshot(windows: windows, plan: account.email)
    }

    static func parse(_ text: String, now: Date = .now) -> [UsageWindow] {
        let pattern = #"^\s*(Current [^:]+):\s*(\d+(?:\.\d+)?)%\s*used(?:\s*·\s*resets\s+(.+?))?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines, .caseInsensitive]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let label = ns.substring(with: match.range(at: 1))
            guard let used = Double(ns.substring(with: match.range(at: 2))) else { return nil }
            let reset = match.range(at: 3).location == NSNotFound ? nil : parseReset(ns.substring(with: match.range(at: 3)), now: now)
            return UsageWindow(id: "claude." + label.lowercased(), title: title(for: label), usedPercent: used, resetsAt: reset)
        }
    }

    static func title(for label: String) -> String {
        let lower = label.lowercased()
        if lower.hasPrefix("current session") { return String(localized: "5-hour window") }
        if lower.hasPrefix("current week") {
            guard let open = label.firstIndex(of: "("), let close = label.lastIndex(of: ")") else { return String(localized: "Week") }
            let inner = label[label.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            if inner.lowercased() == "all models" { return String(localized: "Week") }
            if inner.lowercased().hasSuffix(" only") {
                let model = String(inner.dropLast(5))
                return String(localized: "Week · \(model) only")
            }
            return String(localized: "Week · \(inner)")
        }
        return label.replacingOccurrences(of: "Current ", with: "")
    }

    /// "Sep 14 at 7:29pm (America/New_York)", "Sep 15 at 1am", "7:29pm".
    static func parseReset(_ raw: String, now: Date) -> Date? {
        var text = raw
        var zone = TimeZone.current
        if let range = text.range(of: #"\(([^)]+)\)"#, options: .regularExpression) {
            let identifier = String(text[range].dropFirst().dropLast())
            if let parsed = TimeZone(identifier: identifier) { zone = parsed }
            text.removeSubrange(range)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var parts = calendar.dateComponents([.year, .month, .day], from: now)
        parts.hour = 0
        parts.minute = 0

        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        var hasDate = false
        var hasTime = false

        if let match = firstMatch(#"\b([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2})(?:,?\s+(\d{4}))?"#, in: text),
           let month = months.firstIndex(of: match[1].lowercased()) {
            parts.month = month + 1
            parts.day = Int(match[2])
            if let year = Int(match[3]) { parts.year = year }
            hasDate = true
        }
        if let match = firstMatch(#"(\d{1,2})(?::(\d{2}))?\s*(am|pm)"#, in: text), let hour = Int(match[1]) {
            parts.hour = hour % 12 + (match[3].lowercased() == "pm" ? 12 : 0)
            parts.minute = Int(match[2]) ?? 0
            hasTime = true
        }
        guard hasDate || hasTime, var date = calendar.date(from: parts) else { return nil }
        if !hasDate, date <= now {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        } else if hasDate, date < now.addingTimeInterval(-86_400) {
            date = calendar.date(byAdding: .year, value: 1, to: date) ?? date
        }
        return date
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            return range.location == NSNotFound ? "" : ns.substring(with: range)
        }
    }
}

// MARK: - Codex

/// The same protocol the Codex app uses: JSON-RPC over stdio with `codex app-server`.
enum CodexProvider {
    static func fetch() async throws -> ProviderSnapshot {
        guard let binary = CLI.locate("codex") else { throw CLIError.notFound("Codex") }
        let messages = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"limites","title":"Limites","version":"1.0.0"}}}"#,
            #"{"jsonrpc":"2.0","method":"initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":{}}"#,
        ].joined(separator: "\n") + "\n"

        let data = try await CLI.run(binary, ["app-server"], input: Data(messages.utf8), keepStdinOpen: true, timeout: 30) { buffer in
            response(in: buffer) != nil
        }
        guard let response = response(in: data) else { throw CLIError.failed(String(localized: "No response from Codex")) }
        if let error = response["error"] as? [String: Any] {
            let message = error["message"] as? String ?? ""
            if message.lowercased().contains("auth") || message.lowercased().contains("login") {
                throw CLIError.failed(String(localized: "Sign in to Codex"))
            }
            throw CLIError.failed(message.isEmpty ? String(localized: "Codex error") : message)
        }
        guard let result = response["result"] as? [String: Any] else { throw CLIError.failed(String(localized: "Unexpected response from Codex")) }
        let snapshot = snapshot(from: result)
        if snapshot.windows.isEmpty { throw CLIError.failed(String(localized: "Limits unavailable")) }
        return snapshot
    }

    static func response(in data: Data) -> [String: Any]? {
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            if (object["id"] as? NSNumber)?.intValue == 2 { return object }
        }
        return nil
    }

    static func snapshot(from result: [String: Any]) -> ProviderSnapshot {
        var limits = result["rateLimitsByLimitId"] as? [String: [String: Any]] ?? [:]
        if limits.isEmpty, let single = result["rateLimits"] as? [String: Any] { limits["codex"] = single }
        let keys = limits.keys.sorted { a, b in a == "codex" || (b != "codex" && a < b) }

        var windows: [UsageWindow] = []
        var plan: String?
        for key in keys {
            guard let limit = limits[key] else { continue }
            if plan == nil, let type = limit["planType"] as? String, !type.isEmpty { plan = type.capitalized }
            let name = limit["limitName"] as? String
            for slot in ["primary", "secondary"] {
                guard let window = limit[slot] as? [String: Any],
                      let used = (window["usedPercent"] as? NSNumber)?.doubleValue else { continue }
                let minutes = (window["windowDurationMins"] as? NSNumber)?.intValue
                let resets = (window["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
                var title = windowTitle(
                    minutes: minutes,
                    fallback: slot == "primary" ? String(localized: "Short window") : String(localized: "Long window")
                )
                if key != "codex", let name, !name.isEmpty { title = "\(name) · \(title)" }
                windows.append(UsageWindow(id: "codex.\(key).\(slot)", title: title, usedPercent: used, resetsAt: resets))
            }
        }

        var footnote: String?
        if let credits = result["rateLimitResetCredits"] as? [String: Any],
           let count = (credits["availableCount"] as? NSNumber)?.intValue, count > 0 {
            footnote = count == 1 ? String(localized: "1 full reset available") : String(localized: "\(count) full resets available")
        }
        return ProviderSnapshot(windows: windows, plan: plan, footnote: footnote)
    }

    static func windowTitle(minutes: Int?, fallback: String) -> String {
        guard let minutes, minutes > 0 else { return fallback }
        if minutes == 10_080 { return String(localized: "Week") }
        if minutes == 1_440 { return String(localized: "Day") }
        if minutes % 1_440 == 0 { return String(localized: "\(minutes / 1_440) days") }
        if minutes == 60 { return String(localized: "1-hour window") }
        if minutes % 60 == 0 { return String(localized: "\(minutes / 60)-hour window") }
        return String(localized: "\(minutes)-minute window")
    }
}
