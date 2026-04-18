# Nightingale · 睡眠监测 iOS App 设计文档

- **创建日期**：2026-04-18
- **项目代号**：Nightingale（夜莺）
- **作者**：产品主 + AI 协作
- **状态**：设计阶段

---

## 1. 项目定位

### 1.1 一句话描述
一个**仅自用**的 iPhone app，利用 iPhone 麦克风 + Apple Watch Series 10 传感器，整夜记录睡眠中的音频事件（打呼、梦话、疑似呼吸暂停）和生理指标（心率、HRV、血氧、睡眠分期），早晨生成一份"睡眠实验室级"报告。

### 1.2 目标用户
- **唯一用户**：项目主自己（单人单机，不考虑多用户、多账户、分享）
- **不面向**：App Store 上架、家人共用、商业分发

### 1.3 产品气质
**硬核睡眠实验室（方向 A）+ 夜晚档案馆（方向 C）**的混合风格：
- **A 的内核**：尊重数据、可导出、可对照身体指标、UI 工具化不做鸡汤
- **C 的元素**：梦话自动转写形成日记、打呼可回放、叙事化晨间回顾

### 1.4 明确不做（Non-Goals）
- 不做多用户 / 多设备账号体系
- 不做云同步 / 云备份 / 任何服务器
- 不做社交 / 分享 / 排行
- 不做内容化的"睡眠教练"建议（方向 B 舍弃）
- 不做医疗诊断定性结论（只提供参考指标，所有风险提示都带"请咨询医生"免责）
- 不做第三方 SDK 集成（不打点、不崩溃上报、不广告）

---

## 2. 硬件与环境假设

| 项目 | 约定 |
|---|---|
| iPhone | 用户自有的 iPhone（型号待定，假设 iOS 17+） |
| Apple Watch | **Series 10**（血氧功能可用，需用户确认是否为美版——美版 SpO2 被阉割） |
| 开发机 | Mac（用户已有或待购） |
| 开发者账号 | **免费 Apple ID**起步（接受每 7 天重新部署的代价），后续如体验问题再升级到 $99/年 |
| 网络要求 | **无**。app 不调用任何网络接口，飞行模式也能正常工作 |

---

## 3. 交付与协作模式

### 3.1 路线 B：交钥匙模式
- 所有 Swift 代码由 AI 完整产出
- 用户的工作：在 Xcode 中新建项目、按说明粘贴代码到指定文件、按"运行"、在真机测试、反馈 bug
- 用户不被要求读懂 Swift 代码，只需能在 Xcode 里"粘贴 + 运行"
- 每次交付包含：
  - 完整可粘贴的代码文件
  - Xcode 操作步骤截图式说明（哪里点几下）
  - 权限 / 配置文件的具体改动指引（Info.plist、Capabilities）

### 3.2 迭代节奏
按 Phase 分阶段交付，每个 Phase 结束后：
- 用户在真机测试
- 确认该 Phase 功能达标后才进入下一 Phase
- 允许在 Phase 之间暂停（比如忙别的事情）

---

## 4. 架构设计

### 4.1 系统总图

```
┌─────────────────────────────────────────────────────────────┐
│                    Nightingale iOS App                       │
│                                                               │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │  录制引擎     │    │  分析引擎     │    │   UI 层      │  │
│  │              │    │              │    │              │  │
│  │ • 后台录音    │───▶│ • 打呼识别    │───▶│ • 首页       │  │
│  │ • HealthKit  │    │ • 梦话转写    │    │ • 当晚时间轴 │  │
│  │   同步       │    │ • 呼吸暂停判定│    │ • 趋势页     │  │
│  │ • 噪音监控    │    │ • 睡眠分期合并│    │ • 档案馆     │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
│                             ↓                                │
│                      ┌──────────────┐                       │
│                      │  本地存储层   │                       │
│                      │              │                       │
│                      │ • SwiftData  │ ← 元数据 / 事件       │
│                      │ • 文件系统    │ ← 音频文件            │
│                      │ • 自动清理    │ ← 每周任务            │
│                      └──────────────┘                       │
└─────────────────────────────────────────────────────────────┘
        ↑                                         ↑
  iPhone 麦克风                             HealthKit
                                                  ↑
                                        Apple Watch Series 10
```

### 4.2 四大模块职责边界

#### 录制引擎（Recording Engine）
- **输入**：用户点击"开始记录"按钮
- **职责**：
  - 申请并维持音频会话（AVAudioSession）
  - 开启后台持续录音，息屏不中断
  - 实时分帧（每 15 秒一个缓冲）把音频送给分析引擎
  - 并行从 HealthKit 拉取 Watch 传感器数据
  - 监测电量 / 存储空间，异常时通知用户
