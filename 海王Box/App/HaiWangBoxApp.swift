import SwiftUI
import AVFoundation

@main
struct HaiWangBoxApp: App {
    @StateObject private var theme = ThemeManager.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(theme)
                .accentColor(AppTheme.accent())
        }
    }
}

/// App 生命周期代理（对应 App.kt / Application）
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // 初始化配置（加载内置广告过滤规则）
        ConfigService.shared.loadBuiltinConfig()
        // 允许后台音频播放
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        return true
    }

    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        // 下载任务的后台完成处理
        completionHandler()
    }
}
