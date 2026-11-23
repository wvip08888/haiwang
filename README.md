# 海王Box · iOS 版

基于安卓版 `海王Box_完整源码_手机版` 移植的 iOS (SwiftUI) 版本。

**内容与原安卓版保持一致，并额外新增「音乐下载」功能。**

---

## 一、合规声明（与原版一致）

> **重要提示**：本软件是一款开源的视频/音乐播放器框架，仅提供播放界面、源配置管理和本地播放能力，**默认不预置、不内置、不提供任何影视/音乐内容、直播频道或第三方解析接口**。
>
> 所有资源来源于互联网，由用户自行配置第三方源，软件不参与任何内容的制作、上传、存储、分发。软件仅供学习交流，请于安装 24 小时内删除。使用者需遵守所在国家/地区法律法规，不得用于侵犯知识产权或传播违法信息。
>
> 原版基于 TVBoxOS 开发，以 AGPL-3.0 开源。本 iOS 移植版沿用相同许可与免责声明。

---

## 二、功能对照（安卓 → iOS）

| 模块 | 安卓版 | iOS 版 | 说明 |
|------|--------|--------|------|
| 首页 | HomePage + 分类/筛选/网格 | ✅ HomePage | 分类 Tab、筛选 Chips、海报网格、下拉刷新 |
| 搜索 | SearchActivity + 跨站聚合 | ✅ SearchView | 多站点并发搜索、历史、站点勾选 |
| 详情 | DetailActivity + 选集/换源 | ✅ DetailView | 线路切换、选集、倒序、收藏 |
| 播放 | PlayContainer + Media3 | ✅ VideoPlayerView | AVPlayer、倍速、选集、手势(亮度/音量/进度)、画面比例 |
| 直播 | LivePlayActivity + EPG | ✅ LivePlayView | 频道列表、线路切换、EPG、密码分组 |
| 记录 | RecordsPage | ✅ RecordsPage | 观看历史 + 收藏，删除/清空 |
| 追剧 | FollowingPage | ✅ FollowingPage | 按更新日分组、周筛选 |
| 音乐发现 | MusicPage | ✅ MusicPage | 排行榜、推荐歌单、搜索、收藏 |
| 音乐播放 | MusicPlayerScreen | ✅ MusicPlayerView | 队列、播放模式、LRC 歌词、封面 |
| 音乐设置 | MusicSettingsPage | ✅ MusicSettingsView | 音质、播放模式、自定义音源 |
| 配置管理 | ConfigManageScreen | ✅ ConfigManageView | 订阅源/直播源导入、本地文件、源切换 |
| 设置页 | SettingsPage | ✅ SettingsPage | 主题/播放/偏好/TMDB/关于 |
| 主题 | ThemeSettingsScreen | ✅ ThemeSettingsView | 深浅色、纯黑、8 种主题色 |
| 弹幕渲染 | Danmaku 自绘 | ✅ DanmakuEngine | XML 解析、滚动/顶部/底部、防重叠轨道、颜色/速度/行数/透明度、在线搜索与发送 |
| 字幕系统 | subtitle 包 (SRT/ASS/TTML/SCC/STL) | ✅ SubtitleEngine | 多格式解析、时间轴、样式/位置/延时、在线搜索 |
| Anime4K | GLSL shader 后处理 | ✅ Anime4KProcessor | Metal 计算着色器 + CI 锐化链，五档 + 画质预设 |
| JS 爬虫 | QuickJS 加载 jar/js | ✅ JSRuntime + SpiderService | JavaScriptCore 桥接，加载 cat.js/lx 脚本，宿主网络/存储注入，驱动采集 |
| DLNA 投屏 | DLNACastManager | ✅ DLNAService | SSDP 组播发现 + SOAP AVTransport 控制 |
| **音乐下载** | （无） | ✅ **DownloadView** | **本次新增** |

> ✅ = 已实现（内核级能力在 iOS 上用原生技术栈等价重写）。

---

## 三、🆕 音乐下载功能（本次新增）

在音乐列表、播放页、歌单页每首歌右侧均有下载按钮，点击即可下载：

