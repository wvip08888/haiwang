import SwiftUI

/// 音乐播放页（对应 MusicPlayerScreen / MusicTrackPlayerActivity）
struct MusicPlayerView: View {
    @ObservedObject var audio = AudioPlaybackService.shared
    @ObservedObject var downloads = DownloadService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showQueue = false
    @State private var lyrics: [LyricLine] = []
    @State private var currentLyricIndex: Int = 0
    @State private var showDownloadConfirm = false
    @State private var toast: String? = nil

    var body: some View {
        ZStack {
            // 背景
            LinearGradient(colors: [AppTheme.accent().opacity(0.5), Color(.systemBackground)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // 顶部
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down").font(.title2)
                    }
                    Spacer()
                    VStack {
                        Text("正在播放").font(.caption).foregroundStyle(.secondary)
                        Text(audio.currentTrack?.sourceId ?? "").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button { showDownloadConfirm = true } label: {
                        Image(systemName: downloads.isDownloaded(audio.currentTrack ?? MusicTrack()) ? "arrow.down.circle.fill" : "arrow.down.circle")
                            .foregroundStyle(downloads.isDownloaded(audio.currentTrack ?? MusicTrack()) ? .green : .primary)
                    }
                }.padding()

                Spacer()

                // 封面
                AsyncImage(url: URL(string: audio.currentTrack?.coverUrl ?? "")) { phase in
                    if let img = phase.image { img.resizable().scaledToFit() }
                    else {
                        RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.2))
                            .overlay(Image(systemName: "music.note").font(.system(size: 80)).foregroundStyle(.secondary))
                    }
                }
                .frame(width: 260, height: 260).cornerRadius(16).shadow(radius: 20)

                // 歌词（简化显示）
                if !lyrics.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 12) {
                                ForEach(lyrics.indices, id: \.self) { idx in
                                    Text(lyrics[idx].text)
                                        .font(.subheadline)
                                        .foregroundStyle(idx == currentLyricIndex ? AppTheme.accent() : .secondary)
                                        .frame(maxWidth: .infinity)
                                        .id(idx)
                                }
                            }
                        }.frame(height: 80)
                        .onChange(of: currentLyricIndex) { idx in
                            withAnimation { proxy.scrollTo(idx, anchor: .center) }
                        }
                    }
                } else {
                    Text(audio.currentTrack?.subtitle ?? "")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                Spacer()

                // 进度条
                VStack {
                    Slider(value: Binding(
                        get: { audio.currentTime },
                        set: { audio.seek(to: $0) }
                    ), in: 0...max(audio.duration, 1))
                    HStack {
                        Text(formatTime(audio.currentTime)).font(.caption2)
                        Spacer()
                        Text(formatTime(audio.duration)).font(.caption2)
                    }
                }.padding(.horizontal)

                // 播放控制
                HStack(spacing: 40) {
                    Button { audio.setPlayMode(audio.playMode.toggled()) } label: {
                        Image(systemName: audio.playMode == .single ? "repeat.1" : (audio.playMode == .list ? "repeat" : "arrow.right"))
                            .font(.title3)
                    }
                    Button { audio.previous() } label: { Image(systemName: "backward.fill").font(.title) }
                    Button { audio.togglePlay() } label: {
                        Image(systemName: audio.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                    }
                    Button { audio.next() } label: { Image(systemName: "forward.fill").font(.title) }
                    Button { showQueue = true } label: { Image(systemName: "list.bullet").font(.title3) }
                }
                .padding(.bottom, 30)
            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $showQueue) {
            QueueView(tracks: audio.tracks, currentIndex: audio.currentIndex) { idx in
                audio.currentIndex = idx
                audio.play(tracks: audio.tracks, at: idx, preferLocal: audio.useLocalDownload)
            }
        }
        .alert("下载歌曲", isPresented: $showDownloadConfirm) {
            Button("取消", role: .cancel) {}
            Button("下载") {
                if let track = audio.currentTrack {
                    DownloadService.shared.download(track)
                    toast = "已加入下载队列"
                }
            }
        } message: {
            Text("将「\(audio.currentTrack?.title ?? "")」下载到本地，可离线播放")
        }
        .overlay(alignment: .top) {
            if let toast = toast {
                Text(toast).font(.caption).padding(8)
                    .background(.black.opacity(0.7), in: Capsule()).foregroundStyle(.white)
                    .padding(.top, 60)
                    .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.toast = nil } }
            }
        }
        .onChange(of: audio.currentTrack?.id) { _ in loadLyrics() }
        .onChange(of: audio.currentTime) { t in updateLyric(t) }
        .onAppear { loadLyrics() }
    }

    private func loadLyrics() {
        // 尝试加载本地 .lrc（若下载的同名歌词存在），否则为空
        guard let track = audio.currentTrack,
              let item = downloads.item(for: track),
              let local = item.localURL else { lyrics = []; return }
        let lrcURL = local.deletingPathExtension().appendingPathExtension("lrc")
        guard let text = try? String(contentsOf: lrcURL, encoding: .utf8) else { lyrics = []; return }
        lyrics = LRCParser.parse(text)
        currentLyricIndex = 0
    }

    private func updateLyric(_ t: Double) {
        guard !lyrics.isEmpty else { return }
        let ms = Int64(t * 1000)
        var idx = 0
        for (i, line) in lyrics.enumerated() where line.timeMs <= ms { idx = i }
        currentLyricIndex = idx
    }

    private func formatTime(_ s: Double) -> String {
        let total = Int(s)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// LRC 歌词解析
enum LRCParser {
    static func parse(_ text: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let pattern = #"\[(\d{2}):(\d{2})(?:\.(\d{1,3}))?\](.*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        for line in text.split(separator: "\n") {
            let s = String(line)
            let ns = s as NSString
            guard let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { continue }
            let min = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let sec = Int(ns.substring(with: m.range(at: 2))) ?? 0
            let frac = m.range(at: 3).location != NSNotFound ? ns.substring(with: m.range(at: 3)) : "0"
            let ms = Int(frac.padding(toLength: 3, withPad: "0", startingAt: 0)) ?? 0
            let content = ns.substring(with: m.range(at: 4)).trimmingCharacters(in: .whitespaces)
            if !content.isEmpty {
                lines.append(LyricLine(timeMs: Int64(min * 60_000 + sec * 1000 + ms), text: content))
            }
        }
        return lines.sorted { $0.timeMs < $1.timeMs }
    }
}

/// 播放队列
struct QueueView: View {
    let tracks: [MusicTrack]
    @Binding var currentIndex: Int
    let onPick: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach(tracks.indices, id: \.self) { idx in
                    Button {
                        onPick(idx); dismiss()
                    } label: {
                        HStack {
                            Image(systemName: currentIndex == idx ? "music.note.list" : "music.note")
                                .foregroundStyle(currentIndex == idx ? AppTheme.accent() : .secondary)
                            VStack(alignment: .leading) {
                                Text(tracks[idx].title).foregroundStyle(currentIndex == idx ? AppTheme.accent() : .primary)
                                Text(tracks[idx].artist).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("播放队列 (\(tracks.count) 首)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}
