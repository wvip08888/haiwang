import SwiftUI

/// 追剧页（对应 FollowingPage：按更新日分组）
struct FollowingPage: View {
    @StateObject private var vm = FollowingViewModel()
    @State private var selected: VodInfo? = nil
    private let weekdays = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 星期筛选条
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        Button("本周") {
                            vm.selectedDay = -1
                        }.font(.caption).padding(.horizontal, 12).padding(.vertical, 6)
                        .background(vm.selectedDay == -1 ? AppTheme.accent() : Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(vm.selectedDay == -1 ? .white : .primary)
                        ForEach(0..<7, id: \.self) { d in
                            Button(weekdays[d]) { vm.selectedDay = d }
                                .font(.caption).padding(.horizontal, 12).padding(.vertical, 6)
                                .background(vm.selectedDay == d ? AppTheme.accent() : Color.secondary.opacity(0.12), in: Capsule())
                                .foregroundStyle(vm.selectedDay == d ? .white : .primary)
                        }
                    }.padding()
                }

                if vm.items.isEmpty {
                    ContentUnavailableView {
                        Label("暂无追剧", systemImage: "bookmark")
                    } description: { Text("在详情页加入追剧，按更新日追踪剧集") }
                } else {
                    List {
                        ForEach(vm.items) { item in
                            FollowRow(info: item).onTapGesture { selected = item }
                        }.onDelete { vm.remove(at: $0) }
                    }
                }
            }
            .navigationTitle("追剧")
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

struct FollowRow: View {
    let info: VodInfo
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: info.pic)) { phase in
                if let img = phase.image { img.resizable().scaledToFill() }
                else { Color.gray.opacity(0.25).overlay(Image(systemName: "film")) }
            }
            .frame(width: 50, height: 70).cornerRadius(6).clipped()
            VStack(alignment: .leading) {
                Text(info.name).font(.subheadline).lineLimit(1)
                Text(info.note.isEmpty ? "未设置更新日" : info.note)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}
