import Foundation
import UIKit
import Combine

/// 弹幕引擎（对应安卓 player/danmu + Danmu bean）
/// 支持 XML/AcFun 弹幕解析、滚动/顶部/底部三类弹幕、轨道分配（防重叠）。

/// 弹幕类型：对应 master-flv 的 type（1=滚动 4=底部 5=顶部 6=逆向 7=高级）
enum DanmakuType: Int, Codable {
    case scroll = 1, bottom = 4, top = 5, reverse = 6, advanced = 7
}

/// 一条弹幕
struct Danmaku: Identifiable, Codable {
    var id = UUID().uuidString
    var timeMs: Int64 = 0          // 出现时间（毫秒）
    var type: DanmakuType = .scroll
    var fontSize: Float = 25
    var color: Int = 0xFFFFFF      // RGB
    var text: String = ""
    var sendTime: String = ""
    var source: String = ""

    var uiColor: UIColor {
        UIColor(red: CGFloat((color >> 16) & 0xFF)/255,
                green: CGFloat((color >> 8) & 0xFF)/255,
                blue: CGFloat(color & 0xFF)/255, alpha: 1)
    }
}

/// 弹幕设置（对应 DanmuSettingsState.config）
struct DanmakuConfig: Codable {
    var enabled = true
    var online = false
    var randomColor = false
    var speed: Int = 1             // 0超慢 1慢 2适中 3快
    var sizeLevel: Int = 1
    var lines: Int = 0             // 0=自动
    var alpha: Float = 1.0

    var speedFactor: CGFloat {
        [0.6, 0.8, 1.0, 1.4][min(max(speed, 0), 3)]
    }
    var fontSize: CGFloat {
        [18, 22, 27, 33, 40][min(max(sizeLevel, 0), 4)]
    }
}

/// 轨道上正在显示的弹幕
struct ActiveDanmaku {
    var danmaku: Danmaku
    var x: CGFloat                 // 当前 x（屏幕坐标）
    var y: CGFloat                 // 轨道 y
    var width: CGFloat
    var speed: CGFloat
    var trackIndex: Int
}

/// 弹幕引擎核心
final class DanmakuEngine: ObservableObject {
    @Published var config = DanmakuConfig()
    private(set) var danmakus: [Danmaku] = []       // 已按时间排序
    private var cursor = 0                           // 时间游标
    private var active: [ActiveDanmaku] = []
    private var trackLastTime: [Int: TimeInterval] = [:]  // 轨道上次占用时间
    private let displayLink = CADisplayLink()

    // MARK: - 解析
    /// 解析弹幕 XML（Bilibili / AcFun 风格），支持 gzip/deflate
    func parse(xml: String, source: String = "") async -> [Danmaku] {
        var result: [Danmaku] = []
        let pattern = "<d\\s+p=\"([^\"]*)\">(.*?)</d>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { return [] }
        let ns = xml as NSString
        let matches = regex.matches(in: xml, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            let param = ns.substring(with: m.range(at: 1))
            let text = ns.substring(with: m.range(at: 2))
            let parts = param.split(separator: ",")
            guard parts.count >= 4 else { continue }
            let time = (Double(parts[0]) ?? 0) * 1000
            let type = DanmakuType(rawValue: Int(parts[1]) ?? 1) ?? .scroll
            let size = Float(parts[2]) ?? 25
            var color = Int(parts[3]) ?? 0xFFFFFF
            if config.randomColor {
                color = [0xFFFFFF, 0xFF0000, 0x00FF00, 0x00FFFF, 0xFFFF00, 0xFF00FF, 0xFF8000].randomElement() ?? color
            }
            result.append(Danmaku(timeMs: Int64(time), type: type, fontSize: size,
                                  color: color, text: decodeXML(text), source: source))
        }
        self.danmakus = result.sorted { $0.timeMs < $1.timeMs }
        cursor = 0
        return self.danmakus
    }

    private func decodeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// 从网络加载弹幕
    func load(from url: String) async {
        guard let text = await NetworkService.getText(url) else { return }
        _ = await parse(xml: text, source: url)
    }

    // MARK: - 播放控制
    func reset() { cursor = 0; active.removeAll(); trackLastTime.removeAll() }

    /// 追加一条本地弹幕（发送弹幕用）
    func append(_ d: Danmaku) {
        danmakus.append(d)
        danmakus.sort { $0.timeMs < $1.timeMs }
    }

    /// 根据当前播放时间更新活动弹幕
    func tick(timeMs: Int64, viewWidth: CGFloat, viewHeight: CGFloat) -> [ActiveDanmaku] {
        guard config.enabled else { return [] }
        // 投放新弹幕
        while cursor < danmakus.count, danmakus[cursor].timeMs <= timeMs {
            let d = danmakus[cursor]
            spawn(d, width: viewWidth, height: viewHeight, time: TimeInterval(timeMs)/1000)
            cursor += 1
        }
        // 移动
        let dt: CGFloat = 1.0 / 60
        for i in active.indices {
            active[i].x -= active[i].speed * dt * config.speedFactor
        }
        active.removeAll { $0.x + $0.width < -20 }
        return active
    }

    private func spawn(_ d: Danmaku, width: CGFloat, height: CGFloat, time: TimeInterval) {
        let fontSize = config.fontSize * (d.fontSize / 25)
        let textWidth = CGFloat(d.text.count) * fontSize * 1.05 + 20
        let trackCount = config.lines > 0 ? config.lines : max(3, Int(height / (fontSize * 1.6)))
        var best = 0
        var bestTime: TimeInterval = .greatestFiniteMagnitude
        for t in 0..<trackCount {
            let last = trackLastTime[t] ?? 0
            if last < bestTime { bestTime = last; best = t }
        }
        // 防重叠：轨道上次弹幕要离开一定距离
        if time - bestTime < 0.8 && trackCount > 1 { best = (best + 1) % trackCount }
        trackLastTime[best] = time
        let y = fontSize * 0.8 + CGFloat(best) * (fontSize * 1.6)
        let speed: CGFloat = (width + textWidth) / 8.0 * config.speedFactor
        active.append(ActiveDanmaku(danmaku: d, x: width, y: y, width: textWidth,
                                    speed: speed, trackIndex: best))
    }
}
