import Foundation
import Combine

/// 记录页（历史 + 收藏）ViewModel
@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var history: [VodInfo] = []
    @Published var collect: [VodInfo] = []
    @Published var incognito = false

    private let store = StorageService.shared

    func load() {
        incognito = store.flag("incognito")
        history = incognito ? [] : store.history
        collect = store.collect
    }

    func addHistory(_ info: VodInfo) {
        guard !incognito else { return }
        var list = store.history
        list.removeAll { $0.id == info.id && $0.sourceKey == info.sourceKey }
        var newInfo = info
        newInfo.updateTime = Date().timeIntervalSince1970 * 1000
        list.insert(newInfo, at: 0)
        let limit = UserDefaults.standard.integer(forKey: "historyLimit")
        if limit > 0 && list.count > limit { list = Array(list.prefix(limit)) }
        store.history = list
        history = list
    }

    func toggleCollect(_ info: VodInfo) {
        var list = store.collect
        if let idx = list.firstIndex(where: { $0.id == info.id && $0.sourceKey == info.sourceKey }) {
            list.remove(at: idx)
        } else {
            list.insert(info, at: 0)
        }
        store.collect = list
        collect = list
    }

    func isCollected(_ info: VodInfo) -> Bool {
        collect.contains { $0.id == info.id && $0.sourceKey == info.sourceKey }
    }

    func removeHistory(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        store.history = history
    }
    func removeCollect(at offsets: IndexSet) {
        collect.remove(atOffsets: offsets)
        store.collect = collect
    }
    func clearHistory() { history = []; store.history = [] }
    func clearCollect() { collect = []; store.collect = [] }
}

/// 追剧页 ViewModel
@MainActor
final class FollowingViewModel: ObservableObject {
    @Published var items: [VodInfo] = []
    @Published var selectedDay: Int = -1  // -1 = 本周
    private let store = StorageService.shared

    let weekdays = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    func load() { items = store.following }

    func toggleFollow(_ info: VodInfo) {
        var list = store.following
        if let idx = list.firstIndex(where: { $0.id == info.id && $0.sourceKey == info.sourceKey }) {
            list.remove(at: idx)
        } else {
            list.insert(info, at: 0)
        }
        store.following = list
        items = list
    }

    func isFollowing(_ info: VodInfo) -> Bool {
        items.contains { $0.id == info.id && $0.sourceKey == info.sourceKey }
    }

    func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        store.following = items
    }
}

/// 设置页 ViewModel
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var tmdb = StorageService.shared.tmdbConfig
    @Published var historyLimit: Int = UserDefaults.standard.integer(forKey: "historyLimit") {
        didSet { UserDefaults.standard.set(historyLimit, forKey: "historyLimit") }
    }
    @Published var cacheSizeText = "计算中…"

    private let store = StorageService.shared

    func flagBinding(_ name: String) -> Bool { store.flag(name) }
    func setFlag(_ name: String, _ value: Bool) { store.setFlag(name, value) }

    func saveTmdb() { store.tmdbConfig = tmdb }

    func clearCache() {
        let fm = FileManager.default
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
        if let path = caches?.path, let contents = try? fm.contentsOfDirectory(atPath: path) {
            for item in contents {
                try? fm.removeItem(atPath: (path as NSString).appendingPathComponent(item))
            }
        }
        cacheSizeText = "0 MB"
    }

    func calcCacheSize() {
        let fm = FileManager.default
        guard let path = fm.urls(for: .cachesDirectory, in: .userDomainMask).first?.path,
              let contents = try? fm.contentsOfDirectory(atPath: path) else { cacheSizeText = "0 MB"; return }
        var total: Int64 = 0
        for item in contents {
            if let attrs = try? fm.attributesOfItem(atPath: (path as NSString).appendingPathComponent(item)),
               let size = attrs[.size] as? Int64 { total += size }
        }
        cacheSizeText = total > 1024 * 1024
            ? String(format: "%.1f MB", Double(total) / 1024 / 1024)
            : "\(total / 1024) KB"
    }
}
