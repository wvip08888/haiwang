import SwiftUI

/// 详情页（对应 DetailActivity）
struct DetailView: View {
    let video: MovieVideo
    @StateObject private var vm = HomeViewModel()
    @State private var info: VodInfo? = nil
    @State private var loading = true
    @State private var selectedFlag: String = ""
    @State private var selectedEpisode: MovieVideo.Episode? = nil
    @State private var playing = false
    @State private var descExpanded = false
    @StateObject private var library = LibraryViewModel()

    var body: some View {
        Group {
            if loading {
                ProgressView("寻找片源中…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let info = info {
                detailContent(info)
            } else {
                ContentUnavailableView {
                    Label("暂无片源,可尝试换源或搜索", systemImage: "film")
                }
            }
        }
        .navigationTitle(video.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let info = info { library.toggleCollect(info) }
                } label: {
                    Image(systemName: (info.map { library.isCollected($0) } ?? false) ? "heart.fill" : "heart")
                }
            }
        }
        .task { await loadDetail() }
        .fullScreenCover(isPresented: $playing) {
            if let ep = selectedEpisode {
                VideoPlayerView(
                    url: ep.url,
                    title: "\(video.name) · \(ep.name)",
                    episodes: currentEpisodes,
                    currentIndex: currentEpisodes.firstIndex(where: { $0.url == ep.url }) ?? 0,
                    vodInfo: info
                )
            }
        }
    }

    private func detailContent(_ info: VodInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 头部信息
                HStack(alignment: .top, spacing: 14) {
                    AsyncImage(url: URL(string: info.pic.isEmpty ? video.pic : info.pic)) { phase in
                        if let img = phase.image { img.resizable().scaledToFill() }
                        else { Color.gray.opacity(0.3) }
                    }
                    .frame(width: 110, height: 150).cornerRadius(10).clipped()

                    VStack(alignment: .leading, spacing: 6) {
                        Text(info.name).font(.title3.bold())
                        Text(info.subtitle).font(.caption).foregroundStyle(.secondary)
                        Text("来源：\(info.sourceName)").font(.caption2).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button {
                                if let first = currentEpisodes.first {
                                    selectedEpisode = first; playing = true
                                }
                            } label: {
                                Label("播放", systemImage: "play.fill").frame(maxWidth: .infinity)
                            }.buttonStyle(.borderedProminent).tint(AppTheme.accent())
                        }
                    }
                }

                // 简介
                if !info.des.isEmpty {
                    VStack(alignment: .leading) {
                        Text(info.des).font(.subheadline).lineLimit(descExpanded ? nil : 3)
                        Button(descExpanded ? "收起" : "展开") { descExpanded.toggle() }
                            .font(.caption).foregroundStyle(AppTheme.accent())
                    }
                }

                // 线路切换
                if info.seriesFlags.count > 1 {
                    VStack(alignment: .leading) {
                        Text("线路").font(.headline)
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(info.seriesFlags, id: \.self) { flag in
                                    Button(flag) {
                                        selectedFlag = flag
                                        if let first = info.seriesMap[flag]?.first {
                                            selectedEpisode = first
                                        }
                                    }
                                    .font(.caption).padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(selectedFlag == flag ? AppTheme.accent() : Color.secondary.opacity(0.12),
                                                in: Capsule())
                                    .foregroundStyle(selectedFlag == flag ? .white : .primary)
                                }
                            }
                        }
                    }
                }

                // 选集
                if !currentEpisodes.isEmpty {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("\(selectedFlag.isEmpty ? "选集" : "\(selectedFlag) 选集")").font(.headline)
                            Spacer()
                            Button("倒序") {
                                if let flag = currentFlag, let list = info.seriesMap[flag] {
                                    var mutable = info
                                    mutable.seriesMap[flag] = list.reversed()
                                    self.info = mutable
                                }
                            }.font(.caption)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                            ForEach(currentEpisodes, id: \.url) { ep in
                                Button {
                                    selectedEpisode = ep; playing = true
                                } label: {
                                    Text(ep.name).font(.caption).frame(maxWidth: .infinity, minHeight: 34)
                                        .background(selectedEpisode?.url == ep.url ? AppTheme.accent() : Color.secondary.opacity(0.12),
                                                    in: RoundedRectangle(cornerRadius: 8))
                                        .foregroundStyle(selectedEpisode?.url == ep.url ? .white : .primary)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .onAppear { library.load() }
    }

    private var currentFlag: String? {
        if !selectedFlag.isEmpty { return selectedFlag }
        return info?.seriesFlags.first
    }
    private var currentEpisodes: [MovieVideo.Episode] {
        guard let info = info, let flag = currentFlag else { return [] }
        return info.seriesMap[flag] ?? []
    }

    private func loadDetail() async {
        guard let src = ConfigService.shared.activeSource() else { loading = false; return }
        let result = await vm.detail(id: video.id, source: src)
        info = result ?? VodInfo(
            id: video.id, name: video.name, pic: video.pic, des: video.des,
            actor: video.actor, director: video.director, year: video.year,
            area: video.area, type: video.type, sourceKey: video.sourceKey,
            sourceName: src.name, seriesFlags: video.playFlags.map { $0.flag },
            seriesMap: Dictionary(uniqueKeysWithValues: video.playFlags.map { flag in
                (flag.flag, flag.episodes)
            })
        )
        if selectedFlag.isEmpty { selectedFlag = info?.seriesFlags.first ?? "" }
        loading = false
        library.load()
    }
}