- **输出**：音频流分帧 + 传感器时间序列

#### 分析引擎（Analysis Engine）
- **输入**：录制引擎的音频帧 + HealthKit 时间序列
- **职责**：
  - **打呼识别**：用 SoundAnalysis + 苹果预训练分类器（`SNClassifierIdentifier.version1` 包含 "snoring" 类）
  - **梦话识别**：SoundAnalysis 判定是否 "speech" 类 → Speech 框架做 on-device 转写
  - **疑似呼吸暂停**：规则引擎——音频中检测到"持续呼吸声突然静默 ≥ 10 秒" **AND** Watch SpO2 在对应时间 3 分钟窗口内下降 ≥ 3%
  - **睡眠分期合并**：用 HealthKit 的 HKCategoryValueSleepAnalysis（iOS 16+ 有 asleepCore/asleepDeep/asleepREM 分类）
- **输出**：事件对象（时间戳 + 类型 + 置信度 + 关联音频片段路径）

#### 本地存储层（Storage Layer）
- **数据**：SwiftData（iOS 17+）管理结构化数据
- **文件**：沙盒内 `Documents/Recordings/` 存音频，`Documents/Clips/` 存事件片段
- **清理任务**：每日后台检查——超过 7 天的整夜音频删除；事件片段不自动删除；支持"手动归档"锁定某一晚

#### UI 层（User Interface）
- **技术**：SwiftUI + Swift Charts
- **顶层 Tab 结构**：
  1. **今夜**（控制录制、实时状态）
  2. **报告**（查看最近某晚的详细报告）
  3. **趋势**（周 / 月 / 年聚合图表）
  4. **档案馆**（事件列表、梦话日记、手动归档）
  5. **设置**（权限状态、存储管理、数据导出）

### 4.3 技术栈明细

| 场景 | 选型 | 理由 |
|---|---|---|
| UI 框架 | SwiftUI | 苹果主推，声明式，代码量小 |
| 最低系统 | iOS 17 | 可用 SwiftData、最新 Charts、SoundAnalysis 增强版 |
| 数据库 | SwiftData | iOS 17+ 官方方案，比 Core Data 代码少 60% |
| 图表 | Swift Charts | iOS 16+ 自带，功能够用 |
| 音频录制 | AVFoundation + AVAudioEngine | 能拿到实时帧，不只是录完整段 |
| 后台录音 | UIBackgroundModes: audio | 唯一合法方案 |
| 音频分类 | SoundAnalysis（SNClassifySoundRequest） | 苹果预训练模型含 "snoring" 类 |
| 语音转写 | Speech 框架 + `requiresOnDeviceRecognition = true` | 强制本地识别 |
| 传感器读取 | HealthKit（HKHealthStore） | 唯一合法通道 |
| 并发模型 | Swift Concurrency（async/await） | 现代、可读性高 |
| 后台任务 | BGTaskScheduler（BGProcessingTask） | 跑每日清理 |

---

## 5. 数据模型

### 5.1 主要实体（SwiftData Model）

```swift
// 伪代码，示意字段，具体类型在 Phase 1 实现时敲定

@Model
class SleepSession {  // 一晚睡眠
    var id: UUID
    var startTime: Date
    var endTime: Date?  // 为空表示还没结束
    var fullAudioPath: String?  // 整夜音频路径，7 天后被清空
    var isArchived: Bool  // 手动归档标记，不会被自动清理
    var morningNote: String?  // 晨间打卡
    var morningMood: String?  // emoji
    @Relationship(deleteRule: .cascade) var events: [SleepEvent]
    @Relationship(deleteRule: .cascade) var sensorSamples: [SensorSample]
}

@Model
class SleepEvent {
    var id: UUID
    var session: SleepSession?
    var timestamp: Date
    var duration: TimeInterval
    var type: EventType  // .snore / .sleepTalk / .suspectedApnea / .nightmareSpike
    var confidence: Double  // 0-1
    var clipPath: String?  // 事件前后各 15 秒的音频片段
    var transcript: String?  // 仅梦话事件有
    var metrics: [String: Double]  // 附加指标，如最低 SpO2、峰值 HR
}

@Model
class SensorSample {
    var session: SleepSession?
    var timestamp: Date
    var kind: SensorKind  // .heartRate / .hrv / .spo2 / .sleepStage / .temperature
    var value: Double
    var stringValue: String?  // 分期名称等
}

enum EventType: String, Codable { case snore, sleepTalk, suspectedApnea, nightmareSpike }
enum SensorKind: String, Codable { case heartRate, hrv, spo2, sleepStage, temperature, bodyMovement }
```

