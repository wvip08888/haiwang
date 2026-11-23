import Foundation

/// 采集脚本服务（对应安卓 SpiderLoader / catvod）
/// 把 JSRuntime 桥接到点播源：根据 SourceBean.jar(js) 或 api 加载脚本，
/// 调用 spider.home/category/detail/search/play 方法解析数据。
final class SpiderService {
    static let shared = SpiderService()

    private let js = JSRuntime.shared
    private var scriptCache: [String: String] = [:]   // sourceKey -> script

    /// 为源准备脚本（jar 指向 js 地址，或 api 本身是 js 文件）
    func prepare(source: SourceBean) async {
        let scriptURL = source.jar.isEmpty ? source.api : source.jar
        guard scriptURL.hasPrefix("http"), let code = await NetworkService.getText(scriptURL) else { return }
        scriptCache[source.id] = code
    }

    /// 首页分类
    func home(source: SourceBean) async -> (videos: [MovieVideo], categories: [SortData]) {
        guard let code = scriptCache[source.id] else { return ([], []) }
        let result = await js.execute(script: code, action: "home", params: [:]) ?? [:]
        return (parseVideos(result), parseCategories(result))
    }

    /// 分类列表
    func category(source: SourceBean, tid: String, page: Int, filters: [String: String]) async -> [MovieVideo] {
        guard let code = scriptCache[source.id] else { return [] }
        var params: [String: Any] = ["tid": tid, "page": page]
        for (k, v) in filters { params[k] = v }
        let result = await js.execute(script: code, action: "category", params: params) ?? [:]
        return parseVideos(result)
    }

    /// 搜索
    func search(source: SourceBean, keyword: String, page: Int) async -> [MovieVideo] {
        guard let code = scriptCache[source.id] else { return [] }
        let result = await js.execute(script: code, action: "search",
                                      params: ["keyword": keyword, "page": page]) ?? [:]
        return parseVideos(result)
    }

    /// 详情 + 播放地址
    func detail(source: SourceBean, id: String) async -> VodInfo? {
        guard let code = scriptCache[source.id] else { return nil }
        let result = await js.execute(script: code, action: "detail", params: ["id": id]) ?? [:]
        var info = VodInfo(id: id, sourceKey: source.key, sourceName: source.name)
        if let list = result["list"] as? [[String: Any]], let first = list.first {
            info = parseInfo(first, source: source)
        } else if !result.isEmpty {
            info = parseInfo(result, source: source)
        }
        return info
    }

    /// 播放地址解析（spider.play）
    func playURL(source: SourceBean, flag: String, id: String) async -> String {
        guard let code = scriptCache[source.id] else { return "" }
        let result = await js.execute(script: code, action: "play",
                                      params: ["flag": flag, "id": id]) ?? [:]
        return result["url"] as? String ?? ""
    }

    // MARK: - JS 结果 → 模型
    private func parseVideos(_ obj: [String: Any]) -> [MovieVideo] {
        let arrays = JSONHelper.findArrays(in: obj, keys: ["list", "videos", "data"])
        var out: [MovieVideo] = []
        for arr in arrays {
            for item in arr {
                guard let d = item as? [String: Any] else { continue }
                out.append(MovieVideo(
                    id: S(d, "id"), name: S(d, "name", "title"), pic: S(d, "pic", "cover"),
                    type: S(d, "type"), year: I(d, "year"), actor: S(d, "actor"),
                    director: S(d, "director"), des: S(d, "des"), note: S(d, "note")
                ))
            }
        }
        return out
    }

    private func parseCategories(_ obj: [String: Any]) -> [SortData] {
        guard let arr = obj["class"] as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            let id = S(d, "type_id", "id"); let name = S(d, "type_name", "name")
            guard !id.isEmpty && !name.isEmpty else { return nil }
            return SortData(id: id, name: name)
        }
    }

    private func parseInfo(_ d: [String: Any], source: SourceBean) -> VodInfo {
        var info = VodInfo(
            id: S(d, "id"), name: S(d, "name", "title"), type: S(d, "type"),
            pic: S(d, "pic"), lang: S(d, "lang"), area: S(d, "area"), year: I(d, "year"),
            state: S(d, "state"), actor: S(d, "actor"), director: S(d, "director"),
            des: S(d, "des"), sourceKey: source.key, sourceName: source.name
        )
        if let dd = (d["dl"] as? [String: Any])?["dd"] as? [[String: Any]] {
            for g in dd {
                let flag = S(g, "flag")
                var eps: [MovieVideo.Episode] = []
                if let beans = g["beanList"] as? [[String: Any]] {
                    eps = beans.map { MovieVideo.Episode(name: S($0, "name"), url: S($0, "url")) }
                }
                if eps.isEmpty, let urls = g["urls"] as? String {
                    eps = urls.split(separator: "#").enumerated().map { i, line in
                        let p = line.split(separator: "$", maxSplits: 1)
                        return MovieVideo.Episode(name: p.count > 1 ? String(p[0]) : "第\(i+1)集",
                                                  url: p.count > 1 ? String(p[1]) : String(line))
                    }
                }
                if !eps.isEmpty { info.seriesFlags.append(flag); info.seriesMap[flag] = eps }
            }
        }
        return info
    }

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
