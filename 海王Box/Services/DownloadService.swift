import Foundation
import Combine

/// 音乐下载服务（iOS 版新增功能）
/// 负责：真实下载音频到本地、进度跟踪、断点记录、本地文件管理。
final class DownloadService: NSObject, ObservableObject {

    static let shared = DownloadService()

    @Published private(set) var items: [DownloadItem] = []
    @Published private(set) var activeCount: Int = 0

    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var progressObservers: [String: NSKeyValueObservation] = [:]
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        return URLSession(configuration: cfg, delegate: self, delegateQueue: .main)
    }()

    /// 下载目录：Documents/Downloads
    static var downloadsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Downloads", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    override init() {
        super.init()
        items = StorageService.shared.downloadItems
        // 将上次未完成的任务标记为失败，避免永久停留在“下载中”
        var changed = false
        for i in items.indices where items[i].status == .downloading || items[i].status == .waiting {
            items[i].status = .failed
            items[i].errorText = "应用重启，下载已中断，可重新下载"
            changed = true
        }
        if changed { persist() }
    }

    // MARK: - 对外接口

    /// 是否已下载
    func isDownloaded(_ track: MusicTrack) -> Bool {
        guard let item = items.first(where: { $0.id == track.favoriteKey }) else { return false }
        return item.status == .completed && item.localURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    func item(for track: MusicTrack) -> DownloadItem? {
        items.first { $0.id == track.favoriteKey }
    }

    /// 开始下载一首歌（ ingenu: 从 playUrl 拉取音频文件）
    func download(_ track: MusicTrack) {
        guard let urlEncoded = track.playUrl.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
              let url = URL(string: urlEncoded), url.scheme?.hasPrefix("http") == true else {
            updateItem(id: track.favoriteKey, status: .failed, error: "无效的下载地址，请先解析播放地址")
            return
        }

        let id = track.favoriteKey
        let ext = Self.guessExtension(from: track.playUrl) ?? ".mp3"
        let fileName = Self.safeFileName("\(track.title) - \(track.artist)") + ext

        // 已下载则不重复下载
        if let existing = item(for: track), existing.status == .completed {
            if let local = existing.localURL, FileManager.default.fileExists(atPath: local.path) { return }
        }

        var item = DownloadItem(
            id: id,
            title: track.title.isEmpty ? "未知歌曲" : track.title,
            artist: track.artist,
            coverUrl: track.coverUrl,
            sourceUrl: track.playUrl,
            fileName: fileName,
            progress: 0,
            status: .waiting
        )
        upsert(item)
        item = items.first { $0.id == id }!

        let request = URLRequest(url: url)
        let task = session.downloadTask(with: request)
        task.taskDescription = id
        tasks[id] = task

        // KVO 监听写入进度
        let observer = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.updateItem(id: id, status: .downloading, progress: progress.fractionCompleted)
            }
        }
        progressObservers[id] = observer

        updateItem(id: id, status: .downloading)
        task.resume()
        recalcActive()
    }

    /// 暂停 / 恢复
    func togglePause(_ item: DownloadItem) {
        if let task = tasks[item.id], task.state == .running {
            task.suspend()
            updateItem(id: item.id, status: .paused)
        } else if let task = tasks[item.id], task.state == .suspended {
            task.resume()
            updateItem(id: item.id, status: .downloading)
        } else if item.status == .failed {
            // 失败后重新下载：重新构造一个临时 track
            let track = MusicTrack(
                id: item.id, title: item.title, artist: item.artist,
                coverUrl: item.coverUrl, playUrl: item.sourceUrl
            )
            tasks.removeValue(forKey: item.id)
            download(track)
        }
        recalcActive()
    }

    /// 删除下载（同时删除本地文件）
    func remove(_ item: DownloadItem) {
        tasks[item.id]?.cancel()
        tasks.removeValue(forKey: item.id)
        progressObservers.removeValue(forKey: item.id)
        if let local = item.localURL, FileManager.default.fileExists(atPath: local.path) {
            try? FileManager.default.removeItem(at: local)
        }
        items.removeAll { $0.id == item.id }
        persist()
        recalcActive()
    }

    /// 清空全部下载
    func removeAll() {
        let all = items
        for item in all { remove(item) }
    }

    /// 已下载歌曲的本地播放地址
    func localPlayURL(for track: MusicTrack) -> URL? {
        guard isDownloaded(track) else { return nil }
        return item(for: track)?.localURL
    }

    // MARK: - 内部辅助

    private func upsert(_ item: DownloadItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item
        } else {
            items.insert(item, at: 0)
        }
        persist()
    }

    private func updateItem(id: String, status: DownloadStatus? = nil, progress: Double? = nil, error: String? = nil) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        if let s = status { items[idx].status = s }
        if let p = progress { items[idx].progress = min(max(p, 0), 1) }
        if let e = error { items[idx].errorText = e }
        persist()
    }

    private func persist() {
        StorageService.shared.downloadItems = items
    }

    private func recalcActive() {
        activeCount = tasks.values.filter { $0.state == .running }.count
    }

    private static func guessExtension(from url: String) -> String? {
        let path = url.components(separatedBy: "?").first ?? url
        let ext = (path as NSString).pathExtension.lowercased()
        if ["mp3", "m4a", "aac", "flac", "wav", "ogg", "opus", "mp4"].contains(ext) {
            return "." + ext
        }
        return ".mp3"
    }

    private static func safeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        var result = name.components(separatedBy: invalid).joined(separator: "_")
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty { result = "music_\(Int(Date().timeIntervalSince1970))" }
        if result.count > 120 { result = String(result.prefix(120)) }
        return result
    }
}

// MARK: - URLSessionDownloadDelegate
extension DownloadService: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        guard let item = items.first(where: { $0.id == id }) else { return }
        let dest = Self.downloadsDirectory.appendingPathComponent(item.fileName)

        // 若同名文件已存在则先移除
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            DispatchQueue.main.async {
                self.updateItem(id: id, status: .completed, progress: 1)
                self.cleanup(id: id)
                self.recalcActive()
            }
        } catch {
            DispatchQueue.main.async {
                self.updateItem(id: id, status: .failed, error: "保存失败：\(error.localizedDescription)")
                self.cleanup(id: id)
                self.recalcActive()
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let error = error, let id = task.taskDescription else { return }
        // 主动取消不标记为失败
        if (error as NSError).code == NSURLErrorCancelled { return }
        DispatchQueue.main.async {
            self.updateItem(id: id, status: .failed, error: error.localizedDescription)
            self.cleanup(id: id)
            self.recalcActive()
        }
    }

    private func cleanup(id: String) {
        progressObservers.removeValue(forKey: id)
        tasks.removeValue(forKey: id)
    }
}
