import Foundation

/// Sample data for screenshots and for trying the app without either CLI signed in:
/// `open Limites.app --args --demo`. Nothing is read, sent or registered in this mode.
enum Demo {
    static let isEnabled = CommandLine.arguments.contains("--demo")

    static var claude: ProviderSnapshot {
        ProviderSnapshot(windows: [
            UsageWindow(id: "claude.session", title: String(localized: "5-hour window"), usedPercent: 38, resetsAt: later(hours: 2, minutes: 17)),
            UsageWindow(id: "claude.week", title: String(localized: "Week"), usedPercent: 61, resetsAt: later(hours: 77)),
        ])
    }

    static var codex: ProviderSnapshot {
        ProviderSnapshot(
            windows: [
                UsageWindow(id: "codex.primary", title: CodexProvider.windowTitle(minutes: 300, fallback: ""), usedPercent: 12, resetsAt: later(hours: 4, minutes: 40)),
                UsageWindow(id: "codex.secondary", title: CodexProvider.windowTitle(minutes: 10_080, fallback: ""), usedPercent: 84, resetsAt: later(hours: 29)),
            ],
            plan: "Plus",
            footnote: String(localized: "1 full reset available")
        )
    }

    static var attention: [AttentionItem] {
        [
            AttentionItem(id: "demo.1", source: "claude", kind: .permission, cwd: "/tmp/weather-app", tool: "Bash", date: .now.addingTimeInterval(-20)),
            AttentionItem(id: "demo.2", source: "codex", kind: .finished, cwd: "/tmp/notes", date: .now.addingTimeInterval(-4 * 60)),
        ]
    }

    private static func later(hours: Int, minutes: Int = 0) -> Date {
        .now.addingTimeInterval(TimeInterval(hours * 3600 + minutes * 60))
    }
}
