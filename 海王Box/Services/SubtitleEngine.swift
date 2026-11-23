import Foundation

/// 字幕引擎（对应安卓 subtitle 包：FormatSRT / FormatASS / FormatTTML / FormatSCC / FormatSTL）
/// 支持 SRT / VTT / ASS(SSA) / TTML 解析，统一为时间轴字幕条目。

struct SubtitleStyle: Codable {
    var fontSize: Int = 28
    var color: String = "#FFFFFF"      // 前景
    var outlineColor: String = "#000000"
    var backgroundColor: String = "#00000000"
    var bold = false
    var italic = false
    var positionOffset: Int = 0        // 垂直偏移（px，正为下）
    var delayMs: Int64 = 0

    static let `default` = SubtitleStyle()
    static let styleTwo = SubtitleStyle(fontSize: 32, color: "#FFFF00", outlineColor: "#000000", bold: true)
}

struct SubtitleCue: Identifiable, Codable {
    var id = UUID().uuidString
    var startMs: Int64 = 0
    var endMs: Int64 = 0
    var text: String = ""              // 支持 \N 换行
    var layer: Int = 0
    var style: String = "Default"

    var displayText: String { text.replacingOccurrences(of: "\\N", with: "\n").replacingOccurrences(of: "\\n", with: "\n") }
}

struct TimedTextObject {
    var cues: [SubtitleCue] = []
    var styles: [String: SubtitleStyle] = [:]
    var title: String = ""
    var language: String = ""
}

enum SubtitleFormat: String, CaseIterable, Identifiable {
    case srt, vtt, ass, ssa, ttml, scc, stl, unknown
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .srt: return "SRT"; case .vtt: return "WebVTT"; case .ass: return "ASS"
        case .ssa: return "SSA"; case .ttml: return "TTML"; case .scc: return "SCC"
        case .stl: return "STL"; case .unknown: return "未知"
        }
    }
}

/// 字幕解析与查找引擎
final class SubtitleEngine {
    static let shared = SubtitleEngine()

    /// 自动识别格式并解析
    func parse(text: String, filename: String = "") async -> TimedTextObject {
        let fmt = detect(text: text, filename: filename)
        switch fmt {
        case .ass, .ssa: return parseASS(text)
        case .vtt: return parseSRT(text)     // VTT 与 SRT 结构兼容
        case .ttml: return parseTTML(text)
        case .scc: return parseSCC(text)
        default: return parseSRT(text)
        }
    }

    func detect(text: String, filename: String) -> SubtitleFormat {
        let head = String(text.prefix(400)).lowercased()
        if head.contains("[script info]") || head.contains("<v ") && head.contains("dialogue:") { return .ass }
        if head.contains("webvtt") { return .vtt }
        if head.contains("<tt") && (head.contains("xmlns") || head.contains("<body")) { return .ttml }
        if filename.lowercased().hasSuffix(".ass") { return .ass }
        if filename.lowercased().hasSuffix(".vtt") { return .vtt }
        if filename.lowercased().hasSuffix(".ttml") { return .ttml }
        if filename.lowercased().hasSuffix(".scc") { return .scc }
        if text.contains("-->") { return .srt }
        return .unknown
    }

