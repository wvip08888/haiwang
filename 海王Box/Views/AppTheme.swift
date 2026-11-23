import SwiftUI

/// 主题配色（对应安卓 theme / 主题颜色）
enum AppTheme {
    static let seeds: [(name: String, color: Color)] = [
        ("红色", .red), ("橙色", .orange), ("黄色", .yellow), ("绿色", .green),
        ("青色", .cyan), ("蓝色", .blue), ("紫色", .purple), ("粉色", .pink)
    ]

    static func seedColor() -> Color {
        let name = UserDefaults.standard.string(forKey: "themeSeed") ?? "蓝色"
        return seeds.first { $0.name == name }?.color ?? .blue
    }

    static func accent() -> Color { seedColor() }
}

/// 主题模式：自动 / 浅色 / 深色
enum ThemeMode: String, CaseIterable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "自动"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

/// 跨页面共享的主题环境
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    @Published var mode: ThemeMode = {
        let raw = UserDefaults.standard.string(forKey: "themeMode") ?? "auto"
        return ThemeMode(rawValue: raw) ?? .auto
    }()
    @Published var pureBlack: Bool = UserDefaults.standard.bool(forKey: "pureBlack")
    @AppStorage("themeSeed") var seedName: String = "蓝色"

    var colorScheme: ColorScheme? {
        switch mode {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    func setMode(_ m: ThemeMode) {
        mode = m
        UserDefaults.standard.set(m.rawValue, forKey: "themeMode")
    }
}
