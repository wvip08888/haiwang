import SwiftUI

/// 设置页（对应 SettingsPage / tab_mine）
struct SettingsPage: View {
    @StateObject private var vm = SettingsViewModel()
    @State private var showConfig = false
    @State private var showTheme = false
    @State private var showPlay = false
    @State private var showPreference = false
    @State private var showTmdb = false
    @State private var showAbout = false
    @State private var showDownload = false

    var body: some View {
        NavigationStack {
            List {
                // 头部卡片
                Section {
                    HStack(spacing: 14) {
                        Image("AppLogo").resizable().frame(width: 56, height: 56).cornerRadius(12)
                        VStack(alignment: .leading) {
                            Text("海王Box").font(.title3.bold())
                            Text("影视直播音乐三合一，超聚能一站播放").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }

                Section("配置") {
                    SettingsRow(icon: "square.stack.3d.up", title: "配置管理", subtitle: "导入或删除订阅源") { showConfig = true }
                    SettingsRow(icon: "paintbrush.fill", title: "主题设置", subtitle: "修改应用的配色和效果") { showTheme = true }
                    SettingsRow(icon: "play.circle", title: "播放设置", subtitle: "播放核心和解码方式") { showPlay = true }
                }

                Section("通用") {
                    SettingsRow(icon: "arrow.down.circle", title: "我的下载", subtitle: "离线音乐管理") { showDownload = true }
                    SettingsRow(icon: "gearshape.2", title: "偏好设置", subtitle: "修改应用的使用偏好") { showPreference = true }
                    SettingsRow(icon: "film", title: "TMDB 配置", subtitle: "海报刮削与元数据") { showTmdb = true }
                    Stepper("历史记录上限：\(vm.historyLimit)条", value: $vm.historyLimit, in: 0...500, step: 10)
                    SettingsRow(icon: "trash", title: "清除缓存", subtitle: vm.cacheSizeText) {
                        vm.clearCache()
                    }
                }

                Section("其他") {
                    SettingsRow(icon: "info.circle", title: "关于", subtitle: "查看详细信息") { showAbout = true }
                    Link(destination: URL(string: "https://7w.lt/HW")!) {
                        SettingsRowContent(icon: "safari", title: "访问官方", subtitle: "https://7w.lt/HW")
                    }
                }
            }
            .navigationTitle("我的")
            .sheet(isPresented: $showConfig) { ConfigManageView() }
            .sheet(isPresented: $showTheme) { ThemeSettingsView() }
            .sheet(isPresented: $showPlay) { PlaySettingsView() }
            .sheet(isPresented: $showPreference) { PreferenceSettingsView() }
            .sheet(isPresented: $showTmdb) { TmdbSettingsView(vm: vm) }
            .sheet(isPresented: $showAbout) { AboutView() }
            .sheet(isPresented: $showDownload) { DownloadView() }
        }
        .onAppear { vm.calcCacheSize() }
    }
}

struct SettingsRow: View {
    let icon: String, title: String, subtitle: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { SettingsRowContent(icon: icon, title: title, subtitle: subtitle) }
            .foregroundStyle(.primary)
    }
}

struct SettingsRowContent: View {
    let icon: String, title: String, subtitle: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(AppTheme.accent()).frame(width: 24)
            VStack(alignment: .leading) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

/// 主题设置
struct ThemeSettingsView: View {
    @EnvironmentObject var theme: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("themeSeed") private var seedName = "蓝色"
    @AppStorage("pureBlack") private var pureBlack = false