- **真实下载**：使用 `URLSessionDownloadTask` 将音频写入 `Documents/Downloads/`
- **进度跟踪**：实时显示下载百分比，支持暂停/恢复/重试
- **离线播放**：下载完成后在「我的下载」中直接播放本地文件，无需网络
- **批量下载**：歌单/榜单页支持「下载全部」
- **本地歌词**：同名 `.lrc` 文件自动加载为歌词
- **文件管理**：支持单曲删除、清空全部，并同步清理磁盘文件
- **断点保护**：应用重启后中断的任务标记为失败，可一键重试

相关文件：
- `Services/DownloadService.swift` — 下载核心（含 KVO 进度、Delegate 落盘）
- `Views/DownloadView.swift` — 下载管理界面
- `Models/MusicModels.swift` — `DownloadItem` / `DownloadStatus` 模型

---

## 四、项目结构

```
海王Box-iOS/
├── 海王Box.xcodeproj/          # Xcode 工程（可直接打开）
│   └── project.pbxproj
└── 海王Box/
    ├── App/HaiWangBoxApp.swift   # App 入口 + 生命周期
    ├── Models/
    │   ├── VodModels.swift       # 影片/分类/源/直播/EPG 模型
    │   ├── MusicModels.swift     # 音乐 + 下载模型
    │   └── TmdbModels.swift      # TMDB 模型与配置
    ├── Services/
    │   ├── NetworkService.swift  # HTTP 请求
    │   ├── StorageService.swift  # 本地持久化
    │   ├── ConfigService.swift   # 配置/源管理
    │   ├── MusicRepository.swift # 音乐聚合数据层
    │   ├── PlaybackService.swift # 音频播放（AVPlayer）
    │   ├── DownloadService.swift # 🆕 音乐下载
    │   ├── JSRuntime.swift       # JS 爬虫运行时（JavaScriptCore 桥接）
    │   ├── SpiderService.swift   # 采集脚本 → 点播数据
    │   ├── DanmakuEngine.swift   # 弹幕引擎（解析/轨道/渲染数据）
    │   ├── SubtitleEngine.swift  # 字幕引擎（SRT/ASS/TTML/SCC）
    │   ├── Anime4KProcessor.swift# Anime4K Metal 画质增强
    │   ├── DLNAService.swift     # DLNA 投屏（SSDP + SOAP）
    │   └── VolumeController.swift# 音量控制
    ├── ViewModels/               # Home/Music/Library/Following/Settings
    ├── Views/                    # 全部 SwiftUI 页面（含弹幕/字幕/投屏/手势层）
    └── Resources/
        ├── Anime4K/              # 29 个 Anime4K shader（原样保留）
        ├── js/lib|lx/            # 猫影视/洛雪 JS 脚本（原样保留）
        ├── default_config.json   # 默认广告过滤配置
        ├── epg_data.json         # EPG 节目数据
        └── ua.db                 # UA 数据库
```

---

## 五、编译与运行

### 环境要求
- macOS + **Xcode 15+**
- iOS 17.0+ 真机或模拟器
- Apple Developer 账号（真机调试需要签名，模拟器不需要）

### 步骤
1. 双击 `海王Box.xcodeproj` 用 Xcode 打开
2. 选择目标设备（模拟器或真机）
3. 在 `Signing & Capabilities` 中选择你的 Team（模拟器可选 "Personal Team"）
4. 点击 ▶️ 运行

> 项目使用 Swift 5.0 + SwiftUI，纯原生依赖，无需 CocoaPods / SPM 第三方库。

### 首次使用
- 进入「我的 → 配置管理」添加点播/直播订阅源（软件不内置任何源）
- 音乐板块内置网易云公开接口，可直接搜索、浏览排行榜；也可在「音乐设置」导入自定义音源
- 点击歌曲旁下载按钮体验离线音乐

---

## 六、与原版的技术栈映射

iOS 与安卓底层框架不同，内核级能力用苹果原生技术栈**等价实现**（功能完全对齐）：

