import Foundation

/// 音乐数据仓库（对应安卓 music/MusicRepository + BuiltinDiscover）
/// 支持：内置网易云公开接口（排行榜/歌单/详情/解析）+ 用户自定义音源聚合
final class MusicRepository: ObservableObject {
    static let shared = MusicRepository()

    private let neteaseAPI = "https://music.163.com/api"
    private let builtinSourceId = "builtin:wy"

    // 简易内存缓存
    private var searchCache: [String: [MusicTrack]] = [:]
    private var discoverCache: MusicDiscover?

    // MARK: - 内置排行榜
    /// 对应 BuiltinDiscover 的官方榜单（前若干）
    func builtinRanks() -> [MusicRank] {
        [
            MusicRank(id: "wy:1",   name: "飙升榜",   coverUrl: "", sourceName: "网易云"),
            MusicRank(id: "wy:2",   name: "新歌榜",   coverUrl: "", sourceName: "网易云"),
            MusicRank(id: "wy:3",   name: "原创榜",   coverUrl: "", sourceName: "网易云"),
            MusicRank(id: "wy:4",   name: "热歌榜",   coverUrl: "", sourceName: "网易云"),
            MusicRank(id: "wy:5",   name: "会员榜",   coverUrl: "", sourceName: "网易云"),
            MusicRank(id: "wy:6",   name: "DJ榜",     coverUrl: "", sourceName: "网易云"),
            MusicRank(id: "wy:7",   name: "KKbox",    coverUrl: "", sourceName: "网易云"),
            MusicRank(id: "wy:8",   name: "美国榜",   coverUrl: "", sourceName: "网易云"),
            MusicRank(id: "wy:9",   name: "香港榜",   coverUrl: "", sourceName: "网易云"),
            MusicRank(id: "wy:10",  name: "台湾榜",   coverUrl: "", sourceName: "网易云"),
            MusicRank(id: "wy:11",  name: "日本榜",   coverUrl: "", sourceName: "网易云"),
            MusicRank(id: "wy:12",  name: "韩国榜",   coverUrl: "", sourceName: "网易云"),
            MusicRank(id: "wy:13",  name: "欧美榜",   coverUrl: "", sourceName: "网易云"),
            MusicRank(id: "wy:14",  name: "内地榜",   coverUrl: "", sourceName: "网易云"),
        ]
    }

    // MARK: - 发现页
    func discover() async -> MusicDiscover {
        if let cached = discoverCache { return cached }
        var ranks = builtinRanks()
        var playlists: [MusicPlaylist] = []

        // 推荐歌单（网易云公开接口）
        if let text = await NetworkService.getText("\(neteaseAPI)/personalized?limit=12") {
            playlists = parsePlaylists(text, source: MusicSourceConfig())
        }
        // 排行榜补充真实名字/封面
        if let text = await NetworkService.getText("\(neteaseAPI)/toplist/detail") {
            let real = parseRankDetail(text)
            if !real.isEmpty { ranks = real }
        }

        // 聚合用户音源的榜单与歌单
        for src in StorageService.shared.musicSources where src.enabled {
            let rankURL = buildURL(src, src.rankPath)
            let plURL = buildURL(src, src.playlistPath)
            if let t = await NetworkService.getText(rankURL) {
                ranks += parseRanks(t, source: src)
            }
            if let t = await NetworkService.getText(plURL) {
                playlists += parsePlaylists(t, source: src)
            }
        }

        let result = MusicDiscover(ranks: dedupRanks(ranks), playlists: playlists)
        discoverCache = result
        return result
    }

    func invalidateDiscoverCache() { discoverCache = nil; searchCache.removeAll() }

    // MARK: - 搜索
    func search(keyword: String, page: Int = 1) async -> [MusicTrack] {
        let cacheKey = "\(keyword)-\(page)"
        if let cached = searchCache[cacheKey] { return cached }

        var results: [MusicTrack] = []

        // 内置网易云搜索
        if let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let text = await NetworkService.getText("\(neteaseAPI)/search/get?s=\(encoded)&type=1&offset=\((page - 1) * 30)&limit=30") {
            results += parseSongs(from: text, source: MusicSourceConfig(), platform: "wy")
        }

        // 聚合用户音源
        for src in StorageService.shared.musicSources where src.enabled {
            let url = buildURL(src, src.searchPath, replacements: [
                "keyword": keyword, "page": String(page)
            ])
            if src.baseUrl.isEmpty { continue }
            if let text = await NetworkService.getText(url) {
                results += parseSongs(from: text, source: src)
            }
        }

        let unique = dedupTracks(results)
        searchCache[cacheKey] = unique
        return unique
    }

