# Nightingale Phase 1A · 工程搭建 + 录音回放 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 搭建 iOS 项目工程，实现"点击按钮开始整夜录音 → 息屏后不中断 → 醒来结束录制 → 在列表里看到录音 → 点播放能听到"的完整闭环。不做分析、不做图表、不读 HealthKit（这些放 Phase 1B）。

**Architecture:** SwiftUI + SwiftData 分层架构。UI 层调用 `RecorderController`（状态机）；`RecorderController` 驱动 `AudioRecorder`（AVAudioEngine 实时写文件）；录完的元数据通过 SwiftData 持久化，音频文件存沙盒 `Documents/Recordings/`。后台录音靠 `UIBackgroundModes: audio` + 保持 AVAudioSession 激活来维持。

**Tech Stack:** Swift 5.9+、SwiftUI、SwiftData、AVFoundation、AVAudioEngine、AVAudioPlayer、XCTest。最低 iOS 17.0。

---

## 面向读者的重要说明

这份计划假设你：
- **不会 Swift 也不打算深入学**——所以每一段代码都是完整可粘贴的，不需要你理解内部逻辑
- **会跟着截图式步骤点鼠标**——Xcode 的每一步操作我都写成"打开 X → 点 Y → 选 Z"
- **愿意在真机上测试**——iOS 模拟器没有后台录音能力，也没麦克风，Phase 1A 必须用真 iPhone

执行这份计划时，如果某一步的操作或代码你**不确定**，先别硬跑——截图或描述给我（AI），等我确认后再继续。

---

## 执行前的一次性准备（手动，约 2 小时）

这些不是"任务"，是写代码前的环境准备。照着做一次就行，后面不用再碰。

### P1. 安装 Xcode

- [ ] **Step 1：确认 Mac 系统版本**。打开 Mac → 左上角苹果 Logo → "关于本机"。系统必须是 **macOS 14.0 Sonoma 或更高**。如果低于 14，先升级 macOS。

- [ ] **Step 2：下载 Xcode**。打开 App Store → 搜索 "Xcode" → 点"获取"→ 等下载（约 15GB，视网速 20 分钟至几小时）。**不要关闭 App Store**。

- [ ] **Step 3：首次启动 Xcode**。下载完成后打开 Xcode，会弹"Install additional required components" → 点 Install → 输入 Mac 密码 → 等 5-10 分钟。

- [ ] **Step 4：验证**。Xcode 打开后顶部菜单栏能看到 "Xcode / File / Edit..." 就算成功。**不要**关掉它。

### P2. 登录 Apple ID

- [ ] **Step 1：打开 Xcode 设置**。Xcode 菜单栏 → Xcode → Settings...（或按 `Command + ,`）。

- [ ] **Step 2：进入 Accounts 标签**。顶部有 "General / Accounts / Behaviors..." 一排，点 **Accounts**。

- [ ] **Step 3：添加 Apple ID**。点左下角 `+` → 选 "Apple ID" → Continue → 输入你的 Apple ID 邮箱和密码（如有双因素验证，输收到的验证码）。

- [ ] **Step 4：验证**。添加成功后左侧会看到你的邮箱，右侧显示 `Personal Team` 字样（这就是免费开发者团队，不用交钱）。关掉 Settings 窗口。

### P3. 准备 iPhone

- [ ] **Step 1：连接 iPhone**。用原装数据线把 iPhone 插到 Mac。iPhone 上会弹"信任这台电脑？"→ 点"信任"→ 输入 iPhone 锁屏密码。

- [ ] **Step 2：在 iPhone 上开启开发者模式**（iOS 16+ 需要）。iPhone → 设置 → 隐私与安全性 → 往下滑找"开发者模式"→ 打开 → iPhone 会重启 → 重启后再次进入"开发者模式"→ 点"打开"。

- [ ] **Step 3：记录 iPhone 型号**。iPhone → 设置 → 通用 → 关于本机 → 记下"机型名称"（例如 "iPhone 15 Pro"）。**把型号告诉 AI**，这会影响低电量阈值的默认值。

### P4. 检查 Apple Watch 配对

- [ ] **Step 1：确认 Watch 已配对并开启睡眠追踪**。iPhone 上"健康"app → 浏览 → 睡眠。应该能看到过去几天的睡眠数据。如果没有，先把 Watch 戴着睡一晚。

- [ ] **Step 2：确认血氧功能可用**（仅 Phase 1B 需要，但现在先确认省得以后返工）。Watch → 血氧 app → 手动测一次。如果能出读数，说明不是美版禁用款。**把结果告诉 AI**。

---

## 文件结构

Phase 1A 结束时项目里会有这些文件（相对 Xcode 项目 Group 根）：

```
Nightingale/
├── NightingaleApp.swift              // app 入口，配置 SwiftData 容器
├── AppRoot.swift                     // 根视图，TabView
│
├── Features/
│   ├── Tonight/
│   │   └── TonightView.swift         // 今夜 Tab，录音按钮 + 状态
│   ├── Report/
│   │   ├── ReportListView.swift      // 报告 Tab（列表）
│   │   └── SessionDetailView.swift   // 单晚详情（目前只有播放）
│   └── Settings/
│       └── SettingsView.swift        // 设置 Tab
│
├── Engine/
│   └── Recording/
│       ├── AudioRecorder.swift       // AVAudioEngine 实际录音
│       ├── RecorderController.swift  // 录音状态机 + 和 SwiftData 对接
│       └── PermissionManager.swift   // 麦克风权限
│
├── Storage/
│   ├── Models/
│   │   ├── SleepSession.swift        // SwiftData 模型
│   │   └── SharedEnums.swift         // EventType / SensorKind 等（1A 还用不到全部，先占位）
│   └── AudioFileStore.swift          // 文件路径管理 + 清理
│
├── Shared/
│   ├── Theme.swift                   // 颜色 / 字体常量
│   └── TimeFormat.swift              // 时长格式化等纯函数
│
├── Assets.xcassets                   // Xcode 自动生成
└── Info.plist                        // 权限说明、后台模式
```

测试文件：

```
NightingaleTests/
├── TimeFormatTests.swift
└── AudioFileStoreTests.swift
```

---

