import Foundation
import Combine

/// 首页点播 ViewModel（对应 HomeViewModel）
@MainActor
final class HomeViewModel: ObservableObject {
    @Published var videos: [MovieVideo] = []
    @Published var categories: [SortData] = []
    @Published var selectedCategory: SortData? = nil
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    @Published var page = 1
    @Published var hasMore = true

    private var currentSource: SourceBean? { ConfigService.shared.activeSource() }

    /// 加载首页分类与推荐
    func loadHome() async {
        guard let source = currentSource, !source.api.isEmpty else {
            errorMessage = "尚未配置订阅接口"
            return
        }
        isLoading = true
        errorMessage = nil
        page = 1

        // JS 爬虫源（type=3 或 jar 指向脚本）
        if source.type == 3 || !source.jar.isEmpty {
            await SpiderService.shared.prepare(source: source)
            let result = await SpiderService.shared.home(source: source)
            categories = result.categories
            videos = result.videos
            hasMore = !result.videos.isEmpty
            isLoading = false
            return
        }

        let base = source.api
        async let catText = NetworkService.getText(NetworkService.buildURL(base: base, path: "", query: ["ac": "class"]))
        async let listText = NetworkService.getText(base)

        let (cText, lText) = await (catText, listText)

        if let cText = cText { categories = parseCategories(cText) }
        if let lText = lText {
            let result = VodParser.parseList(lText, sourceKey: source.key)
            videos = result.videos
            hasMore = !result.videos.isEmpty
        } else {
            errorMessage = "首页加载超时，请检查网络后重试"
        }
        isLoading = false
    }

    /// 按分类/筛选加载
    func loadCategory(_ sort: SortData, filters: [String: String] = [:], page: Int = 1) async {
        guard let source = currentSource else { return }
        selectedCategory = sort
        isLoading = true
        var query: [String: String] = ["ac": "videolist", "t": sort.id, "pg": String(page)]
        for (k, v) in filters where !v.isEmpty { query[k] = v }
        let url = NetworkService.buildURL(base: source.api, path: "", query: query)
        if let text = await NetworkService.getText(url) {
            let result = VodParser.parseList(text, sourceKey: source.key)
            if page == 1 { videos = result.videos } else { videos += result.videos }
            hasMore = !result.videos.isEmpty
            self.page = page
        }
        isLoading = false
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        let next = page + 1
        if let sort = selectedCategory {
            await loadCategory(sort, filters: sort.selectedFilters, page: next)
        } else {
            guard let source = currentSource else { return }
            let url = NetworkService.buildURL(base: source.api, path: "", query: ["pg": String(next)])
            if let text = await NetworkService.getText(url) {
                let result = VodParser.parseList(text, sourceKey: source.key)
                videos += result.videos
                hasMore = !result.videos.isEmpty
                page = next
            }
        }
    }

    /// 搜索（跨站点聚合，支持 JS 爬虫源）
    func search(keyword: String, sources: [SourceBean]) async -> [MovieVideo] {
        var all: [MovieVideo] = []
        // 先为所有 JS 源准备脚本
        for src in sources where src.type == 3 || !src.jar.isEmpty {
            await SpiderService.shared.prepare(source: src)
        }
        await withTaskGroup(of: [MovieVideo].self) { group in
            for src in sources where src.isSearchable {
                group.addTask {
                    if src.type == 3 || !src.jar.isEmpty {
                        return await SpiderService.shared.search(source: src, keyword: keyword, page: 1)
                    }
                    let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
                    let url = NetworkService.buildURL(base: src.api, path: "", query: ["ac": "search", "wd": encoded])
                    guard let text = await NetworkService.getText(url) else { return [] }
                    return VodParser.parseList(text, sourceKey: src.key).videos
                }
            }
            for await result in group { all += result }
        }
        return all
    }

    /// 影片详情（支持 JS 爬虫源）
    func detail(id: String, source: SourceBean) async -> VodInfo? {
        if source.type == 3 || !source.jar.isEmpty {
            await SpiderService.shared.prepare(source: source)
            return await SpiderService.shared.detail(source: source, id: id)
        }
        let url = NetworkService.buildURL(base: source.api, path: "", query: ["ac": "detail", "ids": id])
        guard let text = await NetworkService.getText(url) else { return nil }
        return VodParser.parseDetail(text, sourceKey: source.key, sourceName: source.name)
    }

    private func parseCategories(_ text: String) -> [SortData] {
        VodParser.parseCategories(text)
    }
}

/// 影片数据解析（对应 AbsJson / AbsXml / Movie 解析层）
enum VodParser {

