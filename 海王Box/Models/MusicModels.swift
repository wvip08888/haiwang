import Foundation

// MARK: - 音乐数据模型（与安卓 music/MusicModels.kt 一一对应）

let MUSIC_DEFAULT_SEARCH_PATH = "/search?keyword={keyword}&page={page}"
let MUSIC_DEFAULT_PLAYLIST_PATH = "/playlists"
let MUSIC_DEFAULT_RANK_PATH = "/ranks"
let MUSIC_DEFAULT_DETAIL_PATH = "/detail/{id}"

/// 一首可播放的歌曲
struct MusicTrack: Codable, Identifiable, Hashable {
    var id: String = ""
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var coverUrl: String = ""
    var sourceId: String = ""
    var durationMs: Int64 = 0
    var playUrl: String = ""
    var platformKey: String = ""   // tx / wy / kw / mg
    var songMid: String = ""
    var strMediaMid: String = ""
    var songIdNum: String = ""
    var albumMid: String = ""
    var intervalSec: Int = 0
    var sourceUrl: String = ""   // 原始音源地址（用于下载后回查）

    var subtitle: String {
        [artist, album].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// 收藏去重键
    var favoriteKey: String {
        let songId = songMid.isEmpty ? id : songMid
        return sourceId.trimmingCharacters(in: .whitespaces) + "|" + songId
    }

    enum CodingKeys: String, CodingKey {
        case id, title, artist, album, coverUrl, sourceId, durationMs, playUrl
        case platformKey, songMid, strMediaMid, songIdNum, albumMid, intervalSec, sourceUrl
    }
}

/// 歌单
struct MusicPlaylist: Codable, Identifiable, Hashable {
    var id: String = ""
    var name: String = ""
    var coverUrl: String = ""
    var sourceName: String = ""
    var trackCount: Int = 0
}

/// 排行榜
struct MusicRank: Codable, Identifiable, Hashable {
    var id: String = ""
    var name: String = ""
    var coverUrl: String = ""
    var sourceName: String = ""
}

/// 音源平台接口
struct MusicInterface: Codable, Hashable {
    var id: String = ""
    var name: String = ""
    var enabled: Bool = true
    var baseUrl: String = ""
    var displayName: String { name.isEmpty ? id : name }
}

/// 音源配置
struct MusicSourceConfig: Codable, Identifiable, Hashable {
    var id: String = ""
    var name: String = ""
    var version: String = ""
    var platforms: [String] = []
    var baseUrl: String = ""
    var searchPath: String = MUSIC_DEFAULT_SEARCH_PATH
    var playlistPath: String = MUSIC_DEFAULT_PLAYLIST_PATH
    var rankPath: String = MUSIC_DEFAULT_RANK_PATH
    var detailPath: String = MUSIC_DEFAULT_DETAIL_PATH
    var enabled: Bool = true
    var builtin: Bool = false
    var interfaces: [MusicInterface] = []
    var sourceType: String = "json"
    var scriptText: String = ""

    var enabledInterfaces: [MusicInterface] { interfaces.filter { $0.enabled } }

    var summary: String {
        var parts: [String] = []
        if !version.isEmpty { parts.append("v\(version)") }
        let names = interfaces.isEmpty ? platforms : interfaces.map { $0.displayName }
        let shown = names.filter { !$0.isEmpty }
        if !shown.isEmpty { parts.append(shown.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

/// 音质偏好
enum MusicQuality: String, CaseIterable, Identifiable {
    case losslessFirst = "lossless_first"
    case losslessOnly = "lossless_only"
    case high320 = "320"
    case standard128 = "128"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .losslessFirst: return "无损优先"
        case .losslessOnly: return "仅无损"
        case .high320: return "高（320 kbps）"
        case .standard128: return "标准（128 kbps）"
        }
    }
}

/// 播放音源选择模式
enum MusicPlaySourceMode: String, CaseIterable, Identifiable {
    case auto = "auto"
    case preferred = "preferred"
    var id: String { rawValue }
    var label: String { self == .auto ? "自动" : "优先指定" }
}

/// 播放模式
enum MusicPlayMode: String, CaseIterable, Identifiable {
    case single = "SINGLE"
    case list = "LIST"
    case order = "ORDER"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .single: return "单曲循环"
        case .list: return "列表循环"
        case .order: return "顺序播放"
        }
    }
    func toggled() -> MusicPlayMode {
        switch self {
        case .single: return .list
        case .list: return .order
        case .order: return .single
        }
    }
}

/// 音乐发现首页聚合结果
struct MusicDiscover {
    var ranks: [MusicRank] = []
    var playlists: [MusicPlaylist] = []
}

/// 歌词行
struct LyricLine: Identifiable, Hashable {
    var timeMs: Int64 = 0
    var text: String = ""
    var id: String { "\(timeMs)-\(text)" }
}

// MARK: - 下载模型（iOS 版新增功能）

/// 下载任务状态
enum DownloadStatus: String, Codable {
    case waiting = "waiting"
    case downloading = "downloading"
    case completed = "completed"
    case failed = "failed"
    case paused = "paused"
}

/// 一首歌的下载记录
struct DownloadItem: Codable, Identifiable, Hashable {
    var id: String = ""              // 使用 track.favoriteKey
    var title: String = ""
    var artist: String = ""
    var coverUrl: String = ""
    var sourceUrl: String = ""
    var fileName: String = ""        // 本地保存文件名
    var progress: Double = 0
    var status: DownloadStatus = .waiting
    var createdAt: TimeInterval = Date().timeIntervalSince1970
    var errorText: String = ""

    var localURL: URL? {
        guard !fileName.isEmpty else { return nil }
        return DownloadService.downloadsDirectory.appendingPathComponent(fileName)
    }
}