## Task 1：创建 Xcode 项目

**Files:**
- Create（Xcode 自动）：整个 `Nightingale.xcodeproj` 工程文件夹

- [ ] **Step 1：打开 Xcode 起始页**

启动 Xcode，如果没自动出欢迎窗，点菜单 File → New → Project...

- [ ] **Step 2：选择模板**

顶部切到 **iOS**（不要选 macOS/watchOS）→ 选 **App** → 点 Next。

- [ ] **Step 3：填写工程信息**

按下面这个表格一字不差填：

| 字段 | 填什么 |
|---|---|
| Product Name | `Nightingale` |
| Team | 下拉选你的 `Personal Team`（免费账号）|
| Organization Identifier | `com.yourname.nightingale`（把 `yourname` 换成你的名字拼音或任意字符串，全小写无空格）|
| Interface | **SwiftUI** |
| Language | **Swift** |
| Storage | **SwiftData** |
| Include Tests | **✅ 勾上** |
| Host in CloudKit | ❌ 不要勾 |

点 Next。

- [ ] **Step 4：选保存位置**

跳出文件选择器 → 定位到 `/Users/eason-mini/workspace/nightingale/` → **取消勾选** "Create Git repository on my Mac"（我们已经有 git 仓库了）→ 点 Create。

- [ ] **Step 5：验证项目能运行**

Xcode 左上角会显示项目导航器（文件树）。顶部有设备选择器，下拉 → 选你插在电脑上的 iPhone 名字（例如"My iPhone"）→ 按 `Command + R` 或点左上角 ▶️。

第一次会弹窗提示信任开发者 → iPhone 上：设置 → 通用 → VPN 与设备管理 → 找到你的 Apple ID → 信任。

如果一切顺利，iPhone 上会出现一个叫 "Nightingale" 的 app，打开显示默认 "Hello, world!" 文字。

- [ ] **Step 6：Commit**

切回 Terminal（不是 Xcode）：

```bash
cd /Users/eason-mini/workspace/nightingale
git add Nightingale Nightingale.xcodeproj NightingaleTests
git commit -m "chore: scaffold Xcode project via template"
```

---

## Task 2：配置 Info.plist 与 Capabilities（权限 + 后台）

**Files:**
- Modify：`Nightingale/Info.plist`（通过 Xcode UI 修改）
- Modify：Target 的 Signing & Capabilities（通过 Xcode UI）

- [ ] **Step 1：打开 Target 设置**

Xcode 左侧项目导航器 → 点最顶的蓝色图标 `Nightingale`（工程本身）→ 中间列选 TARGETS 下的 `Nightingale`（不是 PROJECT 下的）。

- [ ] **Step 2：添加后台模式**

顶部 Tab 选 **Signing & Capabilities** → 点左上 `+ Capability` → 搜索 "Background Modes" → 双击添加。

在新出现的 Background Modes 板块里，勾选 **Audio, AirPlay, and Picture in Picture**。不要勾其他。

- [ ] **Step 3：添加权限说明文字**

顶部 Tab 切到 **Info** → 在 "Custom iOS Target Properties" 表里，把鼠标悬停到任意一行 → 右侧出现 `+` → 点 `+` 添加两条：

| Key | Type | Value |
|---|---|---|
| `Privacy - Microphone Usage Description` | String | `Nightingale 需要麦克风在夜间记录您的睡眠音频（打呼、梦话等），所有音频仅存本地，不上传。` |
| `UIBackgroundModes`（应该已经由 Step 2 自动添加，确认存在且包含 `audio`） | Array | — |

如果 `UIBackgroundModes` 没自动出现，手动添加：Type 选 Array，展开后 Item 0 填 `audio`。

- [ ] **Step 4：验证**

还在 Info 标签 → 展开 `UIBackgroundModes` 确认有 `audio`。切回 Signing & Capabilities → 确认 Background Modes 下 Audio 是勾选的。

- [ ] **Step 5：Commit**

```bash
cd /Users/eason-mini/workspace/nightingale
git add Nightingale/Info.plist Nightingale.xcodeproj/project.pbxproj
git commit -m "feat: add microphone permission and background audio capability"
```

---

## Task 3：创建 Group 文件夹结构

**Files:**
- Create：Xcode Groups（虚拟文件夹）

Xcode 里的 "Group" 是代码组织单元，对应磁盘上的文件夹。

- [ ] **Step 1：创建顶层 Groups**

项目导航器里，右键 `Nightingale` 文件夹 → New Group → 命名 `Features`。重复创建：`Engine`、`Storage`、`Shared`。

- [ ] **Step 2：创建子 Groups**

- 右键 `Features` → New Group → `Tonight`
- 右键 `Features` → New Group → `Report`
- 右键 `Features` → New Group → `Settings`
- 右键 `Engine` → New Group → `Recording`
- 右键 `Storage` → New Group → `Models`

- [ ] **Step 3：把默认生成的 ContentView.swift 先放一边**

默认 Xcode 会生成 `ContentView.swift`，后面 Task 7 会删掉它并用 `AppRoot.swift` 替代。先留着别动。

- [ ] **Step 4：验证 + Commit**

导航器应该呈现如下结构：

```
Nightingale/
├── NightingaleApp.swift (默认生成)
├── ContentView.swift (默认生成，待删)
├── Assets.xcassets
├── Features/
│   ├── Tonight/
│   ├── Report/
│   └── Settings/
├── Engine/
│   └── Recording/
├── Storage/
│   └── Models/
└── Shared/
```

```bash
cd /Users/eason-mini/workspace/nightingale
git add Nightingale.xcodeproj
git commit -m "chore: set up feature group folder structure"
```

---

## Task 4：Shared/Theme.swift 和 Shared/TimeFormat.swift

**Files:**
- Create：`Nightingale/Shared/Theme.swift`
- Create：`Nightingale/Shared/TimeFormat.swift`
- Create：`NightingaleTests/TimeFormatTests.swift`

- [ ] **Step 1：先写失败的测试**

Xcode 左侧 → `NightingaleTests` → 右键 → New File... → iOS → Swift File → 命名 `TimeFormatTests.swift` → 注意 **Targets 勾选 NightingaleTests（不是 Nightingale）**→ Create。

