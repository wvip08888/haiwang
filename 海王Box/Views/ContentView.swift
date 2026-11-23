import SwiftUI

/// 主标签枚举（对应 MainScreen 的 AppTab）
enum AppTab: Int, CaseIterable, Identifiable {
    case home = 0, music, records, following, mine
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .home: return "首页"
        case .music: return "音乐"
        case .records: return "记录"
        case .following: return "追剧"
        case .mine: return "我的"
        }
    }
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .music: return "music.note"
        case .records: return "clock.arrow.circlepath"
        case .following: return "bookmark.fill"
        case .mine: return "person.fill"
        }
    }
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .home
    @StateObject private var theme = ThemeManager.shared
    @State private var showLive = false
    @StateObject private var audio = AudioPlaybackService.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            HomePage()
                .tabItem { Label(AppTab.home.label, systemImage: AppTab.home.icon) }
                .tag(AppTab.home)

            MusicPage()
                .tabItem { Label(AppTab.music.label, systemImage: AppTab.music.icon) }
                .tag(AppTab.music)

            RecordsPage()
                .tabItem { Label(AppTab.records.label, systemImage: AppTab.records.icon) }
                .tag(AppTab.records)

            FollowingPage()
                .tabItem { Label(AppTab.following.label, systemImage: AppTab.following.icon) }
                .tag(AppTab.following)

            SettingsPage()
                .tabItem { Label(AppTab.mine.label, systemImage: AppTab.mine.icon) }
                .tag(AppTab.mine)
        }
        .tint(AppTheme.accent())
        .colorScheme(theme.colorScheme ?? .light)
        .sheet(isPresented: $showLive) { LivePlayView() }
        .overlay(alignment: .bottom) {
            // 迷你播放器（对应 BottomMiniPlayer）
            if !audio.tracks.isEmpty {
                MiniPlayerBar()
                    .padding(.bottom, 56)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: audio.tracks.isEmpty)
        .onReceive(NotificationCenter.default.publisher(for: .openLive)) { _ in
            showLive = true
        }
        .onAppear {
            // 默认启动直播
            if StorageService.shared.flag("defaultLoadLive") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showLive = true }
            }
        }
    }
}

/// 迷你播放条
struct MiniPlayerBar: View {
    @ObservedObject var audio = AudioPlaybackService.shared
    @State private var showPlayer = false
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: audio.currentTrack?.coverUrl ?? "")) { phase in
                if let img = phase.image { img.resizable().scaledToFill() }
                else { Color.gray.opacity(0.3).overlay(Image(systemName: "music.note")) }
            }
            .frame(width: 40, height: 40).cornerRadius(8).clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text(audio.currentTrack?.title ?? "未在播放").font(.subheadline).lineLimit(1)
                Text(audio.currentTrack?.artist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { audio.togglePlay() } label: {
                Image(systemName: audio.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
            }
            Button { audio.next() } label: {
                Image(systemName: "forward.fill").font(.title3)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
        .onTapGesture { showPlayer = true }
        .sheet(isPresented: $showPlayer) { MusicPlayerView() }
    }
}

extension Notification.Name {
    static let openLive = Notification.Name("openLive")
}