    // MARK: - SRT / VTT
    func parseSRT(_ text: String) -> TimedTextObject {
        var obj = TimedTextObject()
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timeLine = lines.first(where: { $0.contains("-->") }) else { continue }
            let parts = timeLine.split(separator: "-->").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let start = parseClock(parts[0])
            let end = parseClock(parts[1].split(separator: " ").first.map(String.init) ?? parts[1])
            let textStart = lines.firstIndex(where: { $0.contains("-->") })! + 1
            let body = lines.dropFirst(textStart).joined(separator: "\n")
                .removingRegex("<c[^>]*>")
            if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                obj.cues.append(SubtitleCue(startMs: start, endMs: end, text: body))
            }
        }
        obj.cues.sort { $0.startMs < $1.startMs }
        return obj
    }

    private func parseClock(_ s: String) -> Int64 {
        // 00:00:01,234 / 00:01.234 / 01:23.456
        let cleaned = s.replacingOccurrences(of: ",", with: ".")
        let comps = cleaned.split(separator: ":").map(String.init)
        var h = 0, m = 0, sec: Double = 0
        if comps.count == 3 { h = Int(comps[0]) ?? 0; m = Int(comps[1]) ?? 0; sec = Double(comps[2]) ?? 0 }
        else if comps.count == 2 { m = Int(comps[0]) ?? 0; sec = Double(comps[1]) ?? 0 }
        else { sec = Double(comps.first ?? "0") ?? 0 }
        return Int64((Double(h * 3600 + m * 60) + sec) * 1000)
    }

    // MARK: - ASS / SSA
    func parseASS(_ text: String) -> TimedTextObject {
        var obj = TimedTextObject()
        let lines = text.replacingOccurrences(of: "\r", with: "").split(separator: "\n").map(String.init)
        var inStyles = false
        for line in lines {
            if line.hasPrefix("[V4+ Styles]") || line.hasPrefix("[V4 Styles]") { inStyles = true; continue }
            if line.hasPrefix("[") { inStyles = false; continue }
            if inStyles && line.hasPrefix("Style:"), let style = parseASSStyle(line) {
                obj.styles[style.name] = style.style
                continue
            }
            if line.hasPrefix("Dialogue:") {
                guard let cue = parseASSDialogue(line) else { continue }
                obj.cues.append(cue)
            }
        }
        obj.cues.sort { $0.startMs < $1.startMs }
        return obj
    }

    private func parseASSStyle(_ line: String) -> (name: String, style: SubtitleStyle)? {
        let parts = line.dropFirst("Style:".count).split(separator: ",", maxSplits: 22).map(String.init)
        guard parts.count > 9 else { return nil }
        var s = SubtitleStyle.default
        s.fontSize = Int(Double(parts[2]) ?? 28)
        s.bold = parts[3] == "-1" || parts[3] == "1"
        s.italic = parts[4] == "-1" || parts[4] == "1"
        s.color = assColorToHex(parts[9])
        return (parts[0].trimmingCharacters(in: .whitespaces), s)
    }

    private func parseASSDialogue(_ line: String) -> SubtitleCue? {
        let parts = line.dropFirst("Dialogue:".count).split(separator: ",", maxSplits: 9).map(String.init)
        guard parts.count >= 10 else { return nil }
        let start = parseClock(parts[1]); let end = parseClock(parts[2])
        let style = parts[3].trimmingCharacters(in: .whitespaces)
        var body = parts[9]
        // 去掉 {\...} 内联样式标签，保留 \N 换行
        body = body.removingRegex("\\{[^}]*\\}")
        return SubtitleCue(startMs: start, endMs: end, text: body, layer: Int(parts[0]) ?? 0, style: style)
    }

    private func assColorToHex(_ ass: String) -> String {
        // ASS &HAABBGGRR
        let v = ass.replacingOccurrences(of: "&H", with: "").replacingOccurrences(of: "&", with: "")
        guard let n = Int(v, radix: 16) else { return "#FFFFFF" }
        let r = (n >> 0) & 0xFF, g = (n >> 8) & 0xFF, b = (n >> 16) & 0xFF
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    // MARK: - TTML / VTT 简化
    func parseTTML(_ text: String) -> TimedTextObject {
        var obj = TimedTextObject()
        let pattern = #"<p\s+begin="([^"]+)"\s+end="([^"]+)"[^>]*>(.*?)</p>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { return obj }
        let ns = text as NSString
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let start = parseClock(String(ns.substring(with: m.range(at: 1))))
            let end = parseClock(String(ns.substring(with: m.range(at: 2))))
            let body = ns.substring(with: m.range(at: 3))
                .removingRegex("<[^>]+>")
            obj.cues.append(SubtitleCue(startMs: start, endMs: end, text: body))
        }
        return obj
    }

    func parseSCC(_ text: String) -> TimedTextObject {
        // SCC 为行490时间码，简化处理为整段显示
        var obj = TimedTextObject()
        let body = text.split(separator: "\n").filter { !$0.hasPrefix("Scenarist") }.joined(separator: " ")
        obj.cues.append(SubtitleCue(startMs: 0, endMs: Int64.max, text: body))
        return obj
    }

    /// 查找当前时间应显示的字幕
    func cue(at timeMs: Int64, in obj: TimedTextObject, style: SubtitleStyle) -> SubtitleCue? {
        let t = timeMs - style.delayMs
        return obj.cues.first { $0.startMs <= t && t < $0.endMs }
    }

    /// 在线搜索字幕（基于文件名，返回候选地址）
    func onlineCandidates(name: String) async -> [SubtitleCandidate] {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let url = "https://api.avbox.top/subtitle/search?q=\(encoded)"
        guard let text = await NetworkService.getText(url),
              let data = text.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.map { SubtitleCandidate(title: $0["title"] as? String ?? "",
                                           url: $0["url"] as? String ?? "",
                                           format: $0["format"] as? String ?? "srt") }
    }
}

struct SubtitleCandidate: Identifiable, Codable {
    var title: String, url: String, format: String
    var id: String { url }
}

// MARK: - 正则快捷
extension String {
    /// 用正则移除匹配片段
    func removingRegex(_ pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return self }
        let range = NSRange(location: 0, length: (self as NSString).length)
        return regex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: "")
    }
}