粘贴以下内容：

```swift
import XCTest
@testable import Nightingale

final class TimeFormatTests: XCTestCase {
    func testZeroSecondsFormats() {
        XCTAssertEqual(TimeFormat.duration(0), "0:00")
    }

    func testSecondsUnderMinute() {
        XCTAssertEqual(TimeFormat.duration(45), "0:45")
    }

    func testMinutesAndSeconds() {
        XCTAssertEqual(TimeFormat.duration(125), "2:05")
    }

    func testHoursMinutesSeconds() {
        XCTAssertEqual(TimeFormat.duration(3725), "1:02:05")
    }

    func testEightHoursTypicalNight() {
        XCTAssertEqual(TimeFormat.duration(8 * 3600 + 27 * 60 + 13), "8:27:13")
    }

    func testRejectsNegative() {
        XCTAssertEqual(TimeFormat.duration(-5), "0:00")
    }
}
```

- [ ] **Step 2：运行测试看它失败**

按 `Command + U` 或 Xcode 菜单 Product → Test。

**预期结果：编译失败**，错误是 "Cannot find 'TimeFormat' in scope"——因为我们还没写这个类型。这就是我们想看到的"红色"。

- [ ] **Step 3：写最小实现**

Xcode 左侧 → `Nightingale/Shared` → 右键 → New File... → iOS → Swift File → 命名 `TimeFormat.swift` → **Targets 勾选 Nightingale**（不是 Tests）→ Create。粘贴：

```swift
import Foundation

enum TimeFormat {
    /// 把秒数格式化成 "m:ss" 或 "h:mm:ss"，负数返回 "0:00"。
    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}
```

- [ ] **Step 4：再跑测试确认通过**

`Command + U`。**预期：全部 6 个测试绿色通过**。

- [ ] **Step 5：写 Theme**

`Nightingale/Shared` 右键 → New File → Swift File → `Theme.swift`（Target: Nightingale）。粘贴：

```swift
import SwiftUI

/// 全局颜色/字号常量。深色夜用风格。
enum Theme {
    static let background = Color.black
    static let surface = Color(white: 0.08)
    static let surfaceElevated = Color(white: 0.14)
    static let accent = Color(red: 0.55, green: 0.72, blue: 1.0)       // 冷色调蓝
    static let accentSecondary = Color(red: 0.85, green: 0.72, blue: 1.0) // 紫，用于事件
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.7)
    static let textTertiary = Color(white: 0.45)
    static let danger = Color(red: 1.0, green: 0.45, blue: 0.45)

    static let cornerRadius: CGFloat = 14
    static let padding: CGFloat = 16
}
```

- [ ] **Step 6：Commit**

```bash
cd /Users/eason-mini/workspace/nightingale
git add Nightingale/Shared NightingaleTests/TimeFormatTests.swift Nightingale.xcodeproj
git commit -m "feat: add Theme constants and TimeFormat helper with tests"
```

---

## Task 5：SwiftData 模型

**Files:**
- Create：`Nightingale/Storage/Models/SleepSession.swift`
- Create：`Nightingale/Storage/Models/SharedEnums.swift`

Phase 1A 只需要 `SleepSession`（一晚的录音元数据）。`SleepEvent` 和 `SensorSample` 放 Phase 1B，但先把枚举占位好。

- [ ] **Step 1：创建 SharedEnums.swift**

`Storage/Models` 右键 → New File → Swift File → `SharedEnums.swift`（Target: Nightingale）。粘贴：

```swift
import Foundation

/// 睡眠事件类型。Phase 1A 暂不使用，Phase 1B 接入打呼识别时启用。
enum EventType: String, Codable, CaseIterable {
    case snore
    case sleepTalk
    case suspectedApnea
    case nightmareSpike
}

/// 传感器数据类型。Phase 1A 暂不使用，Phase 1B 接入 HealthKit 时启用。
enum SensorKind: String, Codable, CaseIterable {
    case heartRate
    case hrv
    case spo2
    case sleepStage
    case temperature
    case bodyMovement
}

/// 录音状态机的状态。
enum RecorderState: Equatable {
    case idle
    case recording(startedAt: Date)
    case finalizing
    case failed(message: String)
}
```

- [ ] **Step 2：创建 SleepSession.swift**

`Storage/Models` 右键 → New File → Swift File → `SleepSession.swift`。粘贴：

```swift
import Foundation
import SwiftData

@Model
final class SleepSession {
    /// 唯一 ID，用于关联音频文件名。
    var id: UUID

    /// 录制开始时间。
    var startTime: Date

    /// 录制结束时间。nil 表示还在录制中或异常中断。
    var endTime: Date?

    /// 整夜音频文件相对 Documents 的路径，例如 "Recordings/A1B2C3.m4a"。
    /// 7 天后被清理任务清空（文件删除 + 此字段置 nil），但 SleepSession 自身保留。
    var fullAudioPath: String?

    /// 手动归档标记。true 则不被自动清理。
    var isArchived: Bool

    /// 晨间心情（emoji）。Phase 1A 不接入 UI，字段占位供 1B 使用。
    var morningMood: String?

    /// 晨间一句话。同上。
    var morningNote: String?

    init(
        id: UUID = UUID(),
        startTime: Date,
        endTime: Date? = nil,
        fullAudioPath: String? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.fullAudioPath = fullAudioPath
        self.isArchived = isArchived
    }

    /// 录制时长（秒）。未结束则返回从开始到现在。
    var durationSeconds: TimeInterval {
        let end = endTime ?? Date()
        return max(0, end.timeIntervalSince(startTime))
    }
}
```

- [ ] **Step 3：Commit**

```bash
cd /Users/eason-mini/workspace/nightingale
git add Nightingale/Storage Nightingale.xcodeproj
git commit -m "feat: add SleepSession SwiftData model and shared enums"
```

---

## Task 6：AudioFileStore — 文件路径管理 + 清理

**Files:**
- Create：`Nightingale/Storage/AudioFileStore.swift`
- Create：`NightingaleTests/AudioFileStoreTests.swift`

职责：给出整夜音频文件的 URL、计算存储占用、清理 7 天前的整夜录音。

- [ ] **Step 1：先写测试**