### 5.2 音频文件布局

```
Documents/
├── Recordings/
│   ├── 2026-04-17.m4a       // 整夜音频，AAC 64 kbps 单声道 16kHz，~50 MB/晚
│   ├── 2026-04-16.m4a
│   └── ...（最多保留 7 份）
├── Clips/
│   ├── <event-uuid>.m4a      // 15s 事件前 + 事件时长 + 15s 事件后
│   └── ...（永久保留，除非手动删除）
```

### 5.3 存储容量估算

| 类别 | 单位大小 | 节奏 | 占用 |
|---|---|---|---|
| 整夜音频 | ~50 MB | 每天 1 份，保留 7 天 | ~350 MB 稳态 |
| 事件片段 | ~300 KB/个 | 平均 30 事件/晚 | ~9 MB/晚 → 3 GB/年 |
| 结构化数据 | <100 KB/晚 | 永久 | 可忽略 |

用户可在**设置页**随时查看当前占用和清理旧事件。

---

## 6. 权限与隐私

### 6.1 必需权限
| 权限 | 申请时机 | 用途 | Info.plist key |
|---|---|---|---|
| 麦克风 | 首次点击"开始记录" | 整夜录音 | `NSMicrophoneUsageDescription` |
| 语音识别 | 首次出现疑似梦话 | 梦话转写（on-device） | `NSSpeechRecognitionUsageDescription` |
| HealthKit 读取 | 首次进入报告页 | 读取 Watch 传感器数据 | `NSHealthShareUsageDescription` + Capabilities |
| 通知 | Phase 3（智能闹钟） | 唤醒用户 | Notification authorization |

### 6.2 隐私原则（硬性约束）
- 所有数据**永远不离开用户的 iPhone**
- 不集成任何第三方 SDK
- Speech 转写强制使用 `requiresOnDeviceRecognition = true`
- 用户可在设置页**一键清空所有数据**
- 用户可在设置页**导出所有原始数据**（JSON + 音频 zip）用于自我备份或迁移

### 6.3 录音相关的伦理约束
- 这是单人自用 app，用户被告知自己的录音要上传到本地分析
- 如果用户后续打算让伴侣也在同房间被录音，**需要当面获得伴侣同意**——这条写进 README 的"使用须知"，app 内不做强制弹窗（自用项目不需要 UI 强制）

---

## 7. 分阶段功能清单

### 7.1 Phase 1 · MVP（预计 1-2 周 AI 协作）

**目标**：跑通"开始记录 → 整夜运行 → 起床看报告"的全流程

#### 功能清单
- [ ] **今夜页**：大按钮"开始记录" / "结束记录"；实时显示已录时长、电量、存储剩余
- [ ] **后台录音**：息屏后继续录，直到用户手动结束或电量 < 10%
- [ ] **Watch 数据同步**：结束录制时从 HealthKit 拉取时段内的心率、HRV、血氧、睡眠分期
- [ ] **打呼识别**：分析整夜音频，识别所有鼾声片段
- [ ] **事件片段生成**：每次打呼事件保存前后 15s 音频
- [ ] **当晚报告页**：
  - 睡眠时长（基于录制时长 + Watch 睡眠分期交叉验证）
  - 深睡 / 浅睡 / REM 饼图 + 时间轴
  - 心率曲线、SpO2 曲线（整夜）
  - 打呼事件时间轴（散点图，按次数分布）
  - 打呼总次数、总时长、最长单次
- [ ] **事件列表**：点击任一打呼事件可回放 15 秒片段
- [ ] **自动清理**：7 天前的整夜音频自动删（事件片段保留）
- [ ] **设置页**（极简版）：权限状态、存储占用、一键清空

#### 不在 Phase 1 的
- 梦话检测（Phase 2）
- 呼吸暂停判定（Phase 2）
- 多维度叠加时间轴（Phase 2）
- 趋势 / 周报（Phase 2）

### 7.2 Phase 2 · 核心增强（预计 1-2 周）

**目标**：把 A + C 的定位完整兑现

