import SwiftUI

/// 记录页（对应 RecordsPage：历史 + 收藏）
struct RecordsPage: View {
    @StateObject private var vm = LibraryViewModel()
    @State private var mode = 0  // 0=历史 1=收藏
    @State private var selected: VodInfo? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $mode) {
                    Text("历史").tag(0)
                    Text("收藏").tag(1)
                }.pickerStyle(.segmented).padding()

                if mode == 0 {
                    if vm.history.isEmpty {
                        ContentUnavailableView {
                            Label(vm.incognito ? "无痕模式：不显示观看记录" : "暂无观看历史", systemImage: "clock")
                        }
                    } else {
                        List {
                            ForEach(vm.history) { item in
                                HistoryRow(info: item).onTapGesture { selected = item }
                            }
                            .onDelete { vm.removeHistory(at: $0) }
                        }
                    }
                } else {
                    if vm.collect.isEmpty {
                        ContentUnavailableView { Label("暂无收藏", systemImage: "heart") }
                    } else {
                        List {
                            ForEach(vm.collect) { item in
                                HistoryRow(info: item).onTapGesture { selected = item }
                            }
                            .onDelete { vm.removeCollect(at: $0) }
                        }
                    }
                }
            }
            .navigationTitle("记录")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("清空历史", role: .destructive) { vm.clearHistory() }
                        Button("清空收藏", role: .destructive) { vm.clearCollect() }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .navigationDestination(item: $selected) { info in
                DetailView(video: MovieVideo(
                    id: info.id, name: info.name, pic: info.pic,
                    type: info.type, year: info.year, sourceKey: info.sourceKey
                ))
            }
        }
        .onAppear { vm.load() }
    }
}

struct HistoryRow: View {
    let info: VodInfo
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: info.pic)) { phase in
                if let img = phase.image { img.resizable().scaledToFill() }
                else { Color.gray.opacity(0.25).overlay(Image(systemName: "film")) }
            }
            .frame(width: 56, height: 76).cornerRadius(6).clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(info.name).font(.subheadline).lineLimit(1)
                Text(info.note.isEmpty ? info.subtitle : info.note)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !info.playNote.isEmpty {
                    Text("看到 \(info.playNote)").font(.caption2).foregroundStyle(AppTheme.accent())
                }
                Text(timeAgo(info.updateTime)).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func timeAgo(_ ms: Double) -> String {
        guard ms > 0 else { return "" }
        let sec = Date().timeIntervalSince1970 - ms / 1000
        if sec < 60 { return "刚刚" }
        if sec < 3600 { return "\(Int(sec / 60)) 分钟前" }
        if sec < 86400 { return "\(Int(sec / 3600)) 小时前" }
        if sec < 2_592_000 { return "\(Int(sec / 86400)) 天前" }
        return "\(Int(sec / 2_592_000)) 个月前"
    }
}
