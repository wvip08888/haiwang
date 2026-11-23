import SwiftUI
import UniformTypeIdentifiers

/// 配置管理页（对应 ConfigManageScreen）
struct ConfigManageView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var config = ConfigService.shared
    @State private var showAdd = false
    @State private var newName = ""
    @State private var newURL = ""
    @State private var showPicker = false
    @State private var message: String? = nil
    @State private var showLiveConfig = false

    var body: some View {
        NavigationStack {
            List {
                Section("点播订阅源") {
                    ForEach(config.sources) { src in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(src.name).font(.subheadline)
                                Text(src.api).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if src.id == StorageService.shared.activeSourceKey {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.accent())
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { StorageService.shared.activeSourceKey = src.id }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { config.removeSource(src) } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                    if config.sources.isEmpty {
                        Text("未配置点播源").foregroundStyle(.secondary)
                    }
                    Button("添加订阅") { showAdd = true }
                    Button("从本地选择") { showPicker = true }
                }

                Section("直播源") {
                    HStack {
                        Text(StorageService.shared.liveUrl.isEmpty ? "未配置直播源" : "已配置直播源")
                        Spacer()
                        if !StorageService.shared.liveUrl.isEmpty {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    Button("添加直播源 (JSON / m3u / txt)") { showLiveConfig = true }
                }

                Section {
                    Text("支持配置 JSON / m3u / txt 直播源。软件不预置任何内容，源由用户自行添加。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("配置管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .alert("添加订阅", isPresented: $showAdd) {
                TextField("名字", text: $newName)
                TextField("API 地址", text: $newURL)
                Button("取消", role: .cancel) {}
                Button("添加") { addSubscribe() }
            }
            .alert("添加直播源", isPresented: $showLiveConfig) {
                TextField("直播源地址", text: $newURL)
                Button("取消", role: .cancel) {}
                Button("添加") { addLive() }
            }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: [.json, .text, .plainText]) { result in
                if case .success(let url) = result { importLocalFile(url) }
            }
            .overlay(alignment: .bottom) {
                if let msg = message {
                    Text(msg).font(.caption).padding(10).background(.black.opacity(0.75), in: Capsule())
                        .foregroundStyle(.white).padding(.bottom, 30)
                        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { message = nil } }
                }
            }
        }
    }

    private func addSubscribe() {
        guard !newURL.isEmpty else { return }
        Task {
            let result = await config.fetchConfig(from: newURL)
            switch result {
            case .success(let count): message = "成功导入 \(count) 个源"
            case .failure(let err): message = err
            }
            newName = ""; newURL = ""
        }
    }

    private func addLive() {
        guard !newURL.isEmpty else { return }
        Task {
            let result = await config.fetchConfig(from: newURL)
            switch result {
            case .success: message = "直播源已添加"
            case .failure(let err): message = err
            }
            newURL = ""
        }
    }

    private func importLocalFile(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        if let text = try? String(contentsOf: url) {
            let result = config.parseJSONConfig(text)
            switch result {
            case .success(let count): message = "成功导入 \(count) 个源"
            case .failure(let err): message = err
            }
        }
    }
}
