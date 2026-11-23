import Foundation

// MARK: - 影片列表（对应 Movie.Video / VodInfo）
/// 点播影片卡片，字段与安卓 CMS JSON/XML 保持一致
struct MovieVideo: Codable, Identifiable, Hashable {
    var id: String = ""
    var tid: Int = 0
    var name: String = ""
    var type: String = ""
    var en: String = ""
    var pic: String = ""
    var lang: String = ""
    var area: String = ""
    var year: Int = 0
    var state: String = ""
    var note: String = ""
    var actor: String = ""
    var director: String = ""
    var des: String = ""
    var tag: String = ""
    var last: String = ""
    var sourceKey: String = ""

    /// 播放线路（对应 dl.dd）
    var playFlags: [PlayFlag] = []

    enum CodingKeys: String, CodingKey {
        case id, tid, name, type, en, pic, lang, area, year
        case state, note, actor, director, des, tag, last, sourceKey
        case playFlags = "dl"
    }

    struct PlayFlag: Codable, Hashable {
        var flag: String = ""
        var urls: String = ""
        var episodes: [Episode] = []

        enum CodingKeys: String, CodingKey {
            case flag, urls
            case episodes = "beanList"
        }
    }

    struct Episode: Codable, Hashable {
        var name: String = ""
        var url: String = ""
    }
}

/// 视频详情（对应 VodInfo）
struct VodInfo: Codable, Identifiable, Hashable {
    var id: String = ""
    var name: String = ""
    var type: String = ""
    var en: String = ""
    var pic: String = ""
    var lang: String = ""
    var area: String = ""
    var year: Int = 0
    var state: String = ""
    var note: String = ""
    var actor: String = ""
    var director: String = ""
    var des: String = ""
    var sourceKey: String = ""
    var sourceName: String = ""
    var tid: Int = 0
    var last: String = ""
    var playIndex: Int = 0
    var playNote: String = ""
    var seriesFlags: [String] = []
    var seriesMap: [String: [MovieVideo.Episode]] = [:]
    var updateTime: Double = 0

    var subtitle: String {
        [year > 0 ? String(year) : "", area, type]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// 分类/筛选（对应 MovieSort.SortData）
struct SortData: Identifiable, Hashable {
    var id: String = ""
    var name: String = ""
    var sort: Int = -1
    var filters: [SortFilter] = []
    var selectedFilters: [String: String] = [:]
}

struct SortFilter: Identifiable, Hashable {
    var id: String { key }
    var key: String = ""
    var name: String = ""
    var values: [String: String] = [:]
}

// MARK: - 配置源（对应 SourceBean / SourceDepot）
struct SourceBean: Codable, Identifiable, Hashable {
    var key: String = ""
    var name: String = ""
    var api: String = ""
    var type: Int = 0
    var searchable: Int = 0
    var quickSearch: Int = 0
    var changeable: Int = 1
    var filterable: Int = 0
    var playerUrl: String = ""
    var ext: String = ""
    var jar: String = ""
    var categories: [String] = []
    var playerType: Int = 0
    var timeout: Int = 0
    var header: [String: String] = [:]
    var hide: Int = 0
    var id: String { key.isEmpty ? api : key }

    var isSearchable: Bool { searchable != 0 }
    var isIndexSource: Bool { type == 3 }
    var playTimeoutSeconds: Int { timeout > 0 ? max(5, min(60, timeout)) : 15 }
}

struct SourceDepot: Codable, Identifiable, Hashable {
    var url: String = ""
    var name: String = ""
    var id: String { url }
    var displayName: String { name.isEmpty ? url : name }
}

struct ParseBean: Codable, Identifiable, Hashable {
    var name: String = ""
    var url: String = ""
    var ext: String = ""
    var type: Int = 0
    var isDefault: Bool = false
    var id: String { name.isEmpty ? url : name }
}

// MARK: - 直播（对应 LiveChannelItem / LiveChannelGroup）
struct LiveChannel: Identifiable, Hashable {
    var name: String = ""
    var logo: String = ""
    var epg: String = ""
    var urls: [String] = []
    var ua: String = ""
    var referer: String = ""
    var tvgId: String = ""
    var catchup: [String: String] = [:]
    var id: String { tvgId.isEmpty ? name : tvgId }
}

struct LiveChannelGroup: Identifiable, Hashable {
    var name: String = ""
    var password: String = ""
    var channels: [LiveChannel] = []
    var id: String { name }
}

struct EpgProgram: Identifiable, Hashable {
    var title: String = ""
    var start: String = ""
    var end: String = ""
    var id: String { "\(title)-\(start)" }
}
