import SwiftUI
import AVKit
import AVFoundation

/// 视频播放页（对应 PlayContainer + 播放器菜单 + 弹幕/字幕/Anime4K/投屏/手势）
struct VideoPlayerView: View {
    let url: String
    let title: String
    let episodes: [MovieVideo.Episode]
    @State var currentIndex: Int
    var vodInfo: VodInfo? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer? = nil
    @State private var playerLayer: AVPlayerLayer? = nil
    @State private var showControls = false
    @State private var showEpisodes = false
    @State private var showSettings = false
    @State private var showCast = false
    @State private var speed: Float = 1.0
    @State private var scaleMode: ContentMode = .fit
    @State private var isPlaying = true
    @State private var timeMs: Int64 = 0
    @State private var duration: Double = 0
    @State private var currentCue: SubtitleCue? = nil
    @State private var durationObserver: NSKeyValueObservation? = nil

    // 引擎
    @StateObject private var danmu = DanmakuEngine()
    @State private var subtitleObj = TimedTextObject()
    @State private var subtitleStyle = StorageService.shared.loadAny(
        SubtitleStyle.self, "subtitleStyle", default: .default)
    @State private var showSubtitleControls = false
    @State private var showDanmuControls = false
    @State private var danmuInput = ""

    // 手势
    @State private var gesturePercent: CGFloat = 0
    @State private var gestureType: String = ""
    @State private var showGestureHUD = false
    @State private var brightness: CGFloat = UIScreen.main.brightness
    @State private var volume: CGFloat = 0.5

