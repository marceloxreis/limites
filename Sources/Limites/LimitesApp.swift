import AppKit
import ServiceManagement
import SwiftUI

@main
struct LimitesApp: App {
    @State private var usage = UsageStore()
    @State private var attention = AttentionCenter()
    @AppStorage("showPercent") private var showPercent = false

    init() {
        // First launch: register as a login item. Otherwise tab alerts only work
        // while someone remembers to open the app.
        let defaults = UserDefaults.standard
        if !Demo.isEnabled, !defaults.bool(forKey: "didConfigureLoginItem") {
            try? SMAppService.mainApp.register()
            defaults.set(true, forKey: "didConfigureLoginItem")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(usage)
                .environment(attention)
        } label: {
            Image(nsImage: StatusIcon.image(
                highestUsage: usage.highestUsage,
                showPercent: showPercent,
                pending: attention.items.count,
                bellAngle: attention.bellAngle
            ))
        }
        .menuBarExtraStyle(.window)
    }
}
