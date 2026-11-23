import SwiftUI
import AVKit

/// 直播播放页（对应 LivePlayActivity）
struct LivePlayView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var groups: [LiveChannelGroup] = []
    @State private var channels: [LiveChannel] = []
    @State private var selectedChannel: LiveChannel? = nil
    @State private var showChannelList = false
    @State private var showEPG = false
    @State private var showControls = false
    @State private var player: AVPlayer? = nil
    @State private var lineIndex = 0
    @State private var epg: [EpgProgram] = []
    @State private var password = ""
    @State private var showPassword = false
    @State private var pendingGroup: LiveChannelGroup? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let channel = selectedChannel, !channel.urls.isEmpty {
                if let player = player {
                    VideoPlayer(player: player).ignoresSafeArea()
                        .onTapGesture { withAnimation { showControls.toggle() } }
                }
            } else {
                VStack {
                    Image(systemName: "tv").font(.largeTitle).foregroundStyle(.gray)
                    Text("请先选择频道").foregroundStyle(.gray)
                }
            }

            if showControls {
                VStack {
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "chevron.left").font(.title2).foregroundStyle(.white) }
                        Spacer()
                        Text(selectedChannel?.name ?? "直播").foregroundStyle(.white)
                        Spacer()
                        Button { showEPG = true } label: { Image(systemName: "calendar").foregroundStyle(.white) }
                    }.padding()
                    Spacer()
                    HStack(spacing: 40) {
                        Button { showChannelList = true } label: { Label("频道", systemImage: "list.bullet").foregroundStyle(.white) }
                        Button { switchLine() } label: { Label("线路", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.white) }
                        Button { showEPG = true } label: { Label("节目单", systemImage: "calendar").foregroundStyle(.white) }
                    }.padding().background(.black.opacity(0.5))
                }.transition(.opacity)
            }
        }
        .statusBar(hidden: true)
        .sheet(isPresented: $showChannelList) {
            ChannelListView(groups: groups, selected: $selectedChannel) { ch in
                selectedChannel = ch; lineIndex = 0; setupPlayer()
            }
        }
        .sheet(isPresented: $showEPG) {
            EPGView(programs: epg, channelName: selectedChannel?.name ?? "")
        }
        .alert("频道分组密码", isPresented: $showPassword) {
            TextField("密码", text: $password)
            Button("取消", role: .cancel) {}
            Button("确定") {
                if let g = pendingGroup, password == g.password {
                    channels = g.channels
                }
                password = ""
            }
        }
        .task { await loadLive() }
    }

    private func loadLive() async {
        let url = StorageService.shared.liveUrl
        guard !url.isEmpty, let text = await NetworkService.getText(url) else {
            // 无直播源：允许用户在设置中配置
            return
        }
        let parsed = LiveParser.parse(text)
        groups = parsed
        channels = parsed.first?.channels ?? []
        if let first = channels.first { selectedChannel = first; setupPlayer() }
        // EPG
        if let epgText = try? String(contentsOf: Bundle.main.url(forResource: "epg_data", withExtension: "json")!, encoding: .utf8) {
            epg = LiveParser.parseEPG(epgText, channel: selectedChannel?.name ?? "")
        }
    }

    private func setupPlayer() {
        guard let ch = selectedChannel, ch.urls.indices.contains(lineIndex),
              let u = URL(string: ch.urls[lineIndex]) else { return }
        var req = URLRequest(url: u)
        if !ch.ua.isEmpty { req.setValue(ch.ua, forHTTPHeaderField: "User-Agent") }
        if !ch.referer.isEmpty { req.setValue(ch.referer, forHTTPHeaderField: "Referer") }
        player = AVPlayer(url: u)
        player?.play()
    }

    private func switchLine() {
        guard let ch = selectedChannel, !ch.urls.isEmpty else { return }
        lineIndex = (lineIndex + 1) % ch.urls.count
        setupPlayer()
    }
}

/// 频道列表
struct ChannelListView: View {
    let groups: [LiveChannelGroup]
    @Binding var selected: LiveChannel?
    let onPick: (LiveChannel) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach(groups) { group in
                    Section(group.name) {
                        ForEach(group.channels) { ch in
                            Button {
                                onPick(ch); dismiss()
                            } label: {
                                HStack {
                                    Text(ch.name)
                                    Spacer()
                                    if selected?.name == ch.name {
                                        Image(systemName: "checkmark").foregroundStyle(AppTheme.accent())
                                    }
                                }
                            }.foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("频道列表").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}

/// 节目单
struct EPGView: View {
    let programs: [EpgProgram]
    let channelName: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if programs.isEmpty {
                    ContentUnavailableView { Label("暂无节目单", systemImage: "calendar") }
                } else {
                    List(programs) { p in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(p.title).font(.subheadline)
                                Text("\(p.start) - \(p.end)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("节目单 · \(channelName)").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}

/// 直播配置解析（m3u / txt / json）
enum LiveParser {
    static func parse(_ text: String) -> [LiveChannelGroup] {
        var groups: [String: [LiveChannel]] = [:]
        if text.hasPrefix("#EXTM3U") || text.contains("#EXTINF") {
            var currentName = ""
            for line in text.split(separator: "\n") {
                let l = line.trimmingCharacters(in: .whitespaces)
                if l.hasPrefix("#EXTINF") {
                    if let comma = l.lastIndex(of: ",") {
                        currentName = String(l[l.index(after: comma)...])
                    }
                } else if l.hasPrefix("http"), !currentName.isEmpty {
                    let ch = LiveChannel(name: currentName, urls: [l])
                    let groupName = extractGroup(from: l) ?? "默认"
                    groups[groupName, default: []].append(ch)
                    currentName = ""
                }
            }
        } else if let data = text.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) {
            parseJSON(obj, into: &groups)
        }
        return groups.map { LiveChannelGroup(name: $0.key, channels: $0.value) }
            .sorted { $0.name < $1.name }
    }

    private static func parseJSON(_ obj: Any, into groups: inout [String: [LiveChannel]]) {
        guard let arr = obj as? [[String: Any]] else {
            if let dict = obj as? [String: Any] {
                for value in dict.values { parseJSON(value, into: &groups) }
            }
            return
        }
        for d in arr {
            let name = d["name"] as? String ?? d["title"] as? String ?? ""
            var urls: [String] = []
            if let s = d["url"] as? String { urls.append(s) }
            if let a = d["urls"] as? [String] { urls += a }
            if let channel = d["channel"] as? String { urls.append(channel) }
            if !name.isEmpty && !urls.isEmpty {
                let group = d["group"] as? String ?? "默认"
                groups[group, default: []].append(LiveChannel(name: name, urls: urls))
            }
        }
    }

    private static func extractGroup(from url: String) -> String? {
        guard let components = URLComponents(string: url),
              let group = components.queryItems?.first(where: { $0.name.lowercased() == "group" })?.value else { return nil }
        return group
    }

    static func parseEPG(_ text: String, channel: String) -> [EpgProgram] {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let arr = obj[channel] as? [[String: Any]] ?? obj["list"] as? [[String: Any]] ?? []
        return arr.map { d in
            EpgProgram(
                title: d["title"] as? String ?? "",
                start: d["start"] as? String ?? d["startTime"] as? String ?? "",
                end: d["end"] as? String ?? d["endTime"] as? String ?? ""
            )
        }.filter { !$0.title.isEmpty }
    }
}