    // MARK: - 详情（榜单/歌单歌曲）
    func detail(id: String, sourceName: String = "") async -> [MusicTrack] {
        var songs: [MusicTrack] = []

        // 网易云榜单/歌单：id 形如 wy:123 / wy:playlist:123
        let numeric = id.replacingOccurrences(of: "wy:playlist:", with: "")
            .replacingOccurrences(of: "wy:", with: "")
        if id.hasPrefix("wy") {
            let endpoint = id.contains("playlist")
                ? "\(neteaseAPI)/playlist/detail?id=\(numeric)"
                : "\(neteaseAPI)/playlist/detail?id=\(numeric)"
            if let text = await NetworkService.getText(endpoint) {
                songs += parseSongs(from: text, source: MusicSourceConfig(), platform: "wy")
            }
        }

        // 用户音源详情
        for src in StorageService.shared.musicSources where src.enabled {
            let url = buildURL(src, src.detailPath, replacements: ["id": id])
            if let text = await NetworkService.getText(url) {
                songs += parseSongs(from: text, source: src)
            }
        }
        return dedupTracks(songs)
    }

    // MARK: - 播放地址解析
    /// 对应 MusicPlaybackResolver，返回可直接播放的 URL
    func resolvePlayURL(_ track: MusicTrack) async -> String {
        if !track.playUrl.isEmpty { return track.playUrl }

        // 网易云：通过外部公开解析接口换取真实播放地址
        if track.platformKey == "wy" || track.sourceId.contains("wy") || track.sourceId.contains("netease") {
            let songId = track.songIdNum.isEmpty ? numericID(from: track) : track.songIdNum
            if !songId.isEmpty {
                let candidates = [
                    "https://music.163.com/api/song/enhance/player/url?id=\(songId)&ids=[\(songId)]&br=320000",
                    "https://api.avbox.top/music/wy/url?id=\(songId)",
                ]
                for url in candidates {
                    if let text = await NetworkService.getText(url),
                       let found = extractPlayURL(from: text), !found.isEmpty {
                        return found
                    }
                }
            }
        }
        // QQ / 酷狗 / 酷我 通用兜底解析
        let mid = track.songMid.isEmpty ? track.id : track.songMid
        if !mid.isEmpty {
            let url = "https://api.avbox.top/music/url?platform=\(track.platformKey)&id=\(mid)"
            if let text = await NetworkService.getText(url),
               let found = extractPlayURL(from: text), !found.isEmpty {
                return found
            }
        }
        return ""
    }

    // MARK: - JSON 解析
    private func parseSongs(from text: String, source: MusicSourceConfig, platform: String? = nil) -> [MusicTrack] {
        guard let obj = JSONHelper.parse(text) else { return [] }
        let arrays = JSONHelper.findArrays(in: obj, keys: ["songs", "data", "list", "result", "tracks", "items", "songs"])
        var out: [MusicTrack] = []
        for arr in arrays {
            for item in arr {
                guard let d = item as? [String: Any] else { continue }
                out.append(trackFrom(d, source: source, platform: platform))
            }
        }
        return out.filter { !$0.title.isEmpty || !$0.id.isEmpty }
    }

    private func trackFrom(_ d: [String: Any], source: MusicSourceConfig, platform: String?) -> MusicTrack {
        let title = S(d, "title", "name", "songname", "songName")
        let artist = S(d, "artist", "singer", "artists", "author")
        let album = S(d, "album", "albumname")
        let cover = S(d, "coverUrl", "pic", "cover", "img", "album_pic", "artwork")
        let songMid = S(d, "songMid", "songmid", "mid")
        let songId = S(d, "songIdNum", "id", "songid", "songId")
        let play = S(d, "playUrl", "url", "link", "src")
        let duration = I(d, "durationMs", "duration", "interval")
        let plat = platform ?? S(d, "platformKey", "platform")

        return MusicTrack(
            id: songId.isEmpty ? songMid : songId,
            title: title,
            artist: artist,
            album: album,
            coverUrl: cover,
            sourceId: source.id.isEmpty ? builtinSourceId : source.id,
            durationMs: Int64(duration > 10_000 ? duration : duration * 1000),
            playUrl: play,
            platformKey: plat.isEmpty ? "wy" : plat,
            songMid: songMid,
            songIdNum: songId,
            intervalSec: duration > 10_000 ? Int(duration / 1000) : duration
        )
    }

    private func parsePlaylists(_ text: String, source: MusicSourceConfig) -> [MusicPlaylist] {
        guard let obj = JSONHelper.parse(text) else { return [] }
        let arrays = JSONHelper.findArrays(in: obj, keys: ["playlists", "data", "list", "result"])
        var out: [MusicPlaylist] = []
        for arr in arrays {
            for item in arr {
                guard let d = item as? [String: Any] else { continue }
                let name = S(d, "name", "title", "playlistName")
                guard !name.isEmpty else { continue }
                out.append(MusicPlaylist(
                    id: S(d, "id", "playlistId"),
                    name: name,
                    coverUrl: S(d, "coverUrl", "picUrl", "cover", "pic", "imgurl"),
                    sourceName: source.name.isEmpty ? "网易云" : source.name,
                    trackCount: I(d, "trackCount", "size", "count", "songCount")
                ))
            }
        }
        return out
    }

