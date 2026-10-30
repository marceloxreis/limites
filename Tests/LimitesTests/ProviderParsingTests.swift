import Foundation
import Testing
@testable import Limites

private let newYork = TimeZone(identifier: "America/New_York")!

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, in zone: TimeZone = newYork) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

@Suite struct ClaudeUsageTests {
    let now = date(2026, 9, 14, 15, 0)

    @Test func readsEveryWindowFromUsageOutput() {
        let output = """
        You are currently using your subscription to power your Claude Code usage

        Current session: 70% used · resets Sep 14 at 7:30pm (America/New_York)
        Current week (all models): 48% used · resets Sep 15 at 1am (America/New_York)
        Current week (Sonnet only): 12.5% used · resets Sep 15 at 1am (America/New_York)

        What's contributing to your limits usage?
        """
        let windows = ClaudeProvider.parse(output, now: now)

        #expect(windows.map(\.title) == ["5-hour window", "Week", "Week · Sonnet only"])
        #expect(windows.map(\.usedPercent) == [70, 48, 12.5])
        #expect(windows[0].resetsAt == date(2026, 9, 14, 19, 30))
        #expect(windows[1].resetsAt == date(2026, 9, 15, 1))
    }

    @Test func ignoresOutputWithoutWindows() {
        #expect(ClaudeProvider.parse("Please run /login", now: now).isEmpty)
    }

    @Test func timeWithoutDateRollsOverToTomorrow() {
        // Without a zone in parentheses the reset is read in the Mac's own time zone.
        let local = TimeZone.current
        let evening = date(2026, 9, 14, 20, 0, in: local)
        #expect(ClaudeProvider.parseReset("7:29pm", now: evening) == date(2026, 9, 15, 19, 29, in: local))
        #expect(ClaudeProvider.parseReset("9pm", now: evening) == date(2026, 9, 14, 21, 0, in: local))
    }

    @Test func honorsTheTimeZoneInParentheses() {
        let utc = TimeZone(identifier: "UTC")!
        #expect(ClaudeProvider.parseReset("Sep 15 at 1am (UTC)", now: now) == date(2026, 9, 15, 1, in: utc))
    }

    @Test func dateEarlierThisYearMeansNextYear() {
        let december = date(2026, 12, 30, 12, 0)
        #expect(ClaudeProvider.parseReset("Jan 2 at 3pm (America/New_York)", now: december) == date(2027, 1, 2, 15, 0))
    }
}

@Suite struct CodexRateLimitTests {
    @Test func readsPrimaryAndSecondaryWindows() {
        let result: [String: Any] = [
            "rateLimitsByLimitId": [
                "codex": [
                    "planType": "plus",
                    "primary": ["usedPercent": 47, "windowDurationMins": 300, "resetsAt": 1_789_000_000],
                    "secondary": ["usedPercent": 24.5, "windowDurationMins": 10_080, "resetsAt": 1_789_500_000],
                ],
            ],
            "rateLimitResetCredits": ["availableCount": 3],
        ]
        let snapshot = CodexProvider.snapshot(from: result)

        #expect(snapshot.plan == "Plus")
        #expect(snapshot.windows.map(\.title) == ["5-hour window", "Week"])
        #expect(snapshot.windows.map(\.usedPercent) == [47, 24.5])
        #expect(snapshot.windows[0].resetsAt == Date(timeIntervalSince1970: 1_789_000_000))
        #expect(snapshot.footnote == "3 full resets available")
    }

    @Test func fallsBackToTheSingleRateLimitsObject() {
        let result: [String: Any] = ["rateLimits": ["primary": ["usedPercent": 5]]]
        let snapshot = CodexProvider.snapshot(from: result)
        #expect(snapshot.windows.map(\.title) == ["Short window"])
        #expect(snapshot.footnote == nil)
    }

    @Test func picksAReadableWindowTitle() {
        #expect(CodexProvider.windowTitle(minutes: 60, fallback: "") == "1-hour window")
        #expect(CodexProvider.windowTitle(minutes: 1_440, fallback: "") == "Day")
        #expect(CodexProvider.windowTitle(minutes: 4_320, fallback: "") == "3 days")
        #expect(CodexProvider.windowTitle(minutes: 90, fallback: "") == "90-minute window")
        #expect(CodexProvider.windowTitle(minutes: nil, fallback: "Long window") == "Long window")
    }
}

@Suite struct FormatTests {
    @Test func durations() {
        #expect(Format.duration(30) == "1 min")
        #expect(Format.duration(59 * 60) == "59 min")
        #expect(Format.duration(2 * 3600) == "2 h")
        #expect(Format.duration(2 * 3600 + 5 * 60) == "2 h 5 min")
        #expect(Format.duration(86_400) == "1 day")
        #expect(Format.duration(3 * 86_400 + 4 * 3600) == "3 days 4 h")
    }

    @Test func resetsBeyondTwelveHoursShareOneFormat() {
        let now = Date()
        let soon = Format.reset(now.addingTimeInterval(20 * 3600), now: now)
        let later = Format.reset(now.addingTimeInterval(6.5 * 86_400), now: now)
        // Both carry the date, whether the reset is tomorrow or a week away.
        #expect(soon.contains(String(Calendar.current.component(.day, from: now.addingTimeInterval(20 * 3600)))))
        #expect(later.contains(String(Calendar.current.component(.day, from: now.addingTimeInterval(6.5 * 86_400)))))
        #expect(!soon.contains("tomorrow") && !later.contains(" on "))
    }
}