- [ ] **梦话检测 + 转写**：SoundAnalysis 判定语音 → Speech 框架 on-device 转写 → 存储为 SleepEvent
- [ ] **疑似呼吸暂停事件**：规则引擎合并音频 + SpO2
- [ ] **多维度叠加时间轴**（report 页核心组件）：心率 / SpO2 / 打呼 / 梦话 / 分期，同一条时间轴
- [ ] **档案馆 Tab**：
  - 梦话日记（按日期倒序，每条点进去可播放原始音频）
  - 事件搜索（按类型筛选）
  - 手动归档按钮（锁定某晚）
- [ ] **趋势 Tab**：
  - 近 7 天 / 30 天 / 90 天的事件数、睡眠时长、平均心率
  - 简易 AHI 估算（呼吸暂停事件数 / 睡眠小时数）
- [ ] **晨间打卡**：当晚报告页顶部的心情 + 一句话输入

### 7.3 Phase 3 · 高级功能（按需选做）

- [ ] **智能闹钟**：用户设定闹钟时间 + 起床窗口（如"7:00 前 30 分钟内的浅睡期"）→ 推送通知
- [ ] **PDF 导出**：当晚或任意时段的医学风格报告
- [ ] **梦话关键词搜索**：全文检索
- [ ] **手动标签系统**：在晨间打卡里加标签（"昨晚喝酒"、"运动日"、"加班"），趋势页支持按标签分组对比
- [ ] **夜惊检测**：REM 期心率 > 平均值 + 2 倍标准差 → 标记为 nightmareSpike 事件
- [ ] **环境噪音监控**：如果整夜环境噪音 > 阈值，在报告里提示"外界干扰"
- [ ] **梦话词云**（可视化档案馆）

---

## 8. 关键技术风险与应对

| 风险 | 影响 | 应对 |
|---|---|---|
| iOS 后台录音被系统杀掉 | 记录中断，用户醒来发现没数据 | 开启 `UIBackgroundModes: audio` + 播放静音音频保持会话活跃；监测中断事件并尝试恢复 |
| 免费开发者账号 7 天过期 | app 晚上启动不了 | 在 README 说明；app 内首页显示"证书剩余 N 天" |
| 手机电量不足跑不到天亮 | 记录不完整 | 电量 < 15% 时本地通知提醒用户插电；<10% 时自动结束并保存已录部分 |
| SpO2 在美版 Series 10 不可用 | 呼吸暂停判定降级为"仅音频" | 在 HealthKit 查询失败时自动降级；设置页显示"SpO2 不可用" |
| SoundAnalysis 打呼分类误报（例如空调声） | 打呼次数虚高 | 置信度阈值 0.7；事件列表允许用户手动标记误报；被标记的类型后续用于校准 |
| Speech 框架 on-device 准确率有限 | 梦话转写文不对题 | 保留原始音频，转写只作为辅助索引；转写错了用户可播放验证 |
| HealthKit 数据有延迟（Watch 同步要几分钟） | 刚起床看报告数据不全 | 报告页有"刷新"按钮；自动在结束后等待 5 分钟再生成最终报告 |
| 手机放床上被压到或掉地上 | 录音质量差 | app 内提供"最佳摆放位置"说明；事件时检测到音频信噪比异常时给予提示 |

---

## 9. UI / UX 设计原则

### 9.1 总体风格
- **深色优先**（配合夜晚使用场景）
- **数据密度中等**（方向 A 的"实验室"感，但不做到 Excel 的程度）
- **不做过度动画**（避免夜间使用时分心）
- **中文界面**（自用，不做国际化）

### 9.2 首页（今夜 Tab）
- 大面积黑色背景
- 中央一个巨大的圆形按钮：空闲态"开始记录" / 运行态"结束记录"
- 运行态下方显示：已录时长、当前电量、存储剩余
- 运行态禁止进入其他 Tab（避免误操作中断录制）—— 通过顶部 Tab 禁用实现

### 9.3 报告页
- 顶部"晨间打卡"模块（Phase 2+）
- 下方是长滚动页，按模块展示：
  1. 睡眠时长 + 分期饼图
  2. 多维度叠加时间轴（核心）
  3. 事件列表（可展开）
  4. 声音片段快速播放

### 9.4 档案馆页（Phase 2+）
- 以梦话日记为主入口，时间倒序列表
- 每条：日期 + 转写摘要 + 播放按钮
- 右上角过滤：按类型（打呼 / 梦话 / 呼吸暂停）

### 9.5 设置页
- 权限状态卡片（麦克风、语音识别、HealthKit、通知）
- 存储管理卡片（整夜 / 事件片段 / 结构化数据各占多少，清理按钮）
- 数据导出（JSON + zip）
- 一键清空
- 免费账号剩余天数提示
- 版本号 + 开源许可信息（如有）

---