`NightingaleTests` 右键 → New File → Swift File → `AudioFileStoreTests.swift`（Target: NightingaleTests）。粘贴：

```swift
import XCTest
@testable import Nightingale

final class AudioFileStoreTests: XCTestCase {

    var tempRoot: URL!
    var store: AudioFileStore!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        store = AudioFileStore(baseDirectory: tempRoot)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testRecordingsURLIsCreated() {
        let url = store.recordingsDirectory
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testFullRecordingURLIncludesID() {
        let id = UUID()
        let url = store.fullRecordingURL(for: id)
        XCTAssertTrue(url.path.hasSuffix("Recordings/\(id.uuidString).m4a"))
    }

    func testCleanupRemovesOldFilesButKeepsArchived() throws {
        let oldID = UUID()
        let newID = UUID()
        let archivedID = UUID()

        // 造三个文件
        let oldURL = store.fullRecordingURL(for: oldID)
        let newURL = store.fullRecordingURL(for: newID)
        let archivedURL = store.fullRecordingURL(for: archivedID)
        for url in [oldURL, newURL, archivedURL] {
            FileManager.default.createFile(atPath: url.path, contents: Data([0x01]))
        }

        // 把"旧"文件和"归档"文件的 modificationDate 改成 10 天前
        let tenDaysAgo = Date().addingTimeInterval(-10 * 24 * 3600)
        try FileManager.default.setAttributes([.modificationDate: tenDaysAgo], ofItemAtPath: oldURL.path)
        try FileManager.default.setAttributes([.modificationDate: tenDaysAgo], ofItemAtPath: archivedURL.path)

        // 清理，告诉它 archivedID 不能删
        let removed = try store.cleanupOldRecordings(olderThan: 7, archivedIDs: [archivedID])

        XCTAssertEqual(removed, [oldID])
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archivedURL.path))
    }

    func testTotalBytesUsed() {
        let id = UUID()
        let url = store.fullRecordingURL(for: id)
        let data = Data(count: 1024)
        FileManager.default.createFile(atPath: url.path, contents: data)

        XCTAssertEqual(store.totalBytesUsed(), 1024)
    }
}
```

- [ ] **Step 2：运行测试看它失败**

`Command + U`。预期：编译失败，"Cannot find 'AudioFileStore'"。

- [ ] **Step 3：写实现**

`Storage` 右键 → New File → Swift File → `AudioFileStore.swift`（Target: Nightingale）。粘贴：

```swift
import Foundation

/// 管理录音文件在沙盒中的路径与清理。
final class AudioFileStore {

    /// 文件存储根目录（通常是 app 的 Documents 目录，测试时注入临时目录）。
    private let baseDirectory: URL

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
        ensureDirectoryExists(recordingsDirectory)
    }

    /// 用默认 Documents 初始化。生产代码调用这个。
    convenience init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.init(baseDirectory: docs)
    }

    /// 整夜录音目录。
    var recordingsDirectory: URL {
        baseDirectory.appendingPathComponent("Recordings", isDirectory: true)
    }

    /// 某个 session 的整夜音频 URL。
    func fullRecordingURL(for sessionID: UUID) -> URL {
        recordingsDirectory.appendingPathComponent("\(sessionID.uuidString).m4a")
    }

    /// 从相对路径（存在 SleepSession.fullAudioPath）还原成绝对 URL。
    func url(fromRelativePath relativePath: String) -> URL {
        baseDirectory.appendingPathComponent(relativePath)
    }

    /// 把绝对 URL 转成相对路径，用于持久化。
    func relativePath(for url: URL) -> String {
        let basePath = baseDirectory.path
        if url.path.hasPrefix(basePath) {
            return String(url.path.dropFirst(basePath.count).drop(while: { $0 == "/" }))
        }
        return url.path
    }

    /// 当前录音目录总占用字节数。
    func totalBytesUsed() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        return files.reduce(Int64(0)) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(size)
        }
    }

    /// 清理超过 N 天未修改的整夜录音。保留 archivedIDs 里的文件。返回被删除的 session ID 列表。
    @discardableResult
    func cleanupOldRecordings(olderThan days: Int, archivedIDs: Set<UUID>) throws -> [UUID] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 3600)
        let files = try FileManager.default.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )

        var removed: [UUID] = []
        for url in files {
            let filename = url.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: filename) else { continue }
            if archivedIDs.contains(id) { continue }

            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? Date()
            if modDate < cutoff {
                try FileManager.default.removeItem(at: url)
                removed.append(id)
            }
        }
        return removed
    }

    // MARK: - Private

    private func ensureDirectoryExists(_ url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
```

- [ ] **Step 4：跑测试确认绿**

`Command + U`。预期 4 个 AudioFileStore 测试全绿，加上之前 6 个 TimeFormat 测试，共 10 个绿。

- [ ] **Step 5：Commit**

```bash
cd /Users/eason-mini/workspace/nightingale
git add Nightingale/Storage/AudioFileStore.swift NightingaleTests/AudioFileStoreTests.swift Nightingale.xcodeproj
git commit -m "feat: add AudioFileStore with retention cleanup and tests"
```

---

## Task 7：PermissionManager — 麦克风权限

**Files:**
- Create：`Nightingale/Engine/Recording/PermissionManager.swift`

Phase 1A 只处理麦克风。HealthKit / Speech 权限在 Phase 1B 加。

- [ ] **Step 1：创建文件**

`Engine/Recording` 右键 → New File → Swift File → `PermissionManager.swift`（Target: Nightingale）。粘贴：

```swift
import Foundation
import AVFoundation

/// 统一管理运行时权限。Phase 1A 只含麦克风。
@MainActor
final class PermissionManager: ObservableObject {

    enum MicStatus {
        case notDetermined
        case granted
        case denied
    }

    @Published private(set) var microphoneStatus: MicStatus = .notDetermined

    init() {
        refreshMicrophoneStatus()
    }

    /// 查当前权限状态（不触发弹窗）。
    func refreshMicrophoneStatus() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: microphoneStatus = .granted
        case .denied: microphoneStatus = .denied
        case .undetermined: microphoneStatus = .notDetermined
        @unknown default: microphoneStatus = .notDetermined
        }
    }

    /// 请求麦克风权限。已授权则立即返回 true，已拒绝返回 false（不会再弹）。
    func requestMicrophone() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            microphoneStatus = .granted
            return true
        case .denied:
            microphoneStatus = .denied
            return false
        case .undetermined:
            let granted = await AVAudioApplication.requestRecordPermission()
            microphoneStatus = granted ? .granted : .denied
            return granted
        @unknown default:
            return false
        }
    }
}
```