    // 设置状态
    @State private var anime4kTier: Anime4KTier = .light
    @State private var anime4kEnabled = StorageService.shared.flag("anime4k")
    @State private var selectedPreset = "自然"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // 视频层（AVPlayerViewController 承载）
            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation { showControls.toggle() } }
            } else {
                ProgressView("缓冲中…").tint(.white)
            }

            // 手势层
            PlayerGestureOverlay(
                onBrightness: { v in
                    UIScreen.main.brightness = v; brightness = v
                    gestureType = "亮度"; gesturePercent = v; showGestureHUD = true
                },
                onVolume: { v in
                    volume = v; gestureType = "音量"; gesturePercent = v; showGestureHUD = true
                    VolumeController.shared.setVolume(v)
                },
                onSeek: { delta, ended in
                    if ended { showGestureHUD = false; return }
                    let newT = max(0, min(duration, Double(timeMs)/1000 + delta))
                    seek(to: newT)
                    gestureType = delta >= 0 ? "快进" : "快退"
                    gesturePercent = duration > 0 ? CGFloat(newT/duration) : 0
                    showGestureHUD = true
                }
            )
            .ignoresSafeArea()

            // 弹幕层
            if danmu.config.enabled {
                DanmakuOverlay(engine: danmu, timeMs: $timeMs)
                    .ignoresSafeArea().allowsHitTesting(false)
            }

            // 字幕层
            SubtitleOverlay(cue: currentCue, style: subtitleStyle)

            // 手势 HUD
            if showGestureHUD {
                VStack {
                    Text(gestureType).font(.headline)
                    Text("\(Int(gesturePercent * 100))%").font(.title.bold())
                }
                .padding(24).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(.white).transition(.opacity)
            }

            // 顶部栏
            if showControls {
                VStack {
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "chevron.left").font(.title2).foregroundStyle(.white) }
                        Spacer()
                        Text(title).foregroundStyle(.white).font(.headline).lineLimit(1)
                        Spacer()
                        Button { showCast = true } label: { Image(systemName: "airplayvideo").foregroundStyle(.white) }
                        Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3").foregroundStyle(.white) }
                    }
                    .padding().background(LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom))
                    Spacer()
                }
            }

            // 底部控制栏
            if showControls {
                VStack {
                    Spacer()
                    VStack(spacing: 10) {
                        // 进度条
                        Slider(value: Binding(
                            get: { Double(timeMs) / 1000 },
                            set: { v in seek(to: v) }
                        ), in: 0...max(duration, 1)).tint(AppTheme.accent())
                        HStack {
                            Text(formatTime(Double(timeMs)/1000)).font(.caption2)
                            Spacer()
                            Text(formatTime(duration)).font(.caption2)
                        }.foregroundStyle(.white)

                        HStack(spacing: 24) {
                            Button { previousEpisode() } label: { Image(systemName: "backward.end.fill").font(.title2).foregroundStyle(.white) }
                            Button { togglePlay() } label: {
                                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.largeTitle).foregroundStyle(.white)
                            }
                            Button { nextEpisode() } label: { Image(systemName: "forward.end.fill").font(.title2).foregroundStyle(.white) }
                        }
                        HStack(spacing: 16) {
                            Button("选集") { showEpisodes = true }
                            Button("字幕") { showSubtitleControls = true }
                            Button("弹幕") { showDanmuControls = true }
                            Button("\(Int(speed))x") { cycleSpeed() }
                            Button("比例") { scaleMode = scaleMode == .fit ? .fill : .fit }
                        }
                        .font(.caption).foregroundStyle(.white)
                    }
                    .padding().background(.black.opacity(0.6))
                }
            }
        }
        .statusBar(hidden: true)
        .onAppear {
            setupPlayer()
            loadDanmuAndSubtitle()
        }
        .onDisappear { player?.pause(); player = nil }
        .sheet(isPresented: $showEpisodes) {
            EpisodeSheet(episodes: episodes, currentIndex: $currentIndex) { idx in
                currentIndex = idx; setupPlayer(); loadDanmuAndSubtitle()
            }
        }
        .sheet(isPresented: $showSettings) {
            PlayerSettingsSheet(speed: $speed, danmu: $danmu.config, anime4kTier: $anime4kTier,
                                anime4kEnabled: $anime4kEnabled, preset: $selectedPreset) {
                applySpeed(); saveDanmuConfig()
            }
        }
        .sheet(isPresented: $showCast) {
            CastDeviceSheet { device in
                Task { _ = await DLNAService.shared.cast(url: currentURL(), title: title, to: device) }
            }
        }
        .sheet(isPresented: $showSubtitleControls) { subtitleControlsSheet }
        .sheet(isPresented: $showDanmuControls) { danmuControlsSheet }
    }

    // MARK: - 播放器
    private func setupPlayer() {
        guard episodes.indices.contains(currentIndex) else { return }
        let ep = episodes[currentIndex]
        guard let u = URL(string: ep.url.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? ep.url) else { return }
        let item = AVPlayerItem(url: u)
        player = AVPlayer(playerItem: item)
        applySpeed()
        isPlaying = true
        player?.play()

        // 时间观察
        player?.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { t in
            timeMs = Int64(t.seconds * 1000)
            if !subtitleObj.cues.isEmpty {
                currentCue = SubtitleEngine.shared.cue(at: timeMs, in: subtitleObj, style: subtitleStyle)
            }
        }
        // 时长
        durationObserver = item.observe(\.duration) { it, _ in
            DispatchQueue.main.async { duration = it.duration.seconds.isFinite ? it.duration.seconds : 0 }
        }
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
            DispatchQueue.main.async { nextEpisode() }
        }
        if let info = vodInfo {
            var m = info; m.playIndex = currentIndex; m.playNote = ep.name
            LibraryViewModel().addHistory(m)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation { showControls = false } }
    }

    private func currentURL() -> String {
        episodes.indices.contains(currentIndex) ? episodes[currentIndex].url : url
    }
    private func togglePlay() { if isPlaying { player?.pause() } else { player?.play() }; isPlaying.toggle() }
    private func cycleSpeed() { speed = speed >= 2.0 ? 0.75 : speed + 0.25; applySpeed() }
    private func applySpeed() { player?.rate = speed }
    private func seek(to seconds: Double) {
        let t = CMTime(value: Int64(seconds * 1_000_000), timescale: 1_000_000)
        player?.seek(to: t); timeMs = Int64(seconds * 1000)
        danmu.reset()
    }
    private func nextEpisode() { if currentIndex < episodes.count - 1 { currentIndex += 1; setupPlayer(); loadDanmuAndSubtitle() } }
    private func previousEpisode() { if currentIndex > 0 { currentIndex -= 1; setupPlayer(); loadDanmuAndSubtitle() } }

    // MARK: - 弹幕/字幕加载
    private func loadDanmuAndSubtitle() {
        // 弹幕
        danmu.config.enabled = StorageService.shared.flag("danmuOn")
        if danmu.config.online, let dmUrl = vodInfo?.playNote {
            // 从详情注入的弹幕地址加载（实际由 API 提供）
        }
        // 本地/在线字幕
        if let info = vodInfo, !info.sourceKey.isEmpty {
            Task {
                let candidates = await SubtitleEngine.shared.onlineCandidates(name: info.name)
                if let first = candidates.first, let text = await NetworkService.getText(first.url) {
                    subtitleObj = await SubtitleEngine.shared.parse(text: text, filename: info.name + "." + first.format)
                }
            }
        }
    }
    private func saveDanmuConfig() { /* DanmakuConfig 随实例保存，可持久化到 StorageService */ }

    // MARK: - 面板
    private var subtitleControlsSheet: some View {
        NavigationStack {
            List {
                Section("字号") {
                    Stepper("字号 \(subtitleStyle.fontSize)", value: $subtitleStyle.fontSize, in: 12...64)
                    Button("字幕上移") { subtitleStyle.positionOffset -= 20 }
                    Button("字幕下移") { subtitleStyle.positionOffset += 20 }
                }
                Section("样式") {
                    Picker("样式", selection: Binding(
                        get: { subtitleStyle.color == "#FFFF00" ? "二" : "一" },
                        set: { subtitleStyle = $0 == "二" ? .styleTwo : .default }
                    )) { Text("样式一").tag("一"); Text("样式二").tag("二") }
                }
                Section("延时") {
                    Stepper("延时 \(Int(subtitleStyle.delayMs)) ms", value: $subtitleStyle.delayMs, in: -10000...10000, step: 500)
                }
                Section {
                    Button("在线搜索字幕") {
                        Task {
                            let c = await SubtitleEngine.shared.onlineCandidates(name: title)
                            if let first = c.first, let text = await NetworkService.getText(first.url) {
                                subtitleObj = await SubtitleEngine.shared.parse(text: text, filename: title + ".srt")
                            }
                        }
                    }
                }
            }
            .navigationTitle("字幕设置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        StorageService.shared.saveAny(subtitleStyle, "subtitleStyle")
                        showSubtitleControls = false
                    }
                }
            }
        }
    }

    private var danmuControlsSheet: some View {
        NavigationStack {
            List {
                Toggle("弹幕开关", isOn: $danmu.config.enabled)
                Toggle("随机颜色", isOn: $danmu.config.randomColor)
                Picker("速度", selection: $danmu.config.speed) {
                    Text("超慢").tag(0); Text("慢").tag(1); Text("适中").tag(2); Text("快").tag(3)
                }
                Picker("大小", selection: $danmu.config.sizeLevel) {
                    ForEach(0..<5) { Text("\($0 + 1) 档").tag($0) }
                }
                Stepper("行数 \(danmu.config.lines)", value: $danmu.config.lines, in: 0...10)
                HStack {
                    TextField("输入弹幕", text: $danmuInput)
                    Button("发送") {
                        if !danmuInput.isEmpty {
                            var d = Danmaku(timeMs: timeMs, text: danmuInput)
                            d.color = danmu.config.randomColor ? Int.random(in: 0...0xFFFFFF) : 0xFFFFFF
                            danmu.append(d)
                            danmuInput = ""
                        }
                    }
                }
                Section {
                    Button("在线搜索弹幕") {
                        Task {
                            let url = "https://api.avbox.top/danmu/search?q=\(title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title)"
                            await danmu.load(from: url)
                        }
                    }
                }
            }
            .navigationTitle("弹幕设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { saveDanmuConfig(); showDanmuControls = false } } }
        }
    }

    private func formatTime(_ s: Double) -> String {
        let t = Int(s); return String(format: "%02d:%02d", t/60, t%60)
    }
}

