import SwiftUI

/// 下载管理页（iOS 版新增功能）
struct DownloadView: View {
    @ObservedObject var downloads = DownloadService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirm = false
    @StateObject private var audio = AudioPlaybackService.shared

    var body: some View {
        NavigationStack {
            Group {
                if downloads.items.isEmpty {
                    ContentUnavailableView {
                        Label("暂无下载", systemImage: "arrow.down.circle")
                    } description: {
                        Text("在歌曲列表或播放页点击下载按钮，即可把音乐保存到本地离线播放")
                    }
                } else {
                    List {
                        Section {
                            HStack {
                                Label("下载中", systemImage: "arrow.down.circle")
                                Spacer()
                                Text("\(downloads.items.filter { $0.status == .downloading || $0.status == .waiting }.count)")
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Label("已完成", systemImage: "checkmark.circle.fill")
                                Spacer()
                                Text("\(downloads.items.filter { $0.status == .completed }.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Section("全部下载") {
                            ForEach(downloads.items) { item in
                                DownloadRow(item: item) {
                                    playDownloaded(item)
                                } onToggle: {
                                    downloads.togglePause(item)
                                } onDelete: {
                                    downloads.remove(item)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("我的下载")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("清空") { showClearConfirm = true }.disabled(downloads.items.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("清空下载", isPresented: $showClearConfirm) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) { downloads.removeAll() }
            } message: {
                Text("将删除所有已下载的音乐文件，此操作不可恢复")
            }
        }
    }

    private func playDownloaded(_ item: DownloadItem) {
        guard item.status == .completed else { return }
        let track = MusicTrack(
            id: item.id, title: item.title, artist: item.artist,
            coverUrl: item.coverUrl, playUrl: item.sourceUrl
        )
        audio.play(tracks: [track], at: 0, preferLocal: true)
    }
}

struct DownloadRow: View {
    let item: DownloadItem
    let onPlay: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: item.coverUrl)) { phase in
                if let img = phase.image { img.resizable().scaledToFill() }
                else { Color.gray.opacity(0.25).overlay(Image(systemName: "music.note")) }
            }
            .frame(width: 48, height: 48).cornerRadius(8).clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline).lineLimit(1)
                Text(item.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)

                switch item.status {
                case .downloading, .waiting:
                    ProgressView(value: item.progress).tint(AppTheme.accent())
                    Text("下载中 \(Int(item.progress * 100))%").font(.caption2).foregroundStyle(.secondary)
                case .completed:
                    Label("已完成 · 可离线播放", systemImage: "checkmark.circle.fill")
                        .font(.caption2).foregroundStyle(.green)
                case .failed:
                    Text("失败：\(item.errorText)").font(.caption2).foregroundStyle(.red).lineLimit(2)
                case .paused:
                    Text("已暂停").font(.caption2).foregroundStyle(.orange)
                }
            }

            Spacer()

            if item.status == .completed {
                Button(action: onPlay) { Image(systemName: "play.circle.fill").font(.title2) }
            } else if item.status == .downloading || item.status == .waiting || item.status == .paused {
                Button(action: onToggle) {
                    Image(systemName: item.status == .paused ? "play.circle" : "pause.circle")
                }
            } else {
                Button(action: onToggle) { Image(systemName: "arrow.clockwise") }
            }
            Button(action: onDelete) { Image(systemName: "trash").foregroundStyle(.red) }
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
    }
}
