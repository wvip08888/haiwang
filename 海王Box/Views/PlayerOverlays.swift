import SwiftUI
import UIKit

/// 弹幕渲染层（UIKit CADisplayLink 驱动，对应 PlayerDanmakuView）
struct DanmakuOverlay: UIViewRepresentable {
    let engine: DanmakuEngine
    @Binding var timeMs: Int64

    func makeUIView(context: Context) -> DanmakuCanvas {
        let v = DanmakuCanvas()
        v.engine = engine
        return v
    }
    func updateUIView(_ v: DanmakuCanvas, context: Context) {
        v.bind(time: $timeMs)
    }
}

final class DanmakuCanvas: UIView {
    var engine: DanmakuEngine?
    private var displayLink: CADisplayLink?
    private var timeProvider: (() -> Int64)?
    private var labelPool: [UILabel] = []

    func bind(time: Binding<Int64>) {
        timeProvider = { time.wrappedValue }
        if displayLink == nil {
            displayLink = CADisplayLink(target: self, selector: #selector(tick))
            displayLink?.add(to: .main, forMode: .common)
        }
    }

    @objc private func tick() {
        guard let engine = engine, let t = timeProvider else { return }
        let active = engine.tick(timeMs: t, viewWidth: bounds.width, viewHeight: bounds.height)
        // 复用 label
        for lbl in labelPool { lbl.isHidden = true }
        for (i, a) in active.enumerated() {
            let lbl: UILabel
            if i < labelPool.count { lbl = labelPool[i] }
            else {
                lbl = UILabel()
                labelPool.append(lbl)
                addSubview(lbl)
            }
            lbl.isHidden = false
            lbl.text = a.danmaku.text
            lbl.textColor = a.danmaku.uiColor
            lbl.font = .systemFont(ofSize: engine.config.fontSize * (a.danmaku.fontSize/25), weight: .medium)
            lbl.sizeToFit()
            lbl.layer.shadowColor = UIColor.black.cgColor
            lbl.layer.shadowRadius = 1
            lbl.layer.shadowOpacity = 0.8
            lbl.frame = CGRect(x: a.x, y: a.y, width: lbl.frame.width, height: lbl.frame.height)
        }
    }

    deinit { displayLink?.invalidate() }
}

/// 字幕渲染层（对应 widget/SubtitleTextView）
struct SubtitleOverlay: View {
    let cue: SubtitleCue?
    let style: SubtitleStyle
    var body: some View {
        Group {
            if let cue = cue {
                Text(cue.displayText)
                    .font(.system(size: CGFloat(style.fontSize), weight: style.bold ? .bold : .regular))
                    .italic(style.italic)
                    .foregroundColor(Color(hex: style.color))
                    .multilineTextAlignment(.center)
                    .shadow(color: Color(hex: style.outlineColor), radius: 1, x: 0, y: 1)
                    .shadow(color: Color(hex: style.outlineColor), radius: 1, x: 1, y: 0)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40 + CGFloat(style.positionOffset))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .allowsHitTesting(false)
    }
}

extension Color {
    init(hex: String) {
        let h = hex.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        let a = h.count == 8 ? Double((rgb >> 24) & 0xFF)/255 : 1.0
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF)/255,
                  green: Double((rgb >> 8) & 0xFF)/255,
                  blue: Double(rgb & 0xFF)/255,
                  opacity: a)
    }
}

/// 播放手势层（对应 VideoGestureHandler）：左半屏上下=亮度，右半屏上下=音量，左右拖=进度
struct PlayerGestureOverlay: UIViewRepresentable {
    let onBrightness: (CGFloat) -> Void
    let onVolume: (CGFloat) -> Void
    let onSeek: (TimeInterval, Bool) -> Void   // (秒, 是否结束)

    func makeUIView(context: Context) -> GestureView {
        let v = GestureView()
        v.onBrightness = onBrightness
        v.onVolume = onVolume
        v.onSeek = onSeek
        return v
    }
    func updateUIView(_ v: GestureView, context: Context) {
        v.onBrightness = onBrightness; v.onVolume = onVolume; v.onSeek = onSeek
    }
}

final class GestureView: UIView {
    var onBrightness: ((CGFloat) -> Void)?
    var onVolume: ((CGFloat) -> Void)?
    var onSeek: ((TimeInterval, Bool) -> Void)?
    private var startY: CGFloat = 0
    private var startX: CGFloat = 0
    private var startBrightness: CGFloat = UIScreen.main.brightness
    private var startVolume: CGFloat = 0.5
    private var isSeeking = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDouble(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleDouble(_ tap: UITapGestureRecognizer) {
        let x = tap.location(in: self).x
        onSeek?(x < bounds.width/2 ? -10 : 10, true)
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        let p = pan.location(in: self)
        switch pan.state {
        case .began:
            startY = p.y; startX = p.x
            startBrightness = UIScreen.main.brightness
            isSeeking = false
        case .changed:
            let dy = startY - p.y
            let dx = p.x - startX
            if abs(dx) > 60 && abs(dx) > abs(dy) {
                isSeeking = true
                onSeek?(TimeInterval(dx / 8), false)
            } else if startX < bounds.width/2 {
                let b = min(max(startBrightness + dy/1000, 0), 1)
                onBrightness?(b)
            } else {
                let v = min(max(startVolume + dy/1000, 0), 1)
                onVolume?(v)
            }
        case .ended:
            if isSeeking { onSeek?(0, true) }
        default: break
        }
    }
}

/// 投屏设备选择面板（对应 CastSheet）
struct CastDeviceSheet: View {
    @ObservedObject var dlna = DLNAService.shared
    let onSelect: (CastDevice) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if dlna.searching {
                    VStack {
                        ProgressView()
                        Text("正在搜索设备...").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if dlna.devices.isEmpty {
                    ContentUnavailableView {
                        Label("未找到可用设备", systemImage: "tv")
                    } description: {
                        Text("确认电视/盒子已开启 DLNA，并与手机连接同一 Wi-Fi")
                    }
                } else {
                    List(dlna.devices) { device in
                        Button {
                            onSelect(device); dismiss()
                        } label: {
                            HStack {
                                Image(systemName: device.isTVBox ? "tv.fill" : "airplayvideo")
                                    .foregroundStyle(AppTheme.accent())
                                VStack(alignment: .leading) {
                                    Text(device.name)
                                    Text(device.host).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("投屏到设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("刷新") { Task { await dlna.search() } } }
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
        }
        .task { await dlna.search() }
    }
}
