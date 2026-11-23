import SwiftUI

/// 音乐发现页（对应 MusicPage）
struct MusicPage: View {
    @StateObject private var vm = MusicViewModel()
    @StateObject private var audio = AudioPlaybackService.shared
    @StateObject private var downloads = DownloadService.shared
    @State private var searchText = ""
    @State private var showSearchResults = false
    @State private var showSettings = false
    @State private var showFavorites = false
    @State private var showDownloads = false
    @State private var selectedRank: MusicRank? = nil
    @State private var selectedPlaylist: MusicPlaylist? = nil

    var body: some View {
        NavigationStack {
            Group {
                if !vm.hasSources && vm.ranks.isEmpty {
                    noSourceView
                } else {
                    ScrollView {
                        // 搜索框
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("搜索歌曲、歌手", text: $searchText)
                                .onSubmit { performSearch() }
                            if !searchText.isEmpty {
                                Button { searchText = ""; showSearchResults = false; Task { await vm.search("") } } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(10).background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)

                        if showSearchResults {
                            searchResultsView
                        } else {
                            discoverView
                        }
                    }
                    .refreshable { await vm.refresh() }
                }
            }
            .navigationTitle("音乐")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showDownloads = true } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                    Button { showFavorites = true } label: { Image(systemName: "heart") }
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) { MusicSettingsView() }
            .sheet(isPresented: $showFavorites) { MusicFavoritesView() }
            .sheet(isPresented: $showDownloads) { DownloadView() }
            .navigationDestination(item: $selectedRank) { rank in
                MusicCollectionView(id: rank.id, title: rank.name, coverUrl: rank.coverUrl)
            }
            .navigationDestination(item: $selectedPlaylist) { pl in
                MusicCollectionView(id: pl.id, title: pl.name, coverUrl: pl.coverUrl)
            }
        }
        .task { await vm.load() }
        .onChange(of: searchText) { new in
            if new.isEmpty { showSearchResults = false }
        }
    }

    private var discoverView: some View {
        VStack(alignment: .leading, spacing: 24) {
            // 快捷入口
            HStack(spacing: 12) {
                QuickEntry(icon: "arrow.down.circle.fill", title: "我的下载", color: .blue) { showDownloads = true }
                QuickEntry(icon: "heart.fill", title: "我的收藏", color: .pink) { showFavorites = true }
                QuickEntry(icon: "music.note.list", title: "播放队列", color: .purple) {
                    if !audio.tracks.isEmpty { audio.objectWillChange.send() }
                }
            }.padding(.horizontal)

            if vm.isLoading {
                HStack { ProgressView(); Text("加载中…").foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding()
            }

            // 排行榜
            if !vm.ranks.isEmpty {
                VStack(alignment: .leading) {
                    SectionHeader(title: "排行榜", systemImage: "chart.bar.fill")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(vm.ranks) { rank in
                                Button { selectedRank = rank } label: {
                                    VStack {
                                        RankCover(name: rank.name, index: vm.ranks.firstIndex(where: { $0.id == rank.id }) ?? 0)
                                        Text(rank.name).font(.caption).lineLimit(1)
                                        Text(rank.sourceName).font(.caption2).foregroundStyle(.secondary)
                                    }.frame(width: 100)
                                }
                            }
                        }.padding(.horizontal)
                    }
                }
            }

            // 推荐歌单
            if !vm.playlists.isEmpty {
                VStack(alignment: .leading) {
                    SectionHeader(title: "推荐歌单", systemImage: "square.grid.2x2.fill")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(vm.playlists) { pl in
                            Button { selectedPlaylist = pl } label: {
                                VStack(alignment: .leading) {
                                    AsyncImage(url: URL(string: pl.coverUrl)) { phase in
                                        if let img = phase.image { img.resizable().scaledToFill() }
                                        else { Color.gray.opacity(0.25).overlay(Image(systemName: "music.note")) }
                                    }
                                    .frame(height: 130).frame(maxWidth: .infinity).cornerRadius(10).clipped()
                                    Text(pl.name).font(.subheadline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(pl.sourceName).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }.padding(.horizontal)
                }
            }
        }
        .padding(.top)
    }

    private var searchResultsView: some View {
        LazyVStack(spacing: 0) {
            HStack {
                Text("搜索结果 · \(vm.searchResults.count) 首").font(.headline)
                Spacer()
                if vm.isSearching { ProgressView() }
            }.padding()

            ForEach(vm.searchResults) { track in
                TrackRow(track: track) {
                    vm.play(tracks: vm.searchResults, at: vm.searchResults.firstIndex(where: { $0.id == track.id }) ?? 0)
                } onFavorite: {
                    vm.toggleFavorite(track)
                } onDownload: {
                    Task { await downloadTrack(track) }
                }
            }
        }
    }

    private var noSourceView: some View {
        ContentUnavailableView {
            Label("暂无音乐音源", systemImage: "music.note")
        } description: {
            Text("内置网易云公开接口可用；也可在设置中导入自定义音源")
        } actions: {
            Button("音源设置") { showSettings = true }
        }
    }

    private func performSearch() {
        guard !searchText.isEmpty else { return }
        showSearchResults = true
        Task { await vm.search(searchText) }
    }

    private func downloadTrack(_ track: MusicTrack) async {
        var t = track
        if t.playUrl.isEmpty {
            let resolved = await MusicRepository.shared.resolvePlayURL(t)
            t.playUrl = resolved
        }
        DownloadService.shared.download(t)
    }
}

// MARK: - 组件
struct QuickEntry: View {
    let icon: String, title: String, color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title2).foregroundStyle(color)
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }
}

struct SectionHeader: View {
    let title: String, systemImage: String
    var body: some View {
        HStack {
            Label(title, systemImage: systemImage).font(.headline)
            Spacer()
        }.padding(.horizontal)
    }
}

struct RankCover: View {
    let name: String, index: Int
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [.blue.opacity(0.7), .purple.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading) {
                Spacer()
                Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.white.opacity(0.7))
                Text(name).font(.caption.bold()).foregroundStyle(.white).lineLimit(2).padding(8)
            }
            Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.white)
                .padding(6).background(.black.opacity(0.3), in: Circle()).padding(6)
        }
        .frame(width: 100, height: 110).cornerRadius(12).clipped()
    }
}

/// 歌曲行（含下载按钮）
struct TrackRow: View {
    let track: MusicTrack
    let onPlay: () -> Void
    let onFavorite: () -> Void
    let onDownload: () -> Void
    @ObservedObject var downloads = DownloadService.shared
    @State private var showAction = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                AsyncImage(url: URL(string: track.coverUrl)) { phase in
                    if let img = phase.image { img.resizable().scaledToFill() }
                    else { Color.gray.opacity(0.25).overlay(Image(systemName: "music.note")) }
                }
                .frame(width: 50, height: 50).cornerRadius(8).clipped()
            }
            Button(action: onPlay) {
                VStack(alignment: .leading) {
                    Text(track.title).font(.subheadline).lineLimit(1)
                    Text(track.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }.foregroundStyle(.primary)
            Spacer()
            if let item = downloads.item(for: track), item.status == .completed {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green)
            }
            Button(action: onDownload) {
                Image(systemName: "arrow.down.to.line").foregroundStyle(AppTheme.accent())
            }
            Button(action: onFavorite) {
                Image(systemName: "heart").foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal).padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