- [ ] **Step 2：编译确认无错**

`Command + B`（只编译不跑）。预期：Build Succeeded。

- [ ] **Step 3：Commit**

```bash
cd /Users/eason-mini/workspace/nightingale
git add Nightingale/Engine Nightingale.xcodeproj
git commit -m "feat: add PermissionManager for microphone"
```

---

## Task 8：AudioRecorder — 实际录音引擎

**Files:**
- Create：`Nightingale/Engine/Recording/AudioRecorder.swift`

职责：配置 AVAudioSession、启动 AVAudioEngine、把实时音频写入 m4a 文件。不管状态、不管 SwiftData——那是 Controller 的事。

- [ ] **Step 1：创建文件**

`Engine/Recording` 右键 → New File → Swift File → `AudioRecorder.swift`（Target: Nightingale）。粘贴：

```swift
import Foundation
import AVFoundation

/// 低层录音引擎：把 AVAudioEngine 的输入流写入 AAC m4a 文件。
/// 单实例、非线程安全——外部保证串行调用。
final class AudioRecorder {

    enum RecorderError: Error {
        case sessionActivationFailed(Error)
        case fileCreationFailed(Error)
        case engineStartFailed(Error)
        case alreadyRunning
        case notRunning
    }

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var isRunning = false

    /// 配置并启动录音，写入 outputURL。
    /// - 采样率 16 kHz、单声道、AAC 32 kbps。
    func start(writingTo outputURL: URL) throws {
        guard !isRunning else { throw RecorderError.alreadyRunning }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true, options: [])
        } catch {
            throw RecorderError.sessionActivationFailed(error)
        }

        let input = engine.inputNode
        let hardwareFormat = input.outputFormat(forBus: 0)

        // 目标文件设置：AAC 16 kHz 单声道
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32000,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            audioFile = try AVAudioFile(forWriting: outputURL, settings: settings)
        } catch {
            throw RecorderError.fileCreationFailed(error)
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self, let file = self.audioFile else { return }
            do {
                try file.write(from: buffer)
            } catch {
                // 写失败不中断——避免单帧错误杀掉整夜录音
                NSLog("AudioRecorder write failed: \(error)")
            }
        }

        do {
            try engine.start()
            isRunning = true
        } catch {
            input.removeTap(onBus: 0)
            audioFile = nil
            throw RecorderError.engineStartFailed(error)
        }
    }

    /// 停止录音并 flush 文件。安全重复调用。
    func stop() throws {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        isRunning = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 是否正在录音。
    var running: Bool { isRunning }
}
```

> **为什么用 AVAudioEngine 而不是 AVAudioRecorder**：AVAudioRecorder 简单但拿不到实时音频帧，Phase 1B 要做打呼识别需要实时帧。现在就用 Engine 免得以后重构。

- [ ] **Step 2：编译确认无错**

`Command + B`。

- [ ] **Step 3：Commit**

```bash
cd /Users/eason-mini/workspace/nightingale
git add Nightingale/Engine Nightingale.xcodeproj
git commit -m "feat: add AudioRecorder using AVAudioEngine writing AAC m4a"
```

---

## Task 9：RecorderController — 状态机 + SwiftData 对接

**Files:**
- Create：`Nightingale/Engine/Recording/RecorderController.swift`

职责：UI 层的唯一入口。开始时创建 SleepSession、启动 AudioRecorder；停止时关闭 recorder、写 endTime、保存。

- [ ] **Step 1：创建文件**

`Engine/Recording` 右键 → New File → Swift File → `RecorderController.swift`（Target: Nightingale）。粘贴：

```swift
import Foundation
import SwiftData
import AVFoundation
import Combine

@MainActor
final class RecorderController: ObservableObject {

    @Published private(set) var state: RecorderState = .idle

    private let recorder = AudioRecorder()
    private let fileStore: AudioFileStore
    private let modelContext: ModelContext
    private let permissions: PermissionManager

    private var currentSession: SleepSession?
    private var tickTimer: Timer?
    private var interruptionObserver: NSObjectProtocol?

    init(
        modelContext: ModelContext,
        fileStore: AudioFileStore,
        permissions: PermissionManager
    ) {
        self.modelContext = modelContext
        self.fileStore = fileStore
        self.permissions = permissions
        observeAudioInterruptions()
    }

    deinit {
        if let obs = interruptionObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    /// 入口：开始录音。未授权会自动请求。
    func start() async {
        guard case .idle = state else { return }

        let granted = await permissions.requestMicrophone()
        guard granted else {
            state = .failed(message: "未授权麦克风，请到系统设置 → Nightingale → 麦克风打开权限。")
            return
        }

        let session = SleepSession(startTime: Date())
        modelContext.insert(session)

        let url = fileStore.fullRecordingURL(for: session.id)

        do {
            try recorder.start(writingTo: url)
            session.fullAudioPath = fileStore.relativePath(for: url)
            try modelContext.save()
            currentSession = session
            state = .recording(startedAt: session.startTime)
            startTick()
        } catch {
            modelContext.delete(session)
            try? modelContext.save()
            state = .failed(message: "无法启动录音：\(error.localizedDescription)")
        }
    }

    /// 入口：停止录音并保存。
    func stop() {
        guard case .recording = state else { return }
        state = .finalizing
        stopTick()

        do {
            try recorder.stop()
        } catch {
            NSLog("Stop error: \(error)")
        }

        if let session = currentSession {
            session.endTime = Date()
            do {
                try modelContext.save()
            } catch {
                NSLog("Failed to save session: \(error)")
            }
        }

        currentSession = nil
        state = .idle
    }

    // MARK: - 内部

    private func startTick() {
        tickTimer?.invalidate()
        // 触发 UI 定期刷新时长显示
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, case .recording(let start) = self.state else { return }
            self.state = .recording(startedAt: start)
        }
    }

    private func stopTick() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func observeAudioInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleInterruption(notification)
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let typeRaw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }

        switch type {
        case .began:
            NSLog("Audio interrupted")
        case .ended:
            if case .recording = state {
                // 尝试恢复：虽然简单，但打电话后系统通常可以继续
                NSLog("Interruption ended; session continuing")
            }
        @unknown default:
            break
        }
    }
}
```

