// Called by Claude Code and Codex hooks. Reads the event JSON, finds the terminal
// tab the session runs in and tells Limites. It never writes to stdout: hook output
// becomes context or a decision for the agent.
import Darwin
import Foundation

signal(SIGALRM) { _ in exit(0) }
alarm(3)

let arguments = CommandLine.arguments
let source = arguments.count > 1 ? arguments[1] : "claude"

var payload: [String: Any] = [:]
if arguments.count > 2, let object = try? JSONSerialization.jsonObject(with: Data(arguments[2].utf8)) as? [String: Any] {
    payload = object
} else if isatty(STDIN_FILENO) == 0 {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    payload = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
}

struct ProcessInfoEntry {
    let parent: pid_t
    let tty: String?
    let arguments: [String]
}

func inspect(_ pid: pid_t) -> ProcessInfoEntry? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
    var tty: String?
    let device = info.kp_eproc.e_tdev
    if device != -1, let name = devname(device, S_IFCHR) {
        let text = String(cString: name)
        if text != "??" { tty = "/dev/" + text }
    }
    return ProcessInfoEntry(parent: info.kp_eproc.e_ppid, tty: tty, arguments: commandLine(of: pid))
}

func commandLine(of pid: pid_t) -> [String] {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
    var buffer = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }
    let count = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
    var index = MemoryLayout<Int32>.size
    while index < size, buffer[index] != 0 { index += 1 }
    while index < size, buffer[index] == 0 { index += 1 }
    var result: [String] = []
    while result.count < count, index < size {
        let start = index
        while index < size, buffer[index] != 0 { index += 1 }
        result.append(String(decoding: buffer[start..<index], as: UTF8.self))
        index += 1
    }
    return result
}

// Walk up the process tree to the agent. It owns the tab (tty) and tells whether the
// session is interactive: `claude -p` and `codex exec` run from scripts, with nobody watching.
var tty: String?
var headless = false
var pid = getppid()
for _ in 0..<10 where pid > 1 {
    guard let entry = inspect(pid) else { break }
    let names = entry.arguments.prefix(3).map { ($0 as NSString).lastPathComponent }
    let isAgent = names.contains(source) || entry.arguments.prefix(3).contains { $0.contains("claude-code") }
    if isAgent {
        tty = entry.tty
        let rest = Array(entry.arguments.dropFirst())
        if source == "claude" { headless = rest.contains("-p") || rest.contains("--print") }
        if source == "codex" { headless = rest.first == "exec" || rest.first == "e" }
        break
    }
    if tty == nil { tty = entry.tty }
    pid = entry.parent
}

if let override = ProcessInfo.processInfo.environment["LIMITES_TTY"] { tty = override }
if ProcessInfo.processInfo.environment["LIMITES_DEBUG"] != nil {
    FileHandle.standardError.write(Data("tty=\(tty ?? "nil") headless=\(headless)\n".utf8))
}
guard !headless, let tty else { exit(0) }

func string(_ key: String) -> String {
    if let value = payload[key] as? String { return value }
    if let value = payload[key] as? NSNumber { return value.stringValue }
    return ""
}

let event = string("hook_event_name").isEmpty ? string("type") : string("hook_event_name")
let info: [String: String] = [
    "source": source,
    "event": event,
    "session": string("session_id"),
    "cwd": string("cwd").isEmpty ? FileManager.default.currentDirectoryPath : string("cwd"),
    "message": string("message"),
    "notificationType": string("notification_type"),
    "tool": string("tool_name"),
    "tty": tty,
    "program": ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? "",
]

DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("io.github.joshazze.limites.signal"), object: nil, userInfo: info, deliverImmediately: true
)
exit(0)
