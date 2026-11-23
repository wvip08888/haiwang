import SwiftUI

/// 音乐收藏页
struct MusicFavoritesView: View {
    @StateObject private var vm = MusicViewModel()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if vm.favorites.isEmpty {
                    ContentUnavailableView {
                        Label("暂无收藏", systemImage: "heart")
                    } description: { Text("在歌曲列表点击爱心即可收藏") }
                } else {
                    List {
                        ForEach(vm.favorites) { track in
                            TrackRow(track: track) {
                                vm.play(tracks: vm.favorites, at: vm.favorites.firstIndex(where: { $0.id == track.id }) ?? 0)
                            } onFavorite: {
                                vm.toggleFavorite(track)
                            } onDownload: {
                                Task {
                                    var t = track
                                    if t.playUrl.isEmpty { t.playUrl = await MusicRepository.shared.resolvePlayURL(t) }
                                    DownloadService.shared.download(t)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("我的收藏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
        .task { await vm.load() }
    }
}

/// 榜单/歌单详情页
struct MusicCollectionView: View {
    let id: String
    let title: String
    let coverUrl: String
    @State private var tracks: [MusicTrack] = []
    @State private var loading = true
    @StateObject private var audio = AudioPlaybackService.shared
    @StateObject private var downloads = DownloadService.shared

    var body: some View {
        Group {
            if loading {
                ProgressView("加载中…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tracks.isEmpty {
                ContentUnavailableView { Label("暂无歌曲", systemImage: "music.note") }
            } else {
                VStack {
                    HStack {
                        Button {
                            var queue = tracks
                            for i in queue.indices where queue[i].playUrl.isEmpty {
                                // 播放页会按需解析
                            }
                            audio.play(tracks: queue, at: 0)
                        } label: {
                            Label("播放全部", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).tint(AppTheme.accent())
                        Button("下载全部") {
                            Task {
                                for track in tracks {
                                    var t = track
                                    if t.playUrl.isEmpty { t.playUrl = await MusicRepository.shared.resolvePlayURL(t) }
                                    DownloadService.shared.download(t)
                                }
                            }
                        }.buttonStyle(.bordered)
                    }.padding()

                    List {
                        ForEach(Array(tracks.enumerated()), id: \.offset) { idx, track in
                            TrackRow(track: track) {
                                audio.play(tracks: tracks, at: idx)
                            } onFavorite: {
                                var list = StorageService.shared.musicFavorites
                                if let i = list.firstIndex(where: { $0.favoriteKey == track.favoriteKey }) {
                                    list.remove(at: i)
                                } else { list.insert(track, at: 0) }
                                StorageService.shared.musicFavorites = list
                            } onDownload: {
                                Task {
                                    var t = track
                                    if t.playUrl.isEmpty { t.playUrl = await MusicRepository.shared.resolvePlayURL(t) }
                                    DownloadService.shared.download(t)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            tracks = await MusicRepository.shared.detail(id: id)
            loading = false
        }
    }
}

/// 音乐设置页（对应 MusicSettingsPage）
struct MusicSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var quality = StorageService.shared.musicQuality
    @State private var playMode = StorageService.shared.musicPlayMode
    @State private var sources = StorageService.shared.musicSources
    @State private var preferredSource = StorageService.shared.preferredMusicSource
    @State private var showAddSource = false
    @State private var newSourceURL = ""

    var body: some View {
        NavigationStack {
            List {
                Section("音质") {
                    Picker("音质偏好", selection: $quality) {
                        ForEach(MusicQuality.allCases) { q in Text(q.label).tag(q) }
                    }.onChange(of: quality) { StorageService.shared.musicQuality = $0 }
                }

                Section("播放音源") {
                    Picker("选择模式", selection: $playMode) {
                        ForEach(MusicPlaySourceMode.allCases) { m in Text(m.label).tag(m) }
                    }
                    if sources.isEmpty {
                        Text("未配置自定义音源，使用内置网易云接口").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(sources) { src in
                            HStack {
                                Toggle(src.name.isEmpty ? src.id : src.name, isOn: Binding(
                                    get: { src.enabled },
                                    set: { v in updateSource(src) { $0.enabled = v } }
                                ))
                            }
                        }
                    }
                }

                Section {
                    Button("添加自定义音源") { showAddSource = true }
                } footer: {
                    Text("支持 JSON 配置，或 JS 脚本型音源。本软件不内置任何音乐接口。")
                }
            }
            .navigationTitle("音乐设置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
            .alert("添加音源", isPresented: $showAddSource) {
                TextField("配置地址 (URL)", text: $newSourceURL)
                Button("取消", role: .cancel) {}
                Button("添加") { addSource() }
            }
        }
    }

    private func updateSource(_ src: MusicSourceConfig, mutate: (inout MusicSourceConfig) -> Void) {
        var list = StorageService.shared.musicSources
        if let idx = list.firstIndex(where: { $0.id == src.id }) {
            var item = list[idx]; mutate(&item); list[idx] = item
            StorageService.shared.musicSources = list
            sources = list
        }
    }

    private func addSource() {
        guard !newSourceURL.isEmpty,
              let url = URL(string: newSourceURL) else { return }
        Task {
            if let text = try? String(contentsOf: url) {
                var src = MusicSourceConfig(id: newSourceURL, name: "自定义音源", baseUrl: newSourceURL)
                if text.trimmingCharacters(in: .whitespaces).hasPrefix("{"),
                   let data = text.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    src.name = obj["name"] as? String ?? src.name
                    src.baseUrl = obj["baseUrl"] as? String ?? newSourceURL
                    src.searchPath = obj["searchPath"] as? String ?? src.searchPath
                    src.rankPath = obj["rankPath"] as? String ?? src.rankPath
                    src.playlistPath = obj["playlistPath"] as? String ?? src.playlistPath
                    src.detailPath = obj["detailPath"] as? String ?? src.detailPath
                } else {
                    src.sourceType = "js"
                    src.scriptText = text
                }
                var list = StorageService.shared.musicSources
                list.append(src)
                StorageService.shared.musicSources = list
                sources = list
                MusicRepository.shared.invalidateDiscoverCache()
            }
            newSourceURL = ""
        }
    }
}
