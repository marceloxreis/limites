import AppKit

/// Draws the menu bar item as a template image, like the system icons:
/// monochrome, so macOS tints it white or black to match the menu bar.
enum StatusIcon {
    private static let height: CGFloat = 22
    private static let gap: CGFloat = 5

    static func image(highestUsage: Double?, showPercent: Bool, pending: Int, bellAngle: Double) -> NSImage {
        let gauge = symbol(gaugeName(for: highestUsage), pointSize: 15, weight: .semibold)
        let bell = pending > 0 ? symbol("bell.fill", pointSize: 14, weight: .semibold) : nil

        let percent: NSAttributedString? = {
            guard showPercent, let highestUsage else { return nil }
            let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            return NSAttributedString(string: "\(Int(highestUsage.rounded()))%", attributes: [
                .font: font, .foregroundColor: NSColor.black,
            ])
        }()

        // Side padding so the bell is not clipped while it swings.
        let bellSlot: CGFloat = bell.map { $0.size.width + 4 } ?? 0
        var width = gauge.size.width
        if bell != nil { width += bellSlot + gap }
        if let percent { width += gap + ceil(percent.size().width) }

        let image = NSImage(size: NSSize(width: ceil(width), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            if let bell, let context = NSGraphicsContext.current?.cgContext {
                let rect = NSRect(
                    x: x + 2, y: floor((height - bell.size.height) / 2),
                    width: bell.size.width, height: bell.size.height
                )
                context.saveGState()
                // Pivot on the handle, at the top of the bell.
                context.translateBy(x: rect.midX, y: rect.maxY - 1)
                context.rotate(by: -bellAngle * .pi / 180)
                context.translateBy(x: -rect.midX, y: -(rect.maxY - 1))
                bell.draw(in: rect)
                context.restoreGState()
                x += bellSlot + gap
            }
            gauge.draw(in: NSRect(
                x: x, y: floor((height - gauge.size.height) / 2),
                width: gauge.size.width, height: gauge.size.height
            ))
            x += gauge.size.width
            if let percent {
                let size = percent.size()
                percent.draw(at: NSPoint(x: x + gap, y: floor((height - size.height) / 2) + 0.5))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibility(highestUsage: highestUsage, pending: pending)
        return image
    }

    private static func gaugeName(for usage: Double?) -> String {
        guard let usage else { return "gauge.with.dots.needle.0percent" }
        switch usage {
        case ..<17: return "gauge.with.dots.needle.0percent"
        case ..<42: return "gauge.with.dots.needle.33percent"
        case ..<59: return "gauge.with.dots.needle.50percent"
        case ..<85: return "gauge.with.dots.needle.67percent"
        default: return "gauge.with.dots.needle.100percent"
        }
    }

    private static func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
        return base.withSymbolConfiguration(config) ?? base
    }

    private static func accessibility(highestUsage: Double?, pending: Int) -> String {
        var parts = ["Limites"]
        if let highestUsage {
            let percent = "\(Int(highestUsage.rounded()))%"
            parts.append(String(localized: "\(percent) used"))
        }
        if pending > 0 {
            parts.append(pending == 1 ? String(localized: "1 tab needs you") : String(localized: "\(pending) tabs need you"))
        }
        return parts.joined(separator: ", ")
    }
}
