import AppKit

/// Talks to Terminal (and iTerm2) over AppleScript: which tab is in front, and how
/// to bring a specific tab forward, identified by its tty.
enum TerminalBridge {
    private static let terminal = "com.apple.Terminal"
    private static let iTerm = "com.googlecode.iterm2"

    /// The tty of the tab in front of you, when a supported terminal is the active app.
    /// Without an Automation permission already granted it returns nil instead of
    /// asking: the system prompt blocks the calling thread until someone answers.
    static func focusedTTY() -> String? {
        switch NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
        case terminal where isAuthorized(terminal):
            return run(#"tell application id "com.apple.Terminal" to get tty of selected tab of front window"#)
        case iTerm where isAuthorized(iTerm):
            return run(#"tell application id "com.googlecode.iterm2" to get tty of current session of current window"#)
        default:
            return nil
        }
    }

    /// Asks for the Automation permission off the main thread (once; the system remembers).
    static func requestAuthorization() {
        DispatchQueue.global(qos: .utility).async {
            for id in [terminal, iTerm] where isRunning(id) {
                _ = permission(id, ask: true)
            }
        }
    }

    private static func isAuthorized(_ bundleID: String) -> Bool {
        permission(bundleID, ask: false) == noErr
    }

    private static func permission(_ bundleID: String, ask: Bool) -> OSStatus {
        var target = AEAddressDesc()
        let created = bundleID.withCString { AECreateDesc(typeApplicationBundleID, $0, strlen($0), &target) }
        guard created == noErr else { return OSStatus(created) }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, ask)
    }

    static var terminalIsFrontmost: Bool {
        let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return id == terminal || id == iTerm
    }

    /// Triggered by a click, so this is where the permission prompt may appear.
    @discardableResult
    static func focus(tty: String, program: String?) -> Bool {
        let tty = tty.replacingOccurrences(of: "\"", with: "")
        if program == "iTerm.app" || isRunning(iTerm) && !isRunning(terminal) {
            let script = """
            tell application id "com.googlecode.iterm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select w
                                select t
                                select s
                                activate
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
            if run(script) == "ok" { return true }
        }
        guard isRunning(terminal) else { return false }
        let script = """
        tell application id "com.apple.Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected tab of w to t
                        set index of w to 1
                        activate
                        return "ok"
                    end if
                end repeat
            end repeat
        end tell
        """
        return run(script) == "ok"
    }

    private static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static func run(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result?.stringValue : nil
    }
}