    static func parseList(_ text: String, sourceKey: String) -> (videos: [MovieVideo], categories: [SortData]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var videos: [MovieVideo] = []
        var cats: [SortData] = []

        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            guard let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) else { return ([], []) }
            if let dict = obj as? [String: Any] {
                cats = parseCategoriesFrom(dict)
                if let list = dict["list"] as? [[String: Any]] {
                    videos = list.compactMap { videoFrom($0, key: sourceKey) }
                } else if let list = dict["data"] as? [[String: Any]] {
                    videos = list.compactMap { videoFrom($0, key: sourceKey) }
                }
            } else if let arr = obj as? [[String: Any]] {
                videos = arr.compactMap { videoFrom($0, key: sourceKey) }
            }
        } else if trimmed.hasPrefix("<") {
            videos = parseXMLVideos(trimmed, key: sourceKey)
        }
        return (videos, cats)
    }

    static func parseCategories(_ text: String) -> [SortData] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return parseCategoriesFrom(obj)
        }
        return []
    }

    static func parseDetail(_ text: String, sourceKey: String, sourceName: String) -> VodInfo? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var dict: [String: Any]?
        if trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let list = obj["list"] as? [[String: Any]], let first = list.first {
                dict = first
            } else {
                dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
        }
        guard let d = dict else { return nil }
        var info = VodInfo(
            id: str(d, "id"), name: str(d, "name", "title"),
            type: str(d, "type"), en: str(d, "en"), pic: str(d, "pic"),
            lang: str(d, "lang"), area: str(d, "area"),
            year: int(d, "year"), state: str(d, "state"), note: str(d, "note"),
            actor: str(d, "actor"), director: str(d, "director"), des: str(d, "des"),
            sourceKey: sourceKey, sourceName: sourceName, tid: int(d, "tid"),
            last: str(d, "last")
        )
        // 解析播放线路 dl
        if let dl = d["dl"] as? [String: Any],
           let dd = dl["dd"] as? [[String: Any]] {
            for group in dd {
                let flag = str(group, "flag")
                var episodes: [MovieVideo.Episode] = []
                if let beans = group["beanList"] as? [[String: Any]] {
                    for b in beans {
                        episodes.append(MovieVideo.Episode(name: str(b, "name"), url: str(b, "url")))
                    }
                }
                if episodes.isEmpty, let urls = group["urls"] as? String {
                    episodes = urls.split(separator: "#").enumerated().map { idx, line in
                        let parts = line.split(separator: "$", maxSplits: 1)
                        return MovieVideo.Episode(
                            name: parts.count > 1 ? String(parts[0]) : "第\(idx + 1)集",
                            url: parts.count > 1 ? String(parts[1]) : String(line)
                        )
                    }
                }
                if !episodes.isEmpty {
                    info.seriesFlags.append(flag)
                    info.seriesMap[flag] = episodes
                }
            }
        }
        return info
    }

    // MARK: - 内部
    private static func videoFrom(_ d: [String: Any], key: String) -> MovieVideo? {
        var v = MovieVideo(
            id: str(d, "id"), tid: int(d, "tid"), name: str(d, "name", "title"),
            type: str(d, "type"), en: str(d, "en"), pic: str(d, "pic"),
            lang: str(d, "lang"), area: str(d, "area"), year: int(d, "year"),
            state: str(d, "state"), note: str(d, "note"), actor: str(d, "actor"),
            director: str(d, "director"), des: str(d, "des"), tag: str(d, "tag"),
            last: str(d, "last"), sourceKey: key
        )
        if let dl = d["dl"] as? [String: Any], let dd = dl["dd"] as? [[String: Any]] {
            for group in dd {
                var flag = MovieVideo.PlayFlag(flag: str(group, "flag"), urls: str(group, "urls"))
                if let beans = group["beanList"] as? [[String: Any]] {
                    flag.episodes = beans.map { MovieVideo.Episode(name: str($0, "name"), url: str($0, "url")) }
                }
                v.playFlags.append(flag)
            }
        }
        return v.id.isEmpty && v.name.isEmpty ? nil : v
    }

    private static func parseCategoriesFrom(_ dict: [String: Any]) -> [SortData] {
        guard let arr = dict["class"] as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            let id = str(d, "id")
            let name = str(d, "name", "title")
            guard !id.isEmpty, !name.isEmpty else { return nil }
            var sort = SortData(id: id, name: name, sort: int(d, "sort"))
            if let filters = parseFilters(dict, categoryId: id) { sort.filters = filters }
            return sort
        }
    }

    private static func parseFilters(_ dict: [String: Any], categoryId: String) -> [SortFilter]? {
        guard let filters = dict["filters"] as? [String: Any],
              let keysArr = filters[categoryId] as? [[String: Any]] else { return nil }
        return keysArr.compactMap { d in
            let key = str(d, "key")
            guard !key.isEmpty else { return nil }
            var values: [String: String] = [:]
            if let v = d["values"] as? [[String: Any]] {
                for item in v { values[str(item, "n")] = str(item, "v") }
            } else if let v = d["values"] as? [String: String] {
                values = v
            }
            return SortFilter(key: key, name: str(d, "name", "key"), values: values)
        }
    }

    private static func parseXMLVideos(_ text: String, key: String) -> [MovieVideo] {
        // 简易 XML 解析（对应 AbsXml）
        var videos: [MovieVideo] = []
        let pattern = "<video>(.*?)</video>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            let block = ns.substring(with: m.range(at: 1))
            var v = MovieVideo(sourceKey: key)
            func tag(_ name: String) -> String {
                guard let r = try? NSRegularExpression(pattern: "<\(name)>(.*?)</\(name)>", options: .dotMatchesLineSeparators),
                      let mm = r.firstMatch(in: block, range: NSRange(location: 0, length: (block as NSString).length)) else { return "" }
                return (block as NSString).substring(with: mm.range(at: 1))
            }
            v.id = tag("id"); v.name = tag("name"); v.pic = tag("pic")
            v.type = tag("type"); v.year = Int(tag("year")) ?? 0
            v.actor = tag("actor"); v.director = tag("director"); v.des = tag("des")
            if !v.name.isEmpty { videos.append(v) }
        }
        return videos
    }

    private static func str(_ d: [String: Any], _ keys: String...) -> String {
        for k in keys {
            if let s = d[k] as? String, !s.isEmpty { return s }
            if let n = d[k] as? NSNumber { return n.stringValue }
        }
        return ""
    }
    private static func int(_ d: [String: Any], _ keys: String...) -> Int {
        for k in keys {
            if let n = d[k] as? Int { return n }
            if let n = d[k] as? NSNumber { return n.intValue }
            if let s = d[k] as? String, let i = Int(s) { return i }
        }
        return 0
    }
}
