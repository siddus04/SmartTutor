import SwiftUI

extension Color {
    static var appBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemBackground)
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor.windowBackgroundColor)
        #else
        return Color.white
        #endif
    }
}