    private func parseRanks(_ text: String, source: MusicSourceConfig) -> [MusicRank] {
        guard let obj = JSONHelper.parse(text) else { return [] }
        let arrays = JSONHelper.findArrays(in: obj, keys: ["ranks", "data", "list", "toplist"])
        var out: [MusicRank] = []
        for arr in arrays {
            for item in arr {
                guard let d = item as? [String: Any] else { continue }
                let name = S(d, "name", "title")
                guard !name.isEmpty else { continue }
                out.append(MusicRank(
                    id: S(d, "id"), name: name,
                    coverUrl: S(d, "coverUrl", "cover", "pic"),
                    sourceName: source.name
                ))
            }
        }
        return out
    }

    private func parseRankDetail(_ text: String) -> [MusicRank] {
        guard let obj = JSONHelper.parse(text) else { return [] }
        let arrays = JSONHelper.findArrays(in: obj, keys: ["list", "data"])
        var out: [MusicRank] = []
        for arr in arrays {
            for item in arr {
                guard let d = item as? [String: Any] else { continue }
                let name = S(d, "name")
                guard !name.isEmpty else { continue }
                out.append(MusicRank(
                    id: "wy:\(I(d, "id"))", name: name,
                    coverUrl: S(d, "coverImgUrl"), sourceName: "网易云"
                ))
            }
        }
        return out
    }

    private func buildURL(_ src: MusicSourceConfig, _ path: String,
                          replacements: [String: String] = [:]) -> String {
        var p = path
        for (k, v) in replacements {
            p = p.replacingOccurrences(of: "{\(k)}", with: v)
        }
        return NetworkService.buildURL(base: src.baseUrl, path: p, query: [:])
    }

    private func extractPlayURL(from text: String) -> String? {
        guard let obj = JSONHelper.parse(text) else {
            // 纯文本 URL
            return text.hasPrefix("http") ? text.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        }
        let candidates = ["url", "playUrl", "songUrl", "mp3", "link", "src"]
        func search(_ v: Any, depth: Int) -> String? {
            if depth > 6 { return nil }
            if let d = v as? [String: Any] {
                for k in candidates {
                    if let s = d[k] as? String, s.hasPrefix("http") { return s }
                }
                for val in d.values {
                    if let found = search(val, depth: depth + 1) { return found }
                }
            } else if let arr = v as? [Any] {
                for val in arr {
                    if let found = search(val, depth: depth + 1) { return found }
                }
            }
            return nil
        }
        return search(obj, depth: 0)
    }

    private func numericID(from track: MusicTrack) -> String {
        let s = track.id.isEmpty ? track.songMid : track.id
        return s.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }.joined()
    }

    private func dedupTracks(_ list: [MusicTrack]) -> [MusicTrack] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.favoriteKey).inserted }
    }
    private func dedupRanks(_ list: [MusicRank]) -> [MusicRank] {
        var seen = Set<String>()
        return list.filter { seen.insert("\($0.sourceName)-\($0.name)").inserted }
    }

    // 字符串/整数安全取值
    private func S(_ d: [String: Any], _ keys: String...) -> String {
        for k in keys {
            if let s = d[k] as? String, !s.isEmpty { return s }
            if let n = d[k] as? NSNumber { return n.stringValue }
        }
        return ""
    }
    private func I(_ d: [String: Any], _ keys: String...) -> Int {
        for k in keys {
            if let n = d[k] as? Int { return n }
            if let n = d[k] as? NSNumber { return n.intValue }
            if let s = d[k] as? String, let i = Int(s) { return i }
        }
        return 0
    }
}

/// JSON 解析辅助
enum JSONHelper {
    static func parse(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func findArrays(in obj: [String: Any], keys: [String]) -> [[Any]] {
        var result: [[Any]] = []
        for key in keys {
            if let arr = obj[key] as? [Any], !arr.isEmpty { result.append(arr) }
        }
        if result.isEmpty {
            // 递归一层
            for value in obj.values {
                if let nested = value as? [String: Any] {
                    result += findArrays(in: nested, keys: keys)
                }
            }
        }
        // 若某数组元素是 {songs:[...]} 再拆一层
        var expanded: [[Any]] = []
        for arr in result {
            for item in arr {
                if let d = item as? [String: Any] {
                    for key in keys {
                        if let inner = d[key] as? [Any], !inner.isEmpty { expanded.append(inner) }
                    }
                }
            }
        }
        return expanded.isEmpty ? result : result + expanded
    }
}
