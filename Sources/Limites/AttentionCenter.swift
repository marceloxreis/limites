import AppKit
import Observation

struct AttentionItem: Identifiable, Equatable {
    enum Kind: String {
        case permission
        case finished
        case question
    }

    let id: String
    var source: String
    var kind: Kind
    var cwd: String
    var tool: String?
    var tty: String?
    var program: String?
    var date: Date

    var project: String {
        if cwd.isEmpty { return "Terminal" }
        if cwd == NSHomeDirectory() { return String(localized: "Home") }
        return (cwd as NSString).lastPathComponent
    }

    var sourceName: String { source == "codex" ? "Codex" : "Claude Code" }

    var detail: String {
        switch kind {
        case .permission:
            if let tool, !tool.isEmpty { return String(localized: "Wants permission to use \(tool)") }
            return String(localized: "Wants permission")
        case .finished: return String(localized: "Finished, waiting for you")
        case .question: return String(localized: "Has a question")
        }
    }
}

/// Receives hook signals (Claude Code and Codex), plays the sound, swings the bell
/// and clears the alert once you get to the tab.
@MainActor
@Observable
final class AttentionCenter: NSObject {
    static let signalName = Notification.Name("io.github.joshazze.limites.signal")
    static let silent = "None"
    static let sounds = ["Glass", "Ping", "Tink", "Pop", "Purr", "Hero", "Submarine", "Funk", "Bottle", "Blow", "Morse", "Frog", "Sosumi", "Basso"]

    private(set) var items: [AttentionItem] = []
    /// Angle of the menu bar bell, in degrees. Zero at rest.
    private(set) var bellAngle: Double = 0

    @ObservationIgnored private var ringStartedAt: Date?
    @ObservationIgnored private var frameTimer: Timer?
    @ObservationIgnored private var pulseTimer: Timer?
    @ObservationIgnored private var nextRing = Date.distantFuture

    override init() {
        super.init()
        // Demo mode shows sample rows only, so real sessions never end up in a screenshot.
        if Demo.isEnabled {
            items = Demo.attention
            return
        }
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(receive(_:)), name: Self.signalName, object: nil,
            suspensionBehavior: .deliverImmediately
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        TerminalBridge.requestAuthorization()
    }

    // MARK: Signals

