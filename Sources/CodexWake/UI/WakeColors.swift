import SwiftUI

enum WakeColors {
    static let sidebarBackground = Color(NSColor.windowBackgroundColor)
    static let panelBackground = Color(NSColor.controlBackgroundColor)
    static let secondaryPanelBackground = Color(NSColor.textBackgroundColor)

    static let userMessageBackground = Color(light: NSColor(calibratedRed: 0.88, green: 0.95, blue: 1.0, alpha: 1.0),
                                             dark: NSColor(calibratedRed: 0.10, green: 0.18, blue: 0.24, alpha: 1.0))
    static let userMessageHeader = Color(light: NSColor(calibratedRed: 0.05, green: 0.30, blue: 0.52, alpha: 1.0),
                                         dark: NSColor(calibratedRed: 0.58, green: 0.80, blue: 1.0, alpha: 1.0))

    static let steeredMessageBackground = Color(light: NSColor(calibratedRed: 1.0, green: 0.94, blue: 0.84, alpha: 1.0),
                                                dark: NSColor(calibratedRed: 0.24, green: 0.16, blue: 0.08, alpha: 1.0))
    static let steeredMessageHeader = Color(light: NSColor.systemOrange,
                                            dark: NSColor(calibratedRed: 1.0, green: 0.68, blue: 0.32, alpha: 1.0))

    static func reportBackground(_ color: Color) -> Color {
        color.opacity(0.10)
    }

    static func selectionBackground(_ color: Color) -> Color {
        color.opacity(0.14)
    }
}

private extension Color {
    init(light: NSColor, dark: NSColor) {
        self.init(NSColor(name: nil) { appearance in
            let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
            return bestMatch == .darkAqua ? dark : light
        })
    }
}
