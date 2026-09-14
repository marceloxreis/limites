import AppKit
import ServiceManagement
import SwiftUI

struct MenuContent: View {
    @Environment(UsageStore.self) private var usage
    @Environment(AttentionCenter.self) private var attention

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            VStack(alignment: .leading, spacing: 0) {
                Header(now: context.date)

                if !attention.items.isEmpty {
                    MenuDivider()
                    AttentionSection(now: context.date)
                }

                MenuDivider()
                ProviderSection(name: "Claude Code", state: usage.claude, now: context.date)
                MenuDivider()
                ProviderSection(name: "Codex", state: usage.codex, now: context.date)
                MenuDivider()
                SettingsSection()
                MenuDivider()
                MenuButtonRow(title: String(localized: "Quit Limites"), shortcut: "⌘Q") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .padding(5)
            .frame(width: 310)
        }
        .onAppear { usage.refreshIfStale() }
        .background(WindowObserver { usage.refreshIfStale() })
    }
}

// MARK: - Header

private struct Header: View {
    @Environment(UsageStore.self) private var usage
    let now: Date

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Usage limits")
                    .font(.system(size: 13, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                usage.refresh()
            } label: {
                ZStack {
                    if usage.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(0.1)))
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r")
            .help("Refresh now")
        }
        .padding(.horizontal, 9)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    private var subtitle: String {
        guard let last = usage.lastUpdated else { return String(localized: "Checking…") }
        let seconds = now.timeIntervalSince(last)
        if seconds < 60 { return String(localized: "Updated just now") }
        let elapsed = Format.duration(seconds)
        return String(localized: "Updated \(elapsed) ago")
    }
}

// MARK: - Waiting tabs

private struct AttentionSection: View {
    @Environment(AttentionCenter.self) private var attention
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                SectionTitle(attention.items.count == 1 ? String(localized: "Tab needs you") : String(localized: "Tabs need you"))
                Spacer()
                Button("Clear") { attention.clearAll() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.top, 4)
            .padding(.bottom, 2)

            ForEach(attention.items) { item in
                AttentionRow(item: item, now: now) { attention.open(item) }
            }
        }
        .padding(.bottom, 2)
    }
}

private struct AttentionRow: View {
    let item: AttentionItem
    let now: Date
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    Circle().fill(item.kind == .finished ? Color.primary.opacity(0.1) : Color.accentColor)
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(item.kind == .finished ? Color.primary : Color.white)
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.project)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Text("\(item.sourceName) · \(item.detail)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(Format.ago(item.date, now: now))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(Highlight(active: hovering))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(item.tty == nil ? "" : String(localized: "Go to tab"))
    }

    private var symbol: String {
        switch item.kind {
        case .permission: return "hand.raised.fill"
        case .finished: return "checkmark"
        case .question: return "questionmark"
        }
    }
}

// MARK: - Providers

private struct ProviderSection: View {
    let name: String
    let state: ProviderState
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 6) {
                SectionTitle(name)
                if let plan = state.snapshot?.plan {
                    Text(plan)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.1)))
                }
                Spacer()
            }

            if let snapshot = state.snapshot {
                ForEach(snapshot.windows) { window in
                    WindowRow(window: window, now: now)
                }
                if let footnote = snapshot.footnote {
                    Text(footnote)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else if state.error == nil {
                WindowRow(window: UsageWindow(id: "placeholder", title: String(localized: "5-hour window"), usedPercent: 0, resetsAt: nil), now: now)
                    .redacted(reason: .placeholder)
            }

            if let error = state.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
    }
}

private struct WindowRow: View {
    let window: UsageWindow
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title)
                    .font(.system(size: 13))
                Spacer(minLength: 8)
                Text(verbatim: "\(Int(window.usedPercent.rounded()))%")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            UsageBar(fraction: window.usedPercent / 100)
            if let reset = window.resetsAt {
                Text(Format.reset(reset, now: now))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct UsageBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(tint)
                    .frame(width: max(fraction > 0 ? 4 : 0, proxy.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 4)
        .animation(.smooth(duration: 0.45), value: fraction)
    }

    private var tint: Color {
        if fraction >= 0.95 { return .red }
        if fraction >= 0.8 { return .orange }
        return .accentColor
    }
}

