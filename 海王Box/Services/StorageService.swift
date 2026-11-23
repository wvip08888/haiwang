import Foundation

/// 本地存储（对应安卓的 SharedPreferences / MMKV / Room）
final class StorageService {
    static let shared = StorageService()
    private let defaults = UserDefaults.standard

    private enum Key: String {
        case sources, activeSource, parseSources, activeParse
        case musicSources, musicQuality, musicPlayMode, musicPreferredSource
        case favorites, musicFavorites, history, collect, following
        case tmdbConfig, settings, searchHistory, downloadItems
        case epgCache, liveUrl
    }

    // MARK: - 通用 Codable 读写
    func load<T: Codable>(_ type: T.Type, _ key: Key, default fallback: T) -> T {
        guard let data = defaults.data(forKey: key.rawValue) else { return fallback }
        return (try? JSONDecoder().decode(type, from: data)) ?? fallback
    }

    func save<T: Codable>(_ value: T, _ key: Key) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key.rawValue)
        }
    }

    // MARK: - 点播源
    var sources: [SourceBean] {
        get { load([SourceBean].self, .sources, default: []) }
        set { save(newValue, .sources) }
    }
    var activeSourceKey: String {
        get { defaults.string(forKey: Key.activeSource.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.activeSource.rawValue) }
    }
    var parseSources: [ParseBean] {
        get { load([ParseBean].self, .parseSources, default: []) }
        set { save(newValue, .parseSources) }
    }
    var activeParseName: String {
        get { defaults.string(forKey: Key.activeParse.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.activeParse.rawValue) }
    }

    // MARK: - 音乐
    var musicSources: [MusicSourceConfig] {
        get { load([MusicSourceConfig].self, .musicSources, default: []) }
        set { save(newValue, .musicSources) }
    }
    var musicQuality: MusicQuality {
        get { MusicQuality(rawValue: defaults.string(forKey: Key.musicQuality.rawValue) ?? "") ?? .losslessFirst }
        set { defaults.set(newValue.rawValue, forKey: Key.musicQuality.rawValue) }
    }
    var musicPlayMode: MusicPlayMode {
        get { MusicPlayMode(rawValue: defaults.string(forKey: Key.musicPlayMode.rawValue) ?? "") ?? .order }
        set { defaults.set(newValue.rawValue, forKey: Key.musicPlayMode.rawValue) }
    }
    var preferredMusicSource: String {
        get { defaults.string(forKey: Key.musicPreferredSource.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.musicPreferredSource.rawValue) }
    }
    var musicFavorites: [MusicTrack] {
        get { load([MusicTrack].self, .musicFavorites, default: []) }
        set { save(Array(Set(newValue)), .musicFavorites) }
    }

    // MARK: - 历史 / 收藏 / 追剧
    var history: [VodInfo] {
        get { load([VodInfo].self, .history, default: []) }
        set { save(newValue, .history) }
    }
    var collect: [VodInfo] {
        get { load([VodInfo].self, .collect, default: []) }
        set { save(newValue, .collect) }
    }
    var following: [VodInfo] {
        get { load([VodInfo].self, .following, default: []) }
        set { save(newValue, .following) }
    }
    var searchHistory: [String] {
        get { defaults.stringArray(forKey: Key.searchHistory.rawValue) ?? [] }
        set { defaults.set(newValue, forKey: Key.searchHistory.rawValue) }
    }

    // MARK: - TMDB
    var tmdbConfig: TmdbConfig {
        get { load(TmdbConfig.self, .tmdbConfig, default: TmdbConfig()) }
        set { save(newValue, .tmdbConfig) }
    }

    // MARK: - 设置开关
    var settings: [String: Bool] {
        get { defaults.object(forKey: Key.settings.rawValue) as? [String: Bool] ?? [:] }
        set { defaults.set(newValue, forKey: Key.settings.rawValue) }
    }
    func flag(_ name: String, default defaultValue: Bool = false) -> Bool {
        settings[name] ?? defaultValue
    }
    func setFlag(_ name: String, _ value: Bool) {
        var s = settings; s[name] = value; settings = s
    }

    // MARK: - 直播
    var liveUrl: String {
        get { defaults.string(forKey: Key.liveUrl.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.liveUrl.rawValue) }
    }

    // MARK: - 下载记录（新增）
    var downloadItems: [DownloadItem] {
        get { load([DownloadItem].self, .downloadItems, default: []) }
        set { save(newValue, .downloadItems) }
    }

    // MARK: - 通用字符串 Key 读写（供 ViewModel 使用）
    func loadAny<T: Codable>(_ type: T.Type, _ key: String, default fallback: T) -> T {
        guard let data = defaults.data(forKey: key) else { return fallback }
        return (try? JSONDecoder().decode(type, from: data)) ?? fallback
    }
    func saveAny<T: Codable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