    @objc private nonisolated func receive(_ note: Notification) {
        let info = (note.userInfo as? [String: String]) ?? [:]
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.handle(info) }
        }
    }

    func handle(_ info: [String: String]) {
        let session = info["session"].flatMap { $0.isEmpty ? nil : $0 }
        let tty = info["tty"].flatMap { $0.isEmpty ? nil : $0 }
        guard let key = session ?? tty else { return }
        let event = info["event"] ?? ""

        if event == "UserPromptSubmit" {
            items.removeAll { $0.id == key || ($0.tty != nil && $0.tty == tty) }
            return
        }
        guard let kind = Self.kind(event: event, info: info) else { return }

        // You are already looking at this tab: no sound.
        if let tty, TerminalBridge.focusedTTY() == tty {
            items.removeAll { $0.id == key }
            return
        }

        var tool = info["tool"] ?? ""
        if tool.isEmpty, let message = info["message"],
           let range = message.range(of: #"(?<=permission to use ).+$"#, options: .regularExpression) {
            tool = String(message[range]).trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        }
        let item = AttentionItem(
            id: key, source: info["source"] ?? "claude", kind: kind, cwd: info["cwd"] ?? "",
            tool: tool, tty: tty, program: info["program"], date: .now
        )
        if let index = items.firstIndex(where: { $0.id == key }) {
            let previous = items[index]
            items[index] = item
            // A repeated alert of the same kind (e.g. "still waiting") does not play again.
            if previous.kind == kind { return }
        } else {
            items.insert(item, at: 0)
        }
        playSound()
        ring()
        startPulse()
    }

    private static func kind(event: String, info: [String: String]) -> AttentionItem.Kind? {
        switch event {
        case "Stop":
            return .finished
        case "PermissionRequest":
            return .permission
        case "Notification":
            let type = info["notificationType"] ?? ""
            let message = (info["message"] ?? "").lowercased()
            if type == "permission_prompt" || message.contains("permission") { return .permission }
            if type == "idle_prompt" || message.contains("waiting for your input") { return .finished }
            if type == "auth_success" { return nil }
            return .question
        default:
            return nil
        }
    }

    // MARK: Actions

    func open(_ item: AttentionItem) {
        items.removeAll { $0.id == item.id }
        if let tty = item.tty { TerminalBridge.focus(tty: tty, program: item.program) }
        stopIfIdle()
    }

    func clearAll() {
        items.removeAll()
        stopIfIdle()
    }

    func playSound(named name: String? = nil) {
        let chosen = name ?? UserDefaults.standard.string(forKey: "sound") ?? "Glass"
        guard chosen != Self.silent else { return }
        NSSound(named: NSSound.Name(chosen))?.play()
    }

    // MARK: Back at the tab

    @objc private nonisolated func appActivated(_ note: Notification) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.dismissFocused() }
        }
    }

    /// You touched the tab after the alert: a key press (approve, reply) or switching to
    /// it, which makes the terminal send a focus event. Both update the tty's last read
    /// time, the same value `w` shows as IDLE. No permission needed. The 1.5 s grace
    /// period ignores automatic terminal replies right after the alert.
    private func dismissAnswered() {
        let before = items.count
        items.removeAll { item in
            guard let tty = item.tty else { return false }
            var info = stat()
            guard stat(tty, &info) == 0 else { return true } // tab closed
            let read = TimeInterval(info.st_atimespec.tv_sec) + TimeInterval(info.st_atimespec.tv_nsec) / 1e9
            return read > item.date.timeIntervalSince1970 + 1.5
        }
        if items.count != before { stopIfIdle() }
    }

    private func dismissFocused() {
        guard !items.isEmpty, TerminalBridge.terminalIsFrontmost, let tty = TerminalBridge.focusedTTY() else { return }
        let before = items.count
        items.removeAll { $0.tty == tty }
        if items.count != before { stopIfIdle() }
    }

    // MARK: Motion

    /// Bell swing: a damped oscillation around the handle that settles without overshoot.
    func ring() {
        ringStartedAt = .now
        guard frameTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.frame() }
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    private func frame() {
        guard let start = ringStartedAt else { return }
        let t = Date.now.timeIntervalSince(start)
        let duration = 1.3
        if t >= duration {
            bellAngle = 0
            frameTimer?.invalidate()
            frameTimer = nil
            ringStartedAt = nil
            return
        }
        let envelope = exp(-2.6 * t) * (1 - t / duration)
        bellAngle = 20 * envelope * sin(2 * .pi * 2.8 * t)
    }

    /// While a tab is waiting the bell swings again: every 6 s for the first
    /// 2 minutes, then every 30 s. The sound plays only once.
    private func startPulse() {
        scheduleNextRing()
        guard pulseTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pulse() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pulseTimer = timer
    }

    private func pulse() {
        dismissAnswered()
        if TerminalBridge.terminalIsFrontmost { dismissFocused() }
        if items.isEmpty { return stopIfIdle() }
        if Date.now >= nextRing {
            ring()
            scheduleNextRing()
        }
    }

    private func scheduleNextRing() {
        let newest = items.map(\.date).max() ?? .now
        let gap: TimeInterval = Date.now.timeIntervalSince(newest) < 120 ? 6 : 30
        nextRing = Date.now.addingTimeInterval(gap)
    }

    private func stopIfIdle() {
        guard items.isEmpty else { return }
        pulseTimer?.invalidate()
        pulseTimer = nil
        nextRing = .distantFuture
    }
}
