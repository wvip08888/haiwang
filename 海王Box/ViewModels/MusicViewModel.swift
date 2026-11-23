import Foundation
import Combine

/// 音乐页面 ViewModel（对应 MusicPage 的数据流）
@MainActor
final class MusicViewModel: ObservableObject {
    @Published var ranks: [MusicRank] = []
    @Published var playlists: [MusicPlaylist] = []
    @Published var searchResults: [MusicTrack] = []
    @Published var favorites: [MusicTrack] = []
    @Published var isLoading = false
    @Published var isSearching = false
    @Published var searchKeyword = ""
    @Published var errorMessage: String? = nil
    @Published var hasSources = false

    private let repo = MusicRepository.shared

    func load() async {
        isLoading = true
        let discover = await repo.discover()
        ranks = discover.ranks
        playlists = discover.playlists
        favorites = StorageService.shared.musicFavorites
        hasSources = !StorageService.shared.musicSources.isEmpty
        isLoading = false
    }

    func refresh() async {
        repo.invalidateDiscoverCache()
        await load()
    }

    func search(_ keyword: String) async {
        searchKeyword = keyword
        guard !keyword.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchResults = await repo.search(keyword: keyword)
        isSearching = false
    }

    func detail(id: String) async -> [MusicTrack] {
        await repo.detail(id: id)
    }

    func play(tracks: [MusicTrack], at index: Int, preferLocal: Bool = false) {
        resolveAndPlay(tracks: tracks, index: index, preferLocal: preferLocal)
    }

    private func resolveAndPlay(tracks: [MusicTrack], index: Int, preferLocal: Bool) {
        Task { @MainActor in
            var prepared = tracks
            if !prepared.indices.contains(index) { return }
            if prepared[index].playUrl.isEmpty && !preferLocal {
                isLoading = true
                let url = await repo.resolvePlayURL(prepared[index])
                prepared[index].playUrl = url
                isLoading = false
            }
            AudioPlaybackService.shared.play(tracks: prepared, at: index, preferLocal: preferLocal)
            recordRecent(prepared[index])
        }
    }

    /// 播放本地已下载歌曲
    func playDownloaded(_ item: DownloadItem, tracks: [MusicTrack]) {
        let track = MusicTrack(
            id: item.id, title: item.title, artist: item.artist,
            coverUrl: item.coverUrl, sourceUrl: item.sourceUrl
        )
        AudioPlaybackService.shared.play(tracks: tracks.isEmpty ? [track] : tracks, at: 0, preferLocal: true)
    }

    // MARK: - 收藏
    func toggleFavorite(_ track: MusicTrack) {
        var list = StorageService.shared.musicFavorites
        if let idx = list.firstIndex(where: { $0.favoriteKey == track.favoriteKey }) {
            list.remove(at: idx)
        } else {
            list.insert(track, at: 0)
        }
        // 去重
        var seen = Set<String>()
        list = list.filter { seen.insert($0.favoriteKey).inserted }
        StorageService.shared.musicFavorites = list
        favorites = list
    }

    func isFavorite(_ track: MusicTrack) -> Bool {
        favorites.contains { $0.favoriteKey == track.favoriteKey }
    }

    private func recordRecent(_ track: MusicTrack) {
        // 记录到 UserDefaults，用于“继续播放”卡片
        var recents = UserDefaults.standard.stringArray(forKey: "musicRecents") ?? []
        recents.removeAll { $0 == track.favoriteKey }
        recents.insert(track.favoriteKey, at: 0)
        UserDefaults.standard.set(Array(recents.prefix(20)), forKey: "musicRecents")
        // 保存曲目本体
        var saved = StorageService.shared.loadAny([MusicTrack].self, "musicRecentTracks", default: [])
        if !saved.contains(where: { $0.favoriteKey == track.favoriteKey }) {
            saved.insert(track, at: 0)
            StorageService.shared.saveAny(saved, "musicRecentTracks")
        }
    }

    func recentTracks() -> [MusicTrack] {
        StorageService.shared.loadAny([MusicTrack].self, "musicRecentTracks", default: [])
    }

    /// 按平台分组排行榜
    func groupedRanks() -> [(platform: String, color: String, ranks: [MusicRank])] {
        var groups: [String: [MusicRank]] = [:]
        for rank in ranks {
            let platform = normalizePlatform(rank.sourceName)
            groups[platform, default: []].append(rank)
        }
        return groups.map { (platform: $0.key, color: platformColor($0.key), ranks: $0.value) }
            .sorted { $0.platform < $1.platform }
    }

    private func normalizePlatform(_ name: String) -> String {
        if name.contains("网易") || name == "wy" { return "网易云音乐" }
        if name.contains("QQ") || name == "tx" { return "QQ音乐" }
        if name.contains("酷狗") || name == "kg" { return "酷狗音乐" }
        if name.contains("酷我") || name == "kw" { return "酷我音乐" }
        return name.isEmpty ? "其他" : name
    }
    private func platformColor(_ name: String) -> String {
        if name.contains("网易") { return "#E60026" }
        if name.contains("QQ") { return "#31C27C" }
        if name.contains("酷狗") { return "#1CADF5" }
        if name.contains("酷我") { return "#FF6900" }
        return "#8E8E93"
    }
}