- [ ] **Step 2：编译检查**

`Command + B`。应该绿。

- [ ] **Step 3：Commit**

```bash
cd /Users/eason-mini/workspace/nightingale
git add Nightingale/Engine/Recording/RecorderController.swift Nightingale.xcodeproj
git commit -m "feat: add RecorderController state machine wiring recorder to SwiftData"
```

---

## Task 10：App 入口 + AppRoot（TabView）

**Files:**
- Modify：`Nightingale/NightingaleApp.swift`
- Create：`Nightingale/AppRoot.swift`
- Delete：`Nightingale/ContentView.swift`（默认生成的）

- [ ] **Step 1：替换 NightingaleApp.swift**

左侧找到 `NightingaleApp.swift` → 打开 → 删掉所有内容 → 粘贴：

```swift
import SwiftUI
import SwiftData

@main
struct NightingaleApp: App {

    let modelContainer: ModelContainer
    let fileStore: AudioFileStore
    let permissions: PermissionManager

    init() {
        // SwiftData 容器
        let schema = Schema([SleepSession.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }

        self.fileStore = AudioFileStore()
        self.permissions = PermissionManager()
    }

    var body: some Scene {
        WindowGroup {
            AppRoot(fileStore: fileStore, permissions: permissions)
                .modelContainer(modelContainer)
                .preferredColorScheme(.dark)
        }
    }
}
```

- [ ] **Step 2：创建 AppRoot.swift**

项目根（`Nightingale` 下）右键 → New File → Swift File → `AppRoot.swift`（Target: Nightingale）。粘贴：

```swift
import SwiftUI
import SwiftData

struct AppRoot: View {

    let fileStore: AudioFileStore
    @ObservedObject var permissions: PermissionManager

    @Environment(\.modelContext) private var modelContext
    @StateObject private var controllerBox = ControllerBox()

    var body: some View {
        TabView {
            TonightView(controller: controllerBox.ensureController(context: modelContext,
                                                                   fileStore: fileStore,
                                                                   permissions: permissions))
                .tabItem { Label("今夜", systemImage: "moon.stars.fill") }

            ReportListView(fileStore: fileStore)
                .tabItem { Label("报告", systemImage: "chart.xyaxis.line") }

            SettingsView(fileStore: fileStore, permissions: permissions)
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .tint(Theme.accent)
    }
}

/// RecorderController 需要 modelContext 才能创建，而 modelContext 只能在 view tree 里拿到，
/// 所以包一层 lazy holder。
@MainActor
final class ControllerBox: ObservableObject {
    private var controller: RecorderController?

    func ensureController(
        context: ModelContext,
        fileStore: AudioFileStore,
        permissions: PermissionManager
    ) -> RecorderController {
        if let existing = controller { return existing }
        let c = RecorderController(modelContext: context, fileStore: fileStore, permissions: permissions)
        controller = c
        return c
    }
}
```

> 这里引用了 `TonightView` / `ReportListView` / `SettingsView`，后面任务里创建。现在编译会报错，是预期的。

- [ ] **Step 3：删除 ContentView.swift**

左侧 `ContentView.swift` → 右键 → Delete → 选 "Move to Trash"。

- [ ] **Step 4：暂缓编译，等后续任务**

Task 11-13 会创建剩下的 View。不要在这一步尝试 Command+B。

- [ ] **Step 5：Commit**

（先不 commit，等 Task 13 完成时一起 commit）

---

## Task 11：TonightView — 今夜 Tab

**Files:**
- Create：`Nightingale/Features/Tonight/TonightView.swift`

- [ ] **Step 1：创建文件**

`Features/Tonight` 右键 → New File → Swift File → `TonightView.swift`（Target: Nightingale）。粘贴：

```swift
import SwiftUI

struct TonightView: View {

    @ObservedObject var controller: RecorderController

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()
                headline
                Spacer()
                bigButton
                subtitle
                Spacer().frame(height: 60)
            }
            .padding(.horizontal, Theme.padding)
        }
    }

    @ViewBuilder
    private var headline: some View {
        switch controller.state {
        case .idle:
            VStack(spacing: 6) {
                Text("准备就绪")
                    .font(.title).bold()
                    .foregroundStyle(Theme.textPrimary)
                Text("把手机放在床头，屏幕朝下，插上电源")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        case .recording(let start):
            VStack(spacing: 6) {
                Text("正在记录")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                Text(TimeFormat.duration(Date().timeIntervalSince(start)))
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                Text("息屏不会中断录音")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        case .finalizing:
            VStack(spacing: 8) {
                ProgressView().tint(Theme.accent)
                Text("正在保存…")
                    .foregroundStyle(Theme.textSecondary)
            }
        case .failed(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.danger)
                .multilineTextAlignment(.center)
                .padding()
        }
    }

    @ViewBuilder
    private var bigButton: some View {
        Button {
            handleTap()
        } label: {
            ZStack {
                Circle()
                    .fill(buttonColor)
                    .frame(width: 200, height: 200)
                    .shadow(color: buttonColor.opacity(0.5), radius: 40)
                Text(buttonLabel)
                    .font(.title2).bold()
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(isButtonDisabled)
    }

    private var subtitle: some View {
        Text(subtitleText)
            .font(.footnote)
            .foregroundStyle(Theme.textTertiary)
            .multilineTextAlignment(.center)
    }

    private func handleTap() {
        switch controller.state {
        case .idle:
            Task { await controller.start() }
        case .recording:
            controller.stop()
        case .failed:
            Task { await controller.start() }
        case .finalizing:
            break
        }
    }

    private var buttonLabel: String {
        switch controller.state {
        case .idle: "开始记录"
        case .recording: "结束记录"
        case .finalizing: "保存中"
        case .failed: "重试"
        }
    }

    private var buttonColor: Color {
        switch controller.state {
        case .idle: Theme.accent
        case .recording: Theme.danger
        case .finalizing: Theme.textTertiary
        case .failed: Theme.danger
        }
    }

    private var isButtonDisabled: Bool {
        if case .finalizing = controller.state { return true }
        return false
    }

    private var subtitleText: String {
        switch controller.state {
        case .idle, .failed:
            return "开始后手机可以熄屏，静音。早上醒来回到 app 点「结束记录」。"
        case .recording:
            return "不要关闭 app，不要手动结束进程。"
        case .finalizing:
            return ""
        }
    }
}
```