// MARK: - Settings

private struct SettingsSection: View {
    @AppStorage("showPercent") private var showPercent = false
    @AppStorage("sound") private var sound = "Glass"
    @Environment(AttentionCenter.self) private var attention
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 0) {
            ToggleRow(title: String(localized: "Percentage in menu bar"), isOn: $showPercent)

            HStack {
                Text("Alert sound")
                    .font(.system(size: 13))
                Spacer(minLength: 8)
                Picker("Sound", selection: $sound) {
                    Text("None").tag(AttentionCenter.silent)
                    Divider()
                    ForEach(AttentionCenter.sounds, id: \.self) { Text(verbatim: $0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .controlSize(.small)
                .onChange(of: sound) { _, new in attention.playSound(named: new) }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)

            ToggleRow(title: String(localized: "Open at login"), isOn: Binding(
                get: { launchAtLogin },
                set: { enable in
                    do {
                        if enable { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {}
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            ))
        }
        .padding(.vertical, 3)
    }
}

private struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
    }
}

// MARK: - Menu pieces

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

private struct MenuDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
    }
}

private struct MenuButtonRow: View {
    let title: String
    var shortcut: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 13))
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(Highlight(active: hovering))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct Highlight: View {
    let active: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.primary.opacity(active ? 0.1 : 0))
    }
}

/// Reports when the menu window becomes visible again, so stale data gets refreshed.
private struct WindowObserver: NSViewRepresentable {
    let onShow: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ObserverView()
        view.onShow = onShow
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ObserverView)?.onShow = onShow
    }

    final class ObserverView: NSView {
        var onShow: (() -> Void)?
        private var token: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let token { NotificationCenter.default.removeObserver(token) }
            guard let window else { return }
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in self?.onShow?() }
        }
    }
}

// MARK: - Formatting

enum Format {
    /// Dates follow the language the app is shown in, so a sentence never mixes two languages.
    private static let locale: Locale = {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        let current = Locale.current
        return current.language.languageCode?.identifier == Locale(identifier: language).language.languageCode?.identifier
            ? current : Locale(identifier: language)
    }()

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.down)))
        if minutes < 60 { return String(localized: "\(minutes) min") }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours < 24 { return rest == 0 ? String(localized: "\(hours) h") : String(localized: "\(hours) h \(rest) min") }
        let days = hours / 24
        let restHours = hours % 24
        if restHours == 0 { return days == 1 ? String(localized: "1 day") : String(localized: "\(days) days") }
        return days == 1 ? String(localized: "1 day \(restHours) h") : String(localized: "\(days) days \(restHours) h")
    }

    static func ago(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        return seconds < 60 ? String(localized: "now") : duration(seconds)
    }

    /// Under 12 h: a countdown. Beyond that: day and time.
    static func reset(_ date: Date, now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return String(localized: "Resetting") }
        if seconds < 12 * 3600 {
            let remaining = duration(seconds)
            return String(localized: "Resets in \(remaining)")
        }

        let calendar = Calendar.current
        let time = date.formatted(.dateTime.hour().minute().locale(locale))
        if calendar.isDateInTomorrow(date) { return String(localized: "Resets tomorrow at \(time)") }
        if calendar.isDateInToday(date) { return String(localized: "Resets today at \(time)") }
        if seconds < 6 * 86_400 {
            let weekday = date.formatted(.dateTime.weekday(.wide).locale(locale))
            return String(localized: "Resets \(weekday) at \(time)")
        }
        let day = date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
        return String(localized: "Resets on \(day) at \(time)")
    }
}
