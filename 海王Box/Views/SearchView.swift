import SwiftUI

/// 搜索页（对应 SearchActivity / 搜索设置）
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = HomeViewModel()
    @State private var keyword = ""
    @State private var results: [MovieVideo] = []
    @State private var searching = false
    @State private var selectedVideo: MovieVideo? = nil
    @State private var showSitePicker = false
    @AppStorage("searchSites") private var searchSiteKeys: [String] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    TextField("搜索片名、演员", text: $keyword)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { performSearch() }
                    Button("搜索") { performSearch() }.tint(AppTheme.accent())
                    Button("取消") { dismiss() }
                }
                .padding()

                if let history = UserDefaults.standard.stringArray(forKey: "searchHistory"), !history.isEmpty, keyword.isEmpty {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("搜索历史").font(.headline)
                            Spacer()
                            Button("清空") {
                                UserDefaults.standard.removeObject(forKey: "searchHistory")
                            }.font(.caption)
                        }
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(history, id: \.self) { h in
                                    Button(h) { keyword = h; performSearch() }
                                        .font(.caption).padding(6)
                                        .background(Color.secondary.opacity(0.12), in: Capsule())
                                }
                            }
                        }
                    }.padding(.horizontal)
                }

                if searching {
                    ProgressView("搜索中…").frame(maxHeight: .infinity)
                } else if results.isEmpty && !keyword.isEmpty {
                    ContentUnavailableView {
                        Label("「\(keyword)」暂无搜索结果", systemImage: "magnifyingglass")
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 12) {
                            ForEach(results) { v in
                                VodCard(video: v).onTapGesture { selectedVideo = v }
                            }
                        }.padding()
                    }
                }
            }
            .navigationDestination(item: $selectedVideo) { DetailView(video: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSitePicker = true } label: { Image(systemName: "checklist") }
                }
            }
            .sheet(isPresented: $showSitePicker) {
                SearchSitesView(selected: $searchSiteKeys)
            }
        }
    }

    private func performSearch() {
        guard !keyword.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        var history = UserDefaults.standard.stringArray(forKey: "searchHistory") ?? []
        history.removeAll { $0 == keyword }
        history.insert(keyword, at: 0)
        UserDefaults.standard.set(Array(history.prefix(20)), forKey: "searchHistory")

        searching = true
        Task {
            let allSources = ConfigService.shared.sources.filter { $0.isSearchable }
            let chosen = allSources.filter { searchSiteKeys.isEmpty || searchSiteKeys.contains($0.key.isEmpty ? $0.api : $0.key) }
            let result = await vm.search(keyword: keyword, sources: chosen.isEmpty ? allSources : chosen)
            results = result
            searching = false
        }
    }
}

/// 搜索站点选择
struct SearchSitesView: View {
    @Binding var selected: [String]
    @Environment(\.dismiss) private var dismiss
    @StateObject private var config = ConfigService.shared
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("全选（搜索全部站点）") { selected = [] }
                    ForEach(config.sources.filter { $0.isSearchable }) { src in
                        let key = src.key.isEmpty ? src.api : src.key
                        Button {
                            if selected.contains(key) { selected.removeAll { $0 == key } }
                            else { selected.append(key) }
                        } label: {
                            HStack {
                                Text(src.name)
                                Spacer()
                                if selected.contains(key) || selected.isEmpty {
                                    Image(systemName: "checkmark").foregroundStyle(AppTheme.accent())
                                }
                            }
                        }.foregroundStyle(.primary)
                    }
                } header: {
                    Text(selected.isEmpty ? "已选全部站点" : "已选 \(selected.count) 个站点")
                }
            }
            .navigationTitle("搜索站点").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}