## 10. 项目结构（Xcode 工程骨架）

```
Nightingale.xcodeproj
├── Nightingale/
│   ├── App/
│   │   └── NightingaleApp.swift          // 入口，@main
│   ├── Features/
│   │   ├── Tonight/                      // 今夜 Tab
│   │   ├── Report/                       // 报告 Tab
│   │   ├── Trends/                       // 趋势 Tab（Phase 2）
│   │   ├── Archive/                      // 档案馆 Tab（Phase 2）
│   │   └── Settings/                     // 设置 Tab
│   ├── Engine/
│   │   ├── Recording/                    // 录制引擎
│   │   ├── Analysis/                     // 分析引擎
│   │   │   ├── SnoreDetector.swift
│   │   │   ├── SleepTalkDetector.swift   // Phase 2
│   │   │   └── ApneaDetector.swift       // Phase 2
│   │   └── HealthKitSync.swift
│   ├── Storage/
│   │   ├── Models/                       // SwiftData 模型
│   │   ├── AudioFileStore.swift
│   │   └── CleanupTask.swift
│   ├── Shared/
│   │   ├── Views/                        // 通用组件
│   │   ├── Theme/                        // 颜色、字体
│   │   └── Extensions/
│   └── Resources/
│       ├── Assets.xcassets
│       └── Info.plist
└── NightingaleTests/                     // 单元测试（可选）
```

---

## 11. 开发流程约定

### 11.1 每个 Phase 的交付物
1. **代码包**：按文件路径组织的完整 Swift 源文件
2. **Xcode 设置清单**：需要改动的 Info.plist key、Capabilities 勾选、Build Settings
3. **测试指南**：该 Phase 该测哪几个场景（例如 Phase 1 测"手机放床头 + 录 1 小时 + 看报告"）
4. **已知问题清单**

### 11.2 Bug 反馈流程
- 用户在真机遇到问题 → 截图 / 描述 → AI 定位并修复 → 给补丁代码
- 不追求一次做对，追求快速迭代

### 11.3 版本标记
- 每个 Phase 完成后打一个 git tag：`v0.1-mvp`、`v0.2-core`、`v0.3-advanced`
- 不强制写 Changelog，但每次重要改动 commit 信息要清楚

---

## 12. 开放问题（待后续决定）

以下问题不阻塞启动 Phase 1，但在对应阶段前需要对齐：

| 问题 | 触发阶段 | 备注 |
|---|---|---|
| iPhone 具体型号是什么？ | Phase 1 启动前 | 影响低电量阈值设置 |
| Apple Watch 是否为美版？ | Phase 2 呼吸暂停功能前 | 美版 SpO2 不可用则降级 |
| 是否要 app 图标 / 启动页设计？ | Phase 1 中 | 可用 SF Symbols 临时替代 |
| Phase 3 智能闹钟需不需要做？ | Phase 2 完成后 | 看 Phase 2 实际体验 |
| 是否需要 iPad / Mac 版本？ | 目前否，永久保留为 No | 自用场景用不上 |

---

## 13. 成功标准

**Phase 1 成功标准**：连续记录 3 晚睡眠都能跑完，早晨能看到报告，打呼事件能回放。

**Phase 2 成功标准**：梦话能被识别并至少 60% 的转写可辨识；呼吸暂停事件和用户主观感受（"那晚憋醒"）有对应关系。

**项目整体成功标准**：用户在连续使用 1 个月后，不再需要其他睡眠监测 app；能拿出数据和医生讨论自己的睡眠呼吸状况。

---

## 14. 附录

### 14.1 参考资料（苹果官方）
- [Sound Analysis](https://developer.apple.com/documentation/soundanalysis)
- [Speech Framework](https://developer.apple.com/documentation/speech)
- [HealthKit](https://developer.apple.com/documentation/healthkit)
- [Background Audio](https://developer.apple.com/documentation/avfoundation/audio_session_programming_guide)
- [BGTaskScheduler](https://developer.apple.com/documentation/backgroundtasks)

### 14.2 术语表
- **AHI**：Apnea-Hypopnea Index，睡眠呼吸暂停低通气指数。每小时呼吸暂停 + 低通气事件次数。医学上 ≥ 5 为轻度、≥ 15 为中度、≥ 30 为重度。
- **HRV**：Heart Rate Variability，心率变异性。夜间 HRV 是身体恢复状态的良好指标。
- **REM**：Rapid Eye Movement，快速眼动睡眠，做梦主要发生阶段。
- **On-device**：在用户设备本地处理，不经网络、不经苹果服务器。