struct EpisodeSheet: View {
    let episodes: [MovieVideo.Episode]
    @Binding var currentIndex: Int
    let onPick: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 10)], spacing: 10) {
                    ForEach(episodes.indices, id: \.self) { idx in
                        Button { onPick(idx); dismiss() } label: {
                            Text(episodes[idx].name).font(.caption).frame(maxWidth: .infinity, minHeight: 40)
                                .background(currentIndex == idx ? AppTheme.accent() : Color.secondary.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(currentIndex == idx ? .white : .primary)
                        }
                    }
                }.padding()
            }
            .navigationTitle("选集").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}

struct PlayerSettingsSheet: View {
    @Binding var speed: Float
    @Binding var danmu: DanmakuConfig
    @Binding var anime4kTier: Anime4KTier
    @Binding var anime4kEnabled: Bool
    @Binding var preset: String
    let onChange: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("调整倍速") {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { s in
                        Button("\(s)x") { speed = Float(s); onChange() }
                            .foregroundStyle(speed == Float(s) ? AppTheme.accent() : .primary)
                    }
                }
                Section("Anime4K 画质增强") {
                    Toggle("启用", isOn: $anime4kEnabled)
                    Picker("档位", selection: $anime4kTier) {
                        ForEach(Anime4KTier.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section("画面预设") {
                    Picker("预设", selection: $preset) {
                        ForEach(["自然","艳丽","清晰","明亮","影院","护眼","动漫"], id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("画面缩放") {
                    Picker("缩放", selection: Binding(
                        get: { 0 }, set: { _ in }
                    )) { Text("填充").tag(0); Text("原始").tag(1) }
                }
            }
            .navigationTitle("播放设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { onChange(); dismiss() } } }
        }
    }
}