    var body: some View {
        NavigationStack {
            List {
                Section("主题模式") {
                    Picker("模式", selection: Binding(
                        get: { theme.mode },
                        set: { theme.setMode($0) }
                    )) {
                        ForEach(ThemeMode.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                    Toggle("纯黑模式", isOn: $pureBlack)
                }
                Section("主题颜色") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))]) {
                        ForEach(AppTheme.seeds, id: \.name) { seed in
                            Button {
                                seedName = seed.name
                            } label: {
                                Circle().fill(seed.color).frame(width: 36, height: 36)
                                    .overlay {
                                        if seedName == seed.name {
                                            Image(systemName: "checkmark").foregroundStyle(.white)
                                        }
                                    }
                            }
                        }
                    }
                }
                Section("应用效果") {
                    Toggle("显示时间", isOn: Binding(
                        get: { StorageService.shared.flag("showTime") },
                        set: { StorageService.shared.setFlag("showTime", $0) }
                    ))
                    Toggle("隐藏状态栏", isOn: Binding(
                        get: { StorageService.shared.flag("hideStatusBar") },
                        set: { StorageService.shared.setFlag("hideStatusBar", $0) }
                    ))
                }
            }
            .navigationTitle("主题设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}

/// 播放设置
struct PlaySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("内核与画面") {
                    Picker("播放器", selection: Binding(
                        get: { UserDefaults.standard.string(forKey: "playerType") ?? "AVPlayer" },
                        set: { UserDefaults.standard.set($0, forKey: "playerType") }
                    )) {
                        Text("AVPlayer").tag("AVPlayer")
                        Text("系统").tag("system")
                    }
                    Toggle("隧道模式", isOn: Binding(
                        get: { StorageService.shared.flag("tunnel") },
                        set: { StorageService.shared.setFlag("tunnel", $0) }
                    ))
                    Toggle("内核预热", isOn: Binding(
                        get: { StorageService.shared.flag("prewarm") },
                        set: { StorageService.shared.setFlag("prewarm", $0) }
                    ))
                }
                Section("播放行为") {
                    Toggle("自动换线", isOn: Binding(
                        get: { StorageService.shared.flag("autoSwitchLine", default: true) },
                        set: { StorageService.shared.setFlag("autoSwitchLine", $0) }
                    ))
                    Toggle("下一集预载", isOn: Binding(
                        get: { StorageService.shared.flag("preloadNext") },
                        set: { StorageService.shared.setFlag("preloadNext", $0) }
                    ))
                    Toggle("弹幕开关", isOn: Binding(
                        get: { StorageService.shared.flag("danmuOn") },
                        set: { StorageService.shared.setFlag("danmuOn", $0) }
                    ))
                }
                Section("画面参数") {
                    Toggle("Anime4K 画质增强", isOn: Binding(
                        get: { StorageService.shared.flag("anime4k") },
                        set: { StorageService.shared.setFlag("anime4k", $0) }
                    ))
                    Text("内置 Anime4K shader 资源，iOS 端通过 Metal 后处理实现")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("播放设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}

/// 偏好设置
struct PreferenceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("隐私与交互") {
                    Toggle("无痕模式", isOn: Binding(
                        get: { StorageService.shared.flag("incognito") },
                        set: { StorageService.shared.setFlag("incognito", $0) }
                    ))
                    Toggle("禁用手势控制", isOn: Binding(
                        get: { StorageService.shared.flag("disableGesture") },
                        set: { StorageService.shared.setFlag("disableGesture", $0) }
                    ))
                    Toggle("隐藏状态栏", isOn: Binding(
                        get: { StorageService.shared.flag("hideStatusBar") },
                        set: { StorageService.shared.setFlag("hideStatusBar", $0) }
                    ))
                    Toggle("禁用导航动画", isOn: Binding(
                        get: { StorageService.shared.flag("navAnimationDisabled") },
                        set: { StorageService.shared.setFlag("navAnimationDisabled", $0) }
                    ))
                }
                Section("播放与搜索") {
                    Toggle("默认启动直播", isOn: Binding(
                        get: { StorageService.shared.flag("defaultLoadLive") },
                        set: { StorageService.shared.setFlag("defaultLoadLive", $0) }
                    ))
                    Toggle("安全 DNS (DoH)", isOn: Binding(
                        get: { StorageService.shared.flag("doh") },
                        set: { StorageService.shared.setFlag("doh", $0) }
                    ))
                    Toggle("M3U8 净化", isOn: Binding(
                        get: { StorageService.shared.flag("m3u8Purify") },
                        set: { StorageService.shared.setFlag("m3u8Purify", $0) }
                    ))
                    Toggle("长按倍速", isOn: Binding(
                        get: { StorageService.shared.flag("longPressSpeed") },
                        set: { StorageService.shared.setFlag("longPressSpeed", $0) }
                    ))
                }
                Section("预载与缓存") {
                    Toggle("边播边缓存", isOn: Binding(
                        get: { StorageService.shared.flag("playCache") },
                        set: { StorageService.shared.setFlag("playCache", $0) }
                    ))
                }
            }
            .navigationTitle("偏好设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}

/// TMDB 设置
struct TmdbSettingsView: View {
    @ObservedObject var vm: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Toggle("启用 TMDB", isOn: Binding(
                    get: { vm.tmdb.enabled },
                    set: { vm.tmdb.enabled = $0; vm.saveTmdb() }
                ))
                Section("海报展示") {
                    Picker("样式", selection: Binding(
                        get: { vm.tmdb.posterStyle },
                        set: { vm.tmdb.posterStyle = $0; vm.saveTmdb() }
                    )) {
                        Text("固定").tag("fixed")
                        Text("随机").tag("random")
                        Text("轮播").tag("roll")
                    }
                }
                Section {
                    TextField("API Key", text: Binding(
                        get: { vm.tmdb.apiKey },
                        set: { vm.tmdb.apiKey = $0; vm.saveTmdb() }
                    ))
                    TextField("API 代理地址", text: Binding(
                        get: { vm.tmdb.apiBase },
                        set: { vm.tmdb.apiBase = $0; vm.saveTmdb() }
                    ))
                    TextField("图片代理地址", text: Binding(
                        get: { vm.tmdb.imageBase },
                        set: { vm.tmdb.imageBase = $0; vm.saveTmdb() }
                    ))
                } footer: {
                    Text("选填，未填则使用默认")
                }
            }
            .navigationTitle("TMDB 配置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}

/// 关于
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Image("AppLogo").resizable().frame(width: 80, height: 80).cornerRadius(16)
                    Text("海王Box").font(.title.bold())
                    Text("版本 v1.0.0").font(.subheadline).foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("影视直播音乐三合一，超聚能一站播放\n更多精彩关注vx\"海王影视\"")
                            .font(.subheadline)
                        Divider()
                        Text("本软件只供聚合展示功能，所有资源来源于互联网，软件不参与任何制作、上传、存储、下载等内容！软件仅供学习，请于安装24小时内删除。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding().background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }.padding()
            }
            .navigationTitle("关于").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}
