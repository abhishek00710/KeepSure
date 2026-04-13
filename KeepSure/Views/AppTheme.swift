import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.70, green: 0.58, blue: 0.39)
    static let secondaryAccent = Color(red: 0.42, green: 0.36, blue: 0.30)
    static let ink = Color(red: 0.21, green: 0.19, blue: 0.18)
    static let night = Color(red: 0.39, green: 0.34, blue: 0.30)
    static let plum = Color(red: 0.73, green: 0.68, blue: 0.62)
    static let sand = Color(red: 0.95, green: 0.92, blue: 0.88)
    static let mist = Color(red: 0.90, green: 0.86, blue: 0.81)
    static let ivory = Color(red: 0.98, green: 0.97, blue: 0.95)
    static let success = Color(red: 0.42, green: 0.60, blue: 0.46)
    static let warning = Color(red: 0.79, green: 0.58, blue: 0.32)

    static let dashboardGradient = LinearGradient(
        colors: [Color(red: 0.95, green: 0.91, blue: 0.85), Color(red: 0.84, green: 0.78, blue: 0.70)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let captureGradient = LinearGradient(
        colors: [Color(red: 0.86, green: 0.89, blue: 0.87), Color(red: 0.74, green: 0.79, blue: 0.77)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let homeBackground = LinearGradient(
        colors: [Color(red: 0.97, green: 0.95, blue: 0.92), Color(red: 0.92, green: 0.88, blue: 0.83), Color(red: 0.87, green: 0.82, blue: 0.76)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let panelFill = Color.white.opacity(0.92)
    static let elevatedPanelFill = Color.white.opacity(0.62)
}