- [ ] **Step 2：Commit 暂缓**（等 13 完成一起 commit）

---

## Task 12：ReportListView + SessionDetailView

**Files:**
- Create：`Nightingale/Features/Report/ReportListView.swift`
- Create：`Nightingale/Features/Report/SessionDetailView.swift`

列表显示所有 session，点进去可播放音频。

- [ ] **Step 1：创建 ReportListView.swift**

`Features/Report` 右键 → New File → Swift File → `ReportListView.swift`。粘贴：

```swift
import SwiftUI
import SwiftData

struct ReportListView: View {

    let fileStore: AudioFileStore

    @Query(sort: \SleepSession.startTime, order: .reverse) private var sessions: [SleepSession]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if sessions.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(sessions) { session in
                            NavigationLink {
                                SessionDetailView(session: session, fileStore: fileStore)
                            } label: {
                                SessionRow(session: session)
                            }
                            .listRowBackground(Theme.surface)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Theme.background)
                }
            }
            .navigationTitle("报告")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 42))
                .foregroundStyle(Theme.textTertiary)
            Text("还没有记录")
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)
            Text("睡一晚，明早回来看报告")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding()
    }
}

private struct SessionRow: View {
    let session: SleepSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.startTime, style: .date)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(timeRangeText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text(TimeFormat.duration(session.durationSeconds))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Theme.accent)
        }
        .padding(.vertical, 4)
    }

    private var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let start = formatter.string(from: session.startTime)
        let end = session.endTime.map { formatter.string(from: $0) } ?? "进行中"
        return "\(start) – \(end)"
    }
}
```

- [ ] **Step 2：创建 SessionDetailView.swift**

`Features/Report` 右键 → New File → Swift File → `SessionDetailView.swift`。粘贴：

```swift
import SwiftUI
import SwiftData
import AVFoundation

struct SessionDetailView: View {

    let session: SleepSession
    let fileStore: AudioFileStore

    @StateObject private var player = SimpleAudioPlayer()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    metaCard
                    playerCard
                    Spacer().frame(height: 30)
                }
                .padding(.horizontal, Theme.padding)
                .padding(.top, Theme.padding)
            }
        }
        .navigationTitle(session.startTime.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { player.stop() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.startTime, style: .date)
                .font(.title3).bold()
                .foregroundStyle(Theme.textPrimary)
            Text(TimeFormat.duration(session.durationSeconds))
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.accent)
        }
    }

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(label: "开始", value: session.startTime.formatted(date: .omitted, time: .shortened))
            row(label: "结束", value: session.endTime?.formatted(date: .omitted, time: .shortened) ?? "—")
            row(label: "存档", value: session.isArchived ? "已归档" : "7 天内自动清理整夜音频")
        }
        .padding()
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    @ViewBuilder
    private var playerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("整夜音频").font(.headline).foregroundStyle(Theme.textPrimary)

            if let relative = session.fullAudioPath,
               FileManager.default.fileExists(atPath: fileStore.url(fromRelativePath: relative).path) {
                HStack(spacing: 14) {
                    Button {
                        if player.isPlaying { player.pause() }
                        else { player.play(url: fileStore.url(fromRelativePath: relative)) }
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.isPlaying ? "播放中" : "点击播放")
                            .foregroundStyle(Theme.textPrimary)
                        Text(TimeFormat.duration(player.currentTime))
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
            } else {
                Text("整夜音频已被清理或尚未保存完成。")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding()
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).foregroundStyle(Theme.textPrimary).font(.system(.body, design: .monospaced))
        }
    }
}

@MainActor
final class SimpleAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0

    private var avPlayer: AVAudioPlayer?
    private var timer: Timer?

    func play(url: URL) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            avPlayer = try AVAudioPlayer(contentsOf: url)
            avPlayer?.delegate = self
            avPlayer?.prepareToPlay()
            avPlayer?.play()
            isPlaying = true
            startTimer()
        } catch {
            NSLog("Playback failed: \(error)")
        }
    }

    func pause() {
        avPlayer?.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        avPlayer?.stop()
        avPlayer = nil
        isPlaying = false
        stopTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.currentTime = self?.avPlayer?.currentTime ?? 0
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.stopTimer()
        }
    }
}
```

- [ ] **Step 3：Commit 暂缓**

---

## Task 13：SettingsView

**Files:**
- Create：`Nightingale/Features/Settings/SettingsView.swift`

- [ ] **Step 1：创建 SettingsView.swift**

`Features/Settings` 右键 → New File → Swift File → `SettingsView.swift`。粘贴：

