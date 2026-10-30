import Foundation

/// The Claude Code accounts shown in the panel. Each one is a config dir
/// (`CLAUDE_CONFIG_DIR`); `nil` means the default `~/.claude`.
struct ClaudeAccount: Identifiable, Equatable {
    let id: String
    let name: String
    let configDir: String?

    static let all: [ClaudeAccount] = {
        let home = NSHomeDirectory()
        return [
            ClaudeAccount(id: "claude1", name: "claude1", configDir: nil),
            ClaudeAccount(id: "claude2", name: "claude2", configDir: "\(home)/.claude-acc2"),
            ClaudeAccount(id: "claudeorbi", name: "claudeorbi", configDir: "\(home)/.claude-acc-orbi"),
        ]
    }()

    /// The signed-in email, read from the account's `.claude.json`.
    var email: String? {
        let path = configDir.map { "\($0)/.claude.json" } ?? "\(NSHomeDirectory())/.claude.json"
        guard let data = FileManager.default.contents(atPath: path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = object["oauthAccount"] as? [String: Any] else { return nil }
        return account["emailAddress"] as? String
    }
}
