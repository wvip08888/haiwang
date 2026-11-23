import Foundation

/// 统一的 HTTP 请求封装（对应安卓的 OkHttp Clients）
enum NetworkService {

    static let defaultUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    struct Response {
        var data: Data
        var statusCode: Int
        var text: String { String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) ?? "" }
    }

    enum NetworkError: Error, LocalizedError {
        case invalidURL(String)
        case httpStatus(Int)
        case noData
        var errorDescription: String? {
            switch self {
            case .invalidURL(let u): return "地址无效：\(u)"
            case .httpStatus(let c): return "HTTP \(c)"
            case .noData: return "无数据"
            }
        }
    }

    /// GET 请求（支持自定义 header / UA / Referer）
    static func get(_ urlString: String,
                    headers: [String: String] = [:],
                    timeout: TimeInterval = 15) async throws -> Response {
        guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else {
            throw NetworkError.invalidURL(urlString)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(headers["User-Agent"] ?? defaultUA, forHTTPHeaderField: "User-Agent")
        for (k, v) in headers where k.lowercased() != "user-agent" {
            request.setValue(v, forHTTPHeaderField: k)
        }
        let (data, resp) = try await URLSession.shared.data(for: request)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 200
        guard (200..<400).contains(code) else { throw NetworkError.httpStatus(code) }
        return Response(data: data, statusCode: code)
    }

    static func getText(_ urlString: String, headers: [String: String] = [:]) async -> String? {
        try? await get(urlString, headers: headers).text
    }

    static func getJSON(_ urlString: String, headers: [String: String] = [:]) async -> [String: Any]? {
        guard let data = try? await get(urlString, headers: headers).data else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// 拼接 URL 与查询参数
    static func buildURL(base: String, path: String, query: [String: String]) -> String {
        var s = base.hasSuffix("/") ? String(base.dropLast()) : base
        if !path.isEmpty {
            s += path.hasPrefix("/") ? path : "/" + path
        }
        if !query.isEmpty {
            let items = query.map { k, v in
                let ek = k.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? k
                let ev = v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v
                return "\(ek)=\(ev)"
            }.joined(separator: "&")
            s += (s.contains("?") ? "&" : "?") + items
        }
        return s
    }
}