```swift
import SwiftUI
import SwiftData

struct SettingsView: View {

    let fileStore: AudioFileStore
    @ObservedObject var permissions: PermissionManager

    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [SleepSession]

    @State private var showWipeConfirm = false
    @State private var storageBytes: Int64 = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                List {
                    Section("权限") {
                        permissionRow("麦克风", status: micStatusText, color: micStatusColor)
                    }
                    .listRowBackground(Theme.surface)

                    Section("存储") {
                        row(label: "录音文件", value: bytesText(storageBytes))
                        row(label: "记录数", value: "\(sessions.count)")
                    }
                    .listRowBackground(Theme.surface)

                    Section {
                        Button(role: .destructive) {
                            showWipeConfirm = true
                        } label: {
                            Text("一键清空所有数据")
                        }
                    }
                    .listRowBackground(Theme.surface)

                    Section("版本") {
                        row(label: "Nightingale", value: "Phase 1A")
                    }
                    .listRowBackground(Theme.surface)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("设置")
            .onAppear {
                permissions.refreshMicrophoneStatus()
                storageBytes = fileStore.totalBytesUsed()
            }
            .confirmationDialog("确认清空？", isPresented: $showWipeConfirm) {
                Button("清空所有录音", role: .destructive, action: wipeAll)
                Button("取消", role: .cancel) {}
            } message: {
                Text("所有整夜录音文件和 session 记录会被永久删除，不可恢复。")
            }
        }
    }

    private var micStatusText: String {
        switch permissions.microphoneStatus {
        case .granted: "已授权"
        case .denied: "已拒绝（请到系统设置开启）"
        case .notDetermined: "尚未请求"
        }
    }

    private var micStatusColor: Color {
        switch permissions.microphoneStatus {
        case .granted: Theme.accent
        case .denied: Theme.danger
        case .notDetermined: Theme.textTertiary
        }
    }

    private func permissionRow(_ name: String, status: String, color: Color) -> some View {
        HStack {
            Text(name).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(status).foregroundStyle(color).font(.subheadline)
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).foregroundStyle(Theme.textPrimary).font(.system(.body, design: .monospaced))
        }
    }

    private func bytesText(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1024 / 1024
        if mb >= 1024 {
            return String(format: "%.2f GB", mb / 1024)
        }
        return String(format: "%.1f MB", mb)
    }

    private func wipeAll() {
        // 删文件
        try? FileManager.default.removeItem(at: fileStore.recordingsDirectory)
        // 删记录
        for s in sessions { modelContext.delete(s) }
        try? modelContext.save()
        storageBytes = 0
    }
}
```

- [ ] **Step 2：编译**

`Command + B`。现在 AppRoot 里引用的 View 都有了，应该绿。如果报错，通常是打错字——仔细对照代码。

- [ ] **Step 3：Commit Task 10-13 的总成果**

```bash
cd /Users/eason-mini/workspace/nightingale
git add Nightingale/NightingaleApp.swift Nightingale/AppRoot.swift Nightingale/Features Nightingale.xcodeproj
git commit -m "feat: add TabView shell with Tonight/Report/Settings tabs"
```

---

## Task 14：端到端真机烟雾测试

**Files:** 无代码改动。纯手动验证。

- [ ] **Step 1：编译 + 跑到真机**

把 iPhone 插上 Mac → Xcode 顶部设备选择器选你的 iPhone（**不是**模拟器）→ `Command + R`。

如果弹 "Could not launch Nightingale because it is from an unidentified developer" → iPhone → 设置 → 通用 → VPN 与设备管理 → 信任开发者。

- [ ] **Step 2：主界面检查**

app 开启后能看到底部 3 个 Tab："今夜" / "报告" / "设置"。当前"今夜"页居中有"开始记录"大按钮。

- [ ] **Step 3：权限弹窗**

点"开始记录"→ 第一次会弹"Nightingale 想要访问麦克风"→ 允许。

- [ ] **Step 4：短时录音测试**

按钮变红色"结束记录"，上方显示计时在走。**把 iPhone 屏幕锁掉 30 秒**（按侧边电源键）→ 再点亮 iPhone（或从 app 切换器回来）→ 确认计时数字正确走过了 30 秒（证明锁屏未中断）。

点"结束记录"→ 按钮出现 loading "保存中" → 回到"开始记录"。

- [ ] **Step 5：报告页验证**

切到"报告" Tab → 应该看到一条记录，显示今天日期 + 时长 30 秒左右。

点进去 → 看到"整夜音频"卡片 + 播放按钮 → 点播放 → 应该能听到刚才 30 秒的环境声。

- [ ] **Step 6：设置页验证**

切到"设置"→ 权限显示"麦克风 已授权" → 存储 > 0 MB → 记录数 = 1。

- [ ] **Step 7：长录制测试（可选但建议）**

回到"今夜"→ 开始记录 → **插上充电器** → 锁屏 → 把 iPhone 放在床头 → 睡一晚（或至少 2 小时）→ 早上起来解锁 → app 应该还在"正在记录 X:XX:XX"状态 → 点结束 → 看报告 → 播放能听到你的呼吸声 / 鼾声。

**如果到天亮时 app 已经被杀掉了**：把现象记录下来告诉 AI，我们需要加强 background keep-alive 策略。常见原因：
- 电量耗尽
- iOS 系统低内存杀后台
- AudioSession 被其他音频 app 打断

- [ ] **Step 8：清空数据验证**

"设置"→"一键清空"→ 确认 → 回到"报告" → 应该是空状态。

- [ ] **Step 9：Commit 验收完成**

```bash
cd /Users/eason-mini/workspace/nightingale
git add -A
git commit --allow-empty -m "chore: Phase 1A smoke test passed (record, save, replay)"
git tag phase-1a-complete
```

---

## Phase 1A 验收标准

全部以下满足视为 Phase 1A 完成，可以进入 Phase 1B 规划：

- [x] app 能在真机跑起来
- [x] 开始录音 / 结束录音 按钮工作正常
- [x] 锁屏后录音不中断（至少 30 分钟以上）
- [x] 整夜（≥ 6 小时）录音能完整保存（这条是 Phase 1A 最关键的"硬仗"）
- [x] 报告列表能正确显示所有录音
- [x] 单晚详情页能播放音频
- [x] 设置页能显示权限和存储状态
- [x] 一键清空能删除所有数据
- [x] 所有单元测试绿色

---

## 开放问题（执行中遇到时对齐）

- 如果 iPhone 在整夜录制过程中被系统杀掉后台：需要加**静音保活播放**策略（让 AVAudioSession 持续 Active）。这不在 Phase 1A 初始计划内，因为实测才知道是否必要。
- Xcode 15 和 Xcode 16 的 UI 略有不同——如果截图式步骤中"点哪里"找不到，截图问 AI。
- SwiftData 在低 iOS 17.0 版本有几个已知 bug（如频繁 insert 崩溃）——升级 iPhone 到 iOS 17.2+ 可规避大多数。
- 免费开发者证书**每 7 天过期**。到期那天你会发现 app 启动失败——插 Mac、Xcode ▶️、重新部署即可。证书剩余天数 UI 提示放到 Phase 1B（需要先做更完整的设置页）。
