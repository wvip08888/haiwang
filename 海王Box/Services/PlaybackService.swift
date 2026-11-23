import Foundation
import AVFoundation
import Combine

/// 音频播放服务（对应安卓 MusicPlaybackController / MusicPlaybackService）
final class AudioPlaybackService: ObservableObject {
    static let shared = AudioPlaybackService()

    @Published var tracks: [MusicTrack] = []
    @Published var currentIndex: Int = 0
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var playMode: MusicPlayMode = StorageService.shared.musicPlayMode
    @Published var useLocalDownload: Bool = false

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?

    var currentTrack: MusicTrack? { tracks.indices.contains(currentIndex) ? tracks[currentIndex] : nil }

    // MARK: - 队列控制
    func play(tracks: [MusicTrack], at index: Int, preferLocal: Bool = false) {
        self.tracks = tracks
        self.currentIndex = min(max(index, 0), tracks.count - 1)
        self.useLocalDownload = preferLocal
        loadAndPlay()
    }

    func togglePlay() {
        guard let player = player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    func seek(to seconds: Double) {
        guard let player = player else { return }
        let time = CMTime(value: Int64(seconds * 1_000_000), timescale: 1_000_000)
        player.seek(to: time)
        currentTime = seconds
    }

    func next() {
        guard !tracks.isEmpty else { return }
        switch playMode {
        case .single:
            loadAndPlay()
        case .list, .order:
            if currentIndex < tracks.count - 1 {
                currentIndex += 1; loadAndPlay()
            } else if playMode == .list {
                currentIndex = 0; loadAndPlay()
            }
        }
    }

    func previous() {
        guard !tracks.isEmpty else { return }
        if currentTime > 3 { seek(to: 0); return }
        if currentIndex > 0 { currentIndex -= 1; loadAndPlay() }
    }

    func setPlayMode(_ mode: MusicPlayMode) {
        playMode = mode
        StorageService.shared.musicPlayMode = mode
    }

    func stop() {
        player?.pause()
        player = nil
        isPlaying = false
        cleanupObservers()
    }

    // MARK: - 加载与播放
    private func loadAndPlay() {
        guard let track = currentTrack else { return }
        cleanupObservers()

        Task { @MainActor in
            // 优先使用本地下载
            var urlString = ""
            if useLocalDownload, let local = DownloadService.shared.localPlayURL(for: track) {
                urlString = local.absoluteString
            }
            if urlString.isEmpty && !track.playUrl.isEmpty {
                urlString = track.playUrl
            }
            if urlString.isEmpty {
                urlString = await MusicRepository.shared.resolvePlayURL(track)
                if var updated = currentTrack {
                    updated.playUrl = urlString
                    tracks[currentIndex] = updated
                }
            }
            guard let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? urlString) else {
                return
            }

            let item = AVPlayerItem(url: url)
            let newPlayer = AVPlayer(playerItem: item)
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = newPlayer

            statusObserver = item.observe(\.status) { [weak self] it, _ in
                DispatchQueue.main.async {
                    if it.status == .readyToPlay {
                        self?.duration = it.duration.seconds.isFinite ? it.duration.seconds : 0
                        newPlayer.play()
                        self?.isPlaying = true
                    } else if it.status == .failed {
                        self?.isPlaying = false
                    }
                }
            }

            timeObserver = newPlayer.addPeriodicTimeObserver(
                forInterval: CMTime(value: 1, timescale: 4), queue: .main
            ) { [weak self] time in
                self?.currentTime = time.seconds
            }

            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async { self?.next() }
            }

            newPlayer.play()
            isPlaying = true
        }
    }

    private func cleanupObservers() {
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        timeObserver = nil
        statusObserver = nil
    }
}
