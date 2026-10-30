import Foundation

/// The Claude Code accounts shown in the panel. Each one is a config dir
/// (`CLAUDE_CONFIG_DIR`); `nil` means the default `~/.claude`.
struct ClaudeAccount: Identifiable, Equatable {
    let id: String
    let name: String
    let configDir: String?

    /// Found on disk every time it is read, so a new account shows up without a rebuild:
    /// `~/.claude` plus every `~/.claude-*` folder that is signed in.
    /// Names come from the shell aliases that launch each account, else from the folder.
    static var all: [ClaudeAccount] {
        let home = NSHomeDirectory()
        let zshrc = (try? String(contentsOfFile: "\(home)/.zshrc", encoding: .utf8)) ?? ""
        let aliases = aliasNames(zshrc, home: home)

        var accounts: [ClaudeAccount] = []
        let main = ClaudeAccount(id: "default", name: aliases[""] ?? "Claude Code", configDir: nil)
        if main.email != nil { accounts.append(main) }

        let folders = (try? FileManager.default.contentsOfDirectory(atPath: home)) ?? []
        let others = folders
            .filter { $0.hasPrefix(".claude-") }
            .map { "\(home)/\($0)" }
            .map { dir in ClaudeAccount(id: dir, name: aliases[dir] ?? String(dir.split(separator: "/").last!.dropFirst()), configDir: dir) }
            .filter { $0.email != nil }
            .sorted { $0.name < $1.name }
        return accounts + others
    }

    /// Maps each config dir to the alias that launches it; the key "" is the default account
    /// (an alias that runs `claude` with CLAUDE_CONFIG_DIR unset).
    static func aliasNames(_ text: String, home: String) -> [String: String] {
        var names: [String: String] = [:]
        let pattern = #/^\s*alias\s+([A-Za-z0-9_-]+)=['"](.*)['"]\s*$/#
        for line in text.split(separator: "\n") {
            guard let match = String(line).wholeMatch(of: pattern) else { continue }
            let name = String(match.1)
            let command = String(match.2)
            guard command.hasSuffix("claude") else { continue }
            if command.contains("-u CLAUDE_CONFIG_DIR") {
                names[""] = names[""] ?? name
            } else if let dir = command.firstMatch(of: #/CLAUDE_CONFIG_DIR=\\?"?([^"\s\\]+)/#) {
                let path = String(dir.1)
                    .replacingOccurrences(of: "$HOME", with: home)
                    .replacingOccurrences(of: "~", with: home)
                names[path] = names[path] ?? name
            }
        }
        return names
    }

    /// The signed-in email, read from the account's `.claude.json`.
    var email: String? {
        let path = configDir.map { "\($0)/.claude.json" } ?? "\(NSHomeDirectory())/.claude.json"
        guard let data = FileManager.default.contents(atPath: path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = object["oauthAccount"] as? [String: Any] else { return nil }
        return account["emailAddress"] as? String
    }
}
