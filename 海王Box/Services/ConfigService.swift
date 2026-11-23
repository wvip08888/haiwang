import Foundation

/// 配置加载与源管理（对应安卓 api/ConfigLoader + ConfigRepository）
final class ConfigService: ObservableObject {
    static let shared = ConfigService()

    @Published var sources: [SourceBean] = []
    @Published var depots: [SourceDepot] = []
    @Published var parseSources: [ParseBean] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    private init() {
        sources = StorageService.shared.sources
        parseSources = StorageService.shared.parseSources
        if sources.isEmpty { loadBuiltinConfig() }
    }

    /// 应用内置默认配置（仅广告过滤规则，不内置任何影视源）
    func loadBuiltinConfig() {
        guard let url = Bundle.main.url(forResource: "default_config", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }
        // 默认配置只含 ads 过滤列表，源由用户自行导入，保持与安卓版一致
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            UserDefaults.standard.set(json["ads"] as? [String] ?? [], forKey: "adHosts")
        }
    }

    /// 从订阅地址拉取配置（支持 JSON 点播源 / m3u / txt 直播源）
    func fetchConfig(from urlString: String) async -> Result<Int, String> {
        guard let text = await NetworkService.getText(urlString) else {
            return .failure("拉取配置失败\n\(urlString)")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return parseJSONConfig(trimmed)
        } else if trimmed.hasPrefix("#EXTM3U") || trimmed.contains("#EXTINF") {
            StorageService.shared.liveUrl = urlString
            return .success(0)
        }
        return .failure("配置格式无法识别")
    }

    /// 解析点播源 JSON（兼容数组与 {urls:[...]} 包装）
    func parseJSONConfig(_ text: String) -> Result<Int, String> {
        guard let data = text.data(using: .utf8) else { return .failure("配置解析失败") }
        var roots: [[String: Any]] = []

        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            roots = arr
        } else if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let urls = obj["urls"] as? [[String: Any]] {
                roots = urls
            } else if let site = obj["api"] as? String {
                roots = [obj]
                _ = site
            }
        }
        guard !roots.isEmpty else {
            // 可能是一次解析跳转 / 聚合订阅，尝试抽取 urls 数组
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let urls = obj["urls"] as? [Any] {
                var list: [SourceBean] = []
                for u in urls {
                    if let s = u as? String { list.append(SourceBean(api: s, name: s)) }
                    else if let d = u as? [String: Any] {
                        list.append(SourceBean(
                            key: d["key"] as? String ?? "",
                            name: d["name"] as? String ?? "",
                            api: d["api"] as? String ?? d["url"] as? String ?? "",
                            searchable: d["searchable"] as? Int ?? 0,
                            type: d["type"] as? Int ?? 0
                        ))
                    }
                }
                if !list.isEmpty {
                    mergeSources(list)
                    return .success(list.count)
                }
            }
            return .failure("配置解析失败")
        }

        var list: [SourceBean] = []
        for d in roots {
            let api = d["api"] as? String ?? d["url"] as? String ?? ""
            if api.isEmpty { continue }
            list.append(SourceBean(
                key: d["key"] as? String ?? "",
                name: d["name"] as? String ?? api,
                api: api,
                type: d["type"] as? Int ?? 0,
                searchable: d["searchable"] as? Int ?? 0,
                quickSearch: d["quickSearch"] as? Int ?? 0,
                changeable: d["changeable"] as? Int ?? 1,
                filterable: d["filterable"] as? Int ?? 0,
                playerUrl: d["playerUrl"] as? String ?? "",
                ext: d["ext"] as? String ?? "",
                jar: d["jar"] as? String ?? "",
                categories: d["categories"] as? [String] ?? [],
                header: d["header"] as? [String: String] ?? [:]
            ))
        }
        guard !list.isEmpty else { return .failure("配置解析失败") }
        mergeSources(list)
        return .success(list.count)
    }

    private func mergeSources(_ list: [SourceBean]) {
        var current = sources
        for s in list where !current.contains(where: { $0.api == s.api }) {
            current.append(s)
        }
        sources = current
        StorageService.shared.sources = current
        if StorageService.shared.activeSourceKey.isEmpty, let first = current.first {
            StorageService.shared.activeSourceKey = first.key.isEmpty ? first.api : first.key
        }
    }

    func removeSource(_ source: SourceBean) {
        sources.removeAll { $0.id == source.id }
        StorageService.shared.sources = sources
    }

    func activeSource() -> SourceBean? {
        let key = StorageService.shared.activeSourceKey
        return sources.first { ($0.key.isEmpty ? $0.api : $0.key) == key } ?? sources.first
    }
}

// 便于从字典构造
extension SourceBean {
    init(key: String, name: String, api: String, searchable: Int = 0, type: Int = 0) {
        self.init(key: key, name: name, api: api, searchable: searchable, type: type)
    }
}
