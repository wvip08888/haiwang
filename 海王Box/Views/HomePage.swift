import SwiftUI

/// 首页（对应 HomePage + HomeGridLayout）
struct HomePage: View {
    @StateObject private var vm = HomeViewModel()
    @StateObject private var config = ConfigService.shared
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var showConfig = false
    @State private var selectedVideo: MovieVideo? = nil
    @State private var showFilter = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶栏
                HStack(spacing: 12) {
                    Text("海王Box").font(.title2.bold()).foregroundStyle(AppTheme.accent())
                    Spacer()
                    Button { showLive() } label: {
                        Image(systemName: "tv.fill").font(.title3)
                    }
                    Button { showSearch = true } label: {
                        Image(systemName: "magnifyingglass").font(.title3)
                    }
                    Button { showConfig = true } label: {
                        Image(systemName: "gearshape").font(.title3)
                    }
                }
                .padding(.horizontal).padding(.vertical, 8)

                // 分类 Tab（对应 HomeSortTabRow）
                if !vm.categories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(vm.categories) { cat in
                                Button {
                                    Task { await vm.loadCategory(cat) }
                                } label: {
                                    Text(cat.name)
                                        .font(.subheadline.weight(vm.selectedCategory?.id == cat.id ? .bold : .regular))
                                        .foregroundStyle(vm.selectedCategory?.id == cat.id ? AppTheme.accent() : .primary)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 6)
                }

                // 筛选 Chips
                if let cat = vm.selectedCategory, !cat.filters.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(cat.filters) { filter in
                                Menu {
                                    ForEach(Array(filter.values.keys.sorted()), id: \.self) { key in
                                        Button(key) {
                                            var updated = cat
                                            updated.selectedFilters[filter.key] = filter.values[key]
                                            Task { await vm.loadCategory(updated, filters: updated.selectedFilters) }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(filter.selectedValue(cat.selectedFilters) ?? filter.name)
                                        Image(systemName: "chevron.down")
                                    }
                                    .font(.caption).padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // 内容网格
                if vm.isLoading && vm.videos.isEmpty {
                    ProgressView("加载中…").frame(maxHeight: .infinity)
                } else if let err = vm.errorMessage {
                    ContentUnavailableView {
                        Label("加载失败", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(err)
                    } actions: {
                        Button("重试") { Task { await vm.loadHome() } }
                        Button("配置订阅源") { showConfig = true }
                    }
                } else if vm.videos.isEmpty {
                    ContentUnavailableView {
                        Label("暂无内容", systemImage: "tv")
                    } description: {
                        Text("尚未配置订阅接口")
                    } actions: {
                        Button("去配置") { showConfig = true }
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 16) {
                            ForEach(vm.videos) { video in
                                VodCard(video: video).onTapGesture { selectedVideo = video }
                            }
                        }
                        .padding()
                        if vm.hasMore {
                            Button { Task { await vm.loadMore() } } label: {
                                HStack { ProgressView(); Text("加载中…") }
                            }.padding()
                        }
                    }
                    .refreshable { await vm.loadHome() }
                }
            }
            .navigationDestination(item: $selectedVideo) { video in
                DetailView(video: video)
            }
        }
        .sheet(isPresented: $showSearch) { SearchView() }
        .sheet(isPresented: $showConfig) { ConfigManageView() }
        .task { await vm.loadHome() }
    }

    private func showLive() {
        NotificationCenter.default.post(name: .openLive, object: nil)
    }
}

extension SortFilter {
    func selectedValue(_ selected: [String: String]) -> String? {
        guard let v = selected[key] else { return nil }
        return values.first { $0.value == v }?.key
    }
}

/// 影片卡片
struct VodCard: View {
    let video: MovieVideo
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: URL(string: video.pic)) { phase in
                if let img = phase.image { img.resizable().scaledToFill() }
                else { ZStack { Color.gray.opacity(0.25); ProgressView() } }
            }
            .frame(width: 110, height: 150)
            .cornerRadius(10).clipped()
            .overlay(alignment: .bottomLeading) {
                if !video.note.isEmpty {
                    Text(video.note).font(.caption2).foregroundStyle(.white)
                        .padding(4).background(.black.opacity(0.6), in: Capsule())
                        .padding(5)
                }
            }
            Text(video.name).font(.caption).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