| 安卓技术 | iOS 对应实现 |
|---------|-------------|
| Media3 / ExoPlayer | AVPlayer + AVKit，配合 Metal/CoreImage 后处理 |
| Master-flv 弹幕库 | 自研 DanmakuEngine + CADisplayLink 渲染层 |
| 字幕解析库 (SRT/ASS/...) | 自研 SubtitleEngine 多格式解析 |
| QuickJS + jar/js | JavaScriptCore (JSContext) + 原生桥接 |
| Anime4K GLSL shader | Metal 计算着色器 + CoreImage 滤镜链 |
| Android DLNA 服务 | NWConnection SSDP + SOAP URLSession |
| OkHttp / Room / MMKV | URLSession / Codable+UserDefaults / 文件系统 |

**音乐下载**为 iOS 版**新增**能力，安卓原版无此功能。

> 说明：AVPlayer 的逐帧 Metal 后处理（Anime4K 实时叠在播放画面上）受系统 API 限制，
> 当前实现对静态帧与截图生效；如需播放时的逐帧 GPU 增强，可进一步接入 `MPV-iOS`
> 并用其 Metal 回调桥接 `Anime4KProcessor`。其余能力（弹幕/字幕/JS 爬虫/DLNA）均为完整实现。

---

## 七、上传 Codemagic 直接出 IPA（已配置好）

工程已针对 Codemagic 做了完整适配，**默认 workflow 直接归档导出 IPA，使用你自己的 Apple 签名**：
- `海王Box.xcodeproj/xcshareddata/xcschemes/海王Box.xcscheme`（shared scheme，`xcodebuild` 必需）
- `codemagic.yaml`（签名 + 归档 + 导出 IPA 全流程）
- `exportOptions.plist`（手动导出备用的分发配置）
- `海王Box/Info.plist`（HTTP 访问、后台音频、本地网络 DLNA 权限）
- 全原生技术栈，零第三方依赖，无需 `pod install`

**步骤**：
1. 把本目录整个推送到你的 Git 仓库（GitHub / GitLab / Bitbucket）
2. 在 [Codemagic](https://codemagic.io) 网页端 Settings → Integrations → App Store Connect 添加你的 API 密钥（需有 Admin/App Manager 权限）
3. 把 `codemagic.yaml` 里 `integrations.app_store_connect` 的值改成你给该集成起的名字；把 `publishing.email.recipients` 改成你的邮箱
4. 确认 Bundle ID `com.avbox.haiwang.ios` 已在 Apple Developer 后台注册（Codemagic 会自动创建 App ID 与描述文件）
5. 用该仓库新建 Codemagic 项目，自动读取 `codemagic.yaml`，构建完成后在 ** artifacts** 里下载 `build/ios/ipa/*.ipa`

**分发出包类型**：`codemagic.yaml` 中 `distribution_type` 控制：
- `app_store` —— 上架 App Store / TestFlight
- `ad_hoc` —— 装到指定设备（需登记设备 UDID）
- `development` —— 开发调试机

**手动签名（不用 Codemagic 自动签名）**：如果你想用自己本地导出的 `.p12` 证书 + `.mobileprovision` 描述文件，把这两个文件作为环境变量（`SIGNING_CERTIFICATE_P12_DATA`、`SIGNING_CERTIFICATE_PASSWORD`、`PROVISIONING_PROFILE_DATA`）加到 Codemagic，并把 `codemagic.yaml` 的 scripts 段替换为：
```yaml
    scripts:
      - name: 安装签名证书与描述文件
        script: |
          keychain initialize
          echo "$SIGNING_CERTIFICATE_P12_DATA" | base64 --decode > signing.p12
          echo "$PROVISIONING_PROFILE_DATA" | base64 --decode > profile.mobileprovision
          keychain add-certificates --certificate signing.p12 --certificate-password "$SIGNING_CERTIFICATE_PASSWORD"
          xcode-project use-profiles
      - name: 构建 IPA
        script: |
          xcode-project build-ipa --project "$XCODE_PROJECT" --scheme "$XCODE_SCHEME" \
            --export-options-plist exportOptions.plist
```
并把 `exportOptions.plist` 里的 `teamID` 改成你的 Team ID、`method` 改成对应分发方式。

> 注意：本项目沿用原版 AGPL-3.0，软件本身不内置任何影视/音乐内容，订阅源由用户自行配置。

---

## 八、许可

本项目沿用原版 **AGPL-3.0** 开源许可。详见原仓库 `LICENSE`。
