import SwiftUI

/// App appearance preference. Persisted in UserDefaults. Default: dark with a
/// professional blue accent, per the product brief.
enum AppTheme: String, CaseIterable, Identifiable {
    case dark, light, medium
    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark, .medium: return .dark
        case .light: return .light
        }
    }

    var displayName: String { rawValue.capitalized }
}

@MainActor
final class ThemeSettings: ObservableObject {
    @AppStorage("vua.theme") private var stored: String = AppTheme.dark.rawValue

    var theme: AppTheme {
        get { AppTheme(rawValue: stored) ?? .dark }
        set { stored = newValue.rawValue; objectWillChange.send() }
    }

    /// Professional blue accent.
    let accent = Color(.sRGB, red: 0.039, green: 0.518, blue: 1.0, opacity: 1)

    var canvasBackground: Color {
        switch theme {
        case .light: return Color(white: 0.92)
        case .medium: return Color(white: 0.18)
        case .dark: return Color(white: 0.10)
        }
    }
}
