# KeyStatsMac 项目状态

核对日期：2026-10-12。本文以当前源码、Git 提交和本地工作区为准，不把“已实现”视为“已发布”。

本文记录产品状态、与继承基础的差异和技术决策；开发约束见 [AGENTS.md](AGENTS.md)，技术资料入口见 [docs/README.md](docs/README.md)，实验操作说明见各 prototype 的 README。

## 项目定位与边界

> 隐私优先、低功耗的 macOS 物理交互统计与可视化工具。

当前在成熟 upstream 基础上发展分应用展示和长期累计键盘可视化，不重写输入后端。用户可见 UI 可以逐页使用 SwiftUI，AppKit shell 和稳定后端继续保留。

- 这不是 keylogger：不记录实际输入文本、按键顺序、可重建内容的原始输入序列、点击坐标或完整鼠标轨迹。
- 采集和保存的是聚合统计，不通过新功能增加原始输入历史。
- 本地交互统计与产品 Analytics 严格分离；PostHog 不接收键鼠统计、分应用数据或用户 App 列表。
- 准确统计、易读性和低功耗优先；视觉只在用户查看时消耗额外性能。
- History Replay 的目标是回看每日聚合后的累计状态，不是回放原始按键。

## 当前交付状态

### 已提交的基础与产品能力

本轮整理前的基础提交为 `4edf43f`（2026-09-19，提交说明 `+Interaction Profile v0`）。提交名称不等于实际覆盖范围：

| 提交 | 日期 | 实际内容摘要 |
| --- | --- | --- |
| `1e1ed8c` | 2026-09-01 | 菜单栏 100ms coalescing、测试补强、仓库文档卫生 |
| `f3d20fa` | 2026-09-06 | 真实 StatsManager 的 Environment 注入和隔离测试 |
| `608f425` | 2026-09-06 | 跨日 pending-save 数据保全、历史日期 identity 修复 |
| `9cbc317` | 2026-09-17 | Interaction Profile 纯计算器、System Media Keys、vendored Helper 同步 |
| `4edf43f` | 2026-09-19 | Per-App Key Breakdown、App Detail Dashboard、Profile UI 和日期范围查询接线 |

Analytics consent、PID cache 生命周期、per-app key counts、Scroll Session 和 identifier 整理也已存在于提交历史中；不是当前待提交的新功能。

### 本轮分组保存的已实现能力

| 能力 | 当前状态 | 边界 |
| --- | --- | --- |
| Per-App Keyboard Heatmap | 已接入 App Detail，和 Key Breakdown 分页切换 | 共享原有 AppKit renderer，不新增采集或 schema |
| Physical Key Mapping | 纯数据层；旧 Heatmap 函数改为薄 adapter | 修复 literal `+` / `Cmd++`，保留 unsupported |
| Keyboard Layout Model | 固定 Mac-style 布局，2D renderer 已读取它 | 6 行、77 个键帽；不支持布局变体 |
| Cumulative Keyboard Snapshot | 纯累计计算和 StatsManager display-history 查询 | 按需派生，不持久化，不自动刷新 |
| First Tracked Day / Day Index | 纯日历日语义及 StatsManager 查询 | 不是 active-day count |
| Stable Count → Progress | 固定 count-only 曲线及测试 | 不替换现有相对 Heatmap normalization |
| Keyboard Atelier | 独立 prototype，保留 Porcelain v1 / v2 | 未进入正式 App 页面、主工程或发布流程 |

上述能力按共享键盘底座、Per-App Heatmap、累计快照与日期语义、Stable Progress、独立 Atelier prototype 分组保存为本地提交。相关新增 Swift 文件和 Xcode / SwiftPM 注册一起提交；已提交不代表已发布，Atelier 仍未接入正式产品。

## 继承基础与稳定输入链路

项目基于 [debugtheworldbot/keyStats](https://github.com/debugtheworldbot/keyStats)。这里的 upstream 差异指项目继承时的基础，不宣称已对照远端最新版本。

继承能力包括 Helper / CGEventTap / XPC / 权限、全局键位和组合键计数、鼠标点击与距离、scroll distance、KPS/CPS、每日历史、全局 Keyboard Heatmap / Key Breakdown、App Stats 基础、Sparkle 和 E2EE Sync。

正式采集链路不变：

```text
macOS events
→ KeyStatsHelper / EventTapController
→ PayloadBuilder / HelperXPCListener
→ XPC / HelperXPCClient
→ RemoteEventProcessor
→ StatsManager
→ 本地聚合与持久化 / UI
```

不存在主 App 的 InputMonitor 采集架构。除明确缺陷或需求外，不重写 Helper、XPC、StatsManager、持久化兼容和权限处理。

## KeyStatsMac 的已完成差异

### Analytics Consent

`AnalyticsManager` 是唯一 PostHog 入口。consent key 为 `analytics.optIn.v1`，缺失即 false；关闭时不初始化 SDK、不发送事件，tracking 安全 no-op。当前仍未提供正式 Settings 开关 UI。

### Menu Bar Update Coalescing

继承实现每个统计事件都触发菜单栏 SwiftUI / NSStatusItem 刷新；当前统计逐事件精确更新，菜单栏最高约 10Hz，首次可立即更新，burst 合并后读取最新统计，不使用常驻 repeating timer。

原有 `numericText` 和数字 animation 已保留；移除动画、layout/publication deduplication 是定位阶段实验，不作为最终修复能力。

此前真人 Instruments 开发测试中，快速输入从约 43% 单核 CPU，降至一次选定 12 秒区间中约 71ms CPU Weight，即约 0.6% 平均单核 CPU。该结果是 Debug + 特定真人 workload，不是 Release benchmark，也不是本轮重测。

### App Attribution / Per-App Key Distribution

- `AppActivityTracker` 监听 App termination，按 PID 和 bundle ID 清理对应缓存，避免迟到通知误删复用 PID；保留 display-name cache。
- `AppStats.keyPressCounts` 与总量一起累计，复用 canonical naming；旧 JSON 缺失字段时为空字典。
- history、import/merge 和 `appStatsSummary(range:)` 保留并聚合 per-key 数据。
- per-app 数据不进入 Analytics 或新增 Sync 字段。

### App Detail Dashboard / Key Breakdown / Per-App Heatmap

App Stats 的 App 名称区域与 disclosure 入口打开原生 sheet；AppKit shell 内使用 SwiftUI 内容。关闭时由 presenter dismiss，清理 presentation state，避免关掉一次后无法再打开。

- Today / Last 7 Days / Last 30 Days / All Time 沿用现有范围。
- App 的总量和 per-key 数据来自 `appStatsSummary(range:)`，Profile 来自同范围的 `interactionProfiles(range:)`。
- Key Breakdown 展示完整可用列表，不是 Top N；按次数降序、键名稳定打破平局。
- 左右修饰键仅在 Breakdown 展示整理中合并；literal `+`、组合键和 Fn aliases 保持完整事件语义。
- 方向键仅在展示层本地化为 Left Arrow 等，不修改 canonical 存储。
- coverage 根据 named event counts 与权威 total 判断。无活动、旧数据无明细、部分明细分开显示；不伪造缺失历史。
- 完整 coverage 只显示总次数；不完整时显示可用明细数量并说明旧历史缺失。
- 当前 Per-App Heatmap 直接使用原始 `AppStats.keyPressCounts`，不从整理后的 Breakdown rows 反推。
- Heatmap / Breakdown 可切换；Heatmap 默认显示。无明细或只有布局不支持的键时给出说明并引导查看 Breakdown。
- 英文、简体和繁体文案均存在。sheet 使用打开时 snapshot，没有持续输入订阅或常驻刷新 timer。

App Stats / Profile 仍使用本机分应用历史；不能把它和下文包含远端 shard 的全局 display-history 语义混为一谈。

### Interaction Profile v0

纯计算器已接入 App Detail 卡片，不再是“只有数据层、没有 UI”：

- positive-only mid-rank percentile；零值不进入 cohort，ties 同分。
- Keyboard 使用 keyPresses；Pointer 仅使用 totalClicks，当前没有 per-app mouseDistance。
- Scroll 对有正值的 distance/session 排名取平均，保留两个 raw components 与 cohort evidence。
- UI 对无活动和不可排名状态显示说明，不把单样本 0.5 当成可信排名。
- 三个 score 是各维度在当前用户 App 中的独立相对排名，不是交互构成比例，不生成 Keyboard-heavy 等标签。
- 按需计算，不持久化，不新增采集、Analytics 或 Sync schema。

### Scroll Session

沿用原有 scrollWheel 和 scroll distance 链路，读取公开 CGEvent phase / momentum / continuous 字段。`began → changed… → ended` 计 1 次；momentum 不另计，cancelled 或无 began 的 ended 不计。

`DailyStats` / `AppStats.scrollSessions` 旧数据默认 0，沿用 delayed persistence。此前 Finder 1 次、Chrome 2 次、归因与重启持久化已做真机开发验证，不是本轮重测。App Detail 的 Scroll evidence 已展示 session 数；App Stats 主列表没有独立 session 列。

这不是 Trackpad Gesture：公开 API 不能可靠区分触控板、Magic Mouse 等连续滚动设备，不使用设备猜测或无 phase 的超时拼接。

### System Media Keys / Vendored Helper

- 原有普通 F-key 路径保留；亮度、音量、静音、播放及键盘背光采用独立语义名，不能把 BrightnessUp 等当成 F2/F12。
- 原有 listen-only tap 增加 NX_SYSDEFINED，经公开 NSEvent bridge 和白名单过滤；只记录首次 key-down，过滤 key-up / repeat。
- 可选 `mediaKeyCode` payload 复用既有 XPC 接口；只进入全局统计，不错误归因到当前 App。
- 全局 Key Breakdown 可展示名字；固定键盘布局没有对应键帽，Physical Mapping 保留为 unsupported。
- 此前已完成主要亮度、音量、播放键开发真机验证；不等于所有硬件键、Fn 路径和升级权限场景都验证完毕，本轮没有重测真实输入。
- vendored Helper 已在 `9cbc317` 中更新，不再是“源码有、vendor 旧”。当前记录 cdhash 为 `7d49543089f6c0ef30751f56e2dfd6554634919d`。
- DMG 流程先校验 vendor，再覆盖 Xcode 嵌入的 Helper；hash 一致只证明 bundle 与记录一致，不代替未来源码/产物同步和真机验证。

### StatsManager Testability / Persistence Reliability

- 真实 StatsManager 进入 SwiftPM；Environment 注入隔离 UserDefaults、clock、calendar、date formatter 与调度/副作用。
- 正式 singleton 和 live-only 连接位于 `StatsManagerLiveEnvironment.swift`；仍使用 standard defaults、原有调度和未额外冻结 calendar/timezone 的 DateFormatter。
- rollover 在替换 currentStats 前归档上一日完整最新 snapshot，不依赖 delayed-save 已执行。
- 合法 yyyy-MM-dd history key 是记录当时的本地日期 identity，内部 date 与 key 对齐；非法 key 才 fallback。
- 每日记录是完整 snapshot，不是 additive fragment；normalization collision 不 merge。合法 key 优先，多个非法 key 按原 key 字典序选择第一个。

## 共享键盘数据层：职责与语义

```text
全局 display-aggregated daily history
→ CumulativeKeyboardTimeline / CumulativeKeyboardSnapshot
→ canonical whole-event keyPressCounts
→ PhysicalKeyMapping
→ physical participation counts → KeyboardUsageProgress
                         KeyboardLayout → renderer

本机 AppStats range summary
→ AppKeyBreakdown → 完整组合键列表
→ PhysicalKeyMapping + KeyboardLayout → 共享 2D Heatmap
```

### PhysicalKeyMapping

输入聚合键名和计数，返回 `counts` / `unsupported`。一次 Cmd+C 分别增加 Cmd 与 C；物理键参与数之和可以高于事件总量。

- literal `+` 映射到当前布局的 `=`；`Cmd++` / `Shift++` 不再丢失末尾加号。
- 保留左右 Cmd/Shift/Option；generic modifier 仍是 generic，不猜左右。
- F13+、Enter、Home/End、media keys、unknown KeyXX 等不猜键帽，保留 unsupported。
- 非正计数忽略；不修改原始存储。旧 `keyboardHeatmapCounts(from:)` 只转接这层。
- renderer 原有 direct-then-generic fallback 保留，不借此重新设计语义。

### KeyboardLayout / 现有 Heatmap

`KeyboardLayout.macStyle` 是 Foundation-only 固定布局：6 行、77 个键帽，包含 ID、label/symbol、相对宽高、spacing、箭头位置及 fallback IDs。supportedKeyIDs 从布局派生，包含可见键和 generic fallback，不是只有 77 个 ID。

原 AppKit renderer 从 controller 文件提取到 `KeyboardHeatmapView.swift`；全局与 per-app 共用，SwiftUI 只通过轻量 Representable 嵌入。全局 controller 的日期切换仍在原处。renderer 负责 frame、颜色、badge、tooltip；相同 per-app snapshot 不重复 apply。

现有 Heatmap 继续采用相对 normalization：`(log(count + 1) / log(maxCount + 1))^0.82`。没有换成长久稳定 progress，也没有新增键帽或 ANSI/ISO/JIS variants。

### CumulativeKeyboardSnapshot / KeyboardTrackingPeriod

- StatsManager 的累计和 tracking-period 查询使用规范化后的全局 display history，包含未落盘 current snapshot、可用远端 shards，排除当前设备远端副本的重复统计。
- 纯 timeline 按历史 dayKey 排序累计；权威 total 和可用 whole-event details 分开，缺失明细不补造。
- 截止查询返回不晚于目标的最近已有 snapshot；不生成缺失日期，首次记录前为 nil。
- First Tracked Day 是最早 keyPresses > 0 的历史日，旧数据无 per-key 明细仍算；空记录、mouse/scroll-only 不算。
- Day N 使用 Calendar 日历日差 + 1，中间没记录仍计时间，目标早于起点为 nil；支持缺记录目标日与 DST。
- 查询不新增存储、Timer 或 live refresh。完整 timeline 会物化多份累计字典，只看一个 cutoff 时应使用单 snapshot 查询。

### KeyboardUsageProgress

count-only 固定 soft-saturation logarithmic 曲线：

`1 - exp(-log(2) × log1p(count / 100) / log1p(10000 / 100))`

非正 count 为 0，10,000 为 0.5；随 count 单调增长并保留长期 headroom，与其他键、用户 max、日期和 percentile 无关。只接受物理 count，不重新解析组合键。默认锚点集中在一处，修改会改变产品尺度，需单独审查。

## Keyboard Atelier：隔离实验，不是正式产品

位置：`Prototypes/KeyboardAtelier/`。独立构建脚本直接编译共享纯数据文件，不注册到主 Xcode 工程、SwiftPM 或 DMG 流程。当前脚本构建 arm64 macOS 13+，不是 universal 发布产物。

- Porcelain v1 保留 CoreGraphics 表现；v2 使用真实 SceneKit 键帽、底板和脚垫几何。
- 最新 v2 为居中正交相机，无画面内斜转；空格键侧实际抬起约 5°，键帽、刻字随整体倾斜，统一光源。
- 可比较已落盘真实数据、固定低/中/成熟模拟状态，以及灰白几何模式。
- 显示日期、Day N、累计总量、每键次数和 stable progress；支持查看精确 count / 保存图片。
- v2 按数据/灰白状态变化生成静态图并缓存；无 SCNView 持续渲染、Timer 或持续动画。此设计不等于已经完成 Instruments 性能验收。
- 真实数据适配器直接只读本机 preference plist，不启动 StatsManager / Helper，不申请权限，不运行 Analytics 或网络。
- 该磁盘快照不包含未落盘输入或远端 Sync cache；不能冒充正式 display aggregation。正式接入时应使用 StatsManager 的显示查询。
- 解码失败明确显示错误，不静默用模拟数据冒充真实数据。
- 视觉仍在迭代，没有最终验收；不替换现有 Heatmap、不接 History Replay / Live Update。

## 标识符、签名与发布边界

identifier 保持冻结：

| 用途 | 值 |
| --- | --- |
| 主 App | `com.xuanlprk.KeyStatsMac` |
| Helper / XPC Mach service / LaunchAgent label | `com.xuanlprk.KeyStatsMac.helper` |

当前 Debug 主 App / Helper 配置使用 Apple Development；Release 配置仍为 ad-hoc，发布脚本和 vendor 签名不能等同于已完成 Developer ID 发布。Helper cdhash 或签名身份变化可能影响 Accessibility 授权，禁止为了整理命名主动变更。

发布前仍需单独确认 Developer ID、Hardened Runtime、notarization/stapling、XPC signer validation、自己的 Sparkle feed/key、Helper 升级权限连续性、Sparkle 原地升级、重装及重启/登录冷启动。旧 upstream Helper/LaunchAgent 并存或迁移策略也未作为完整发布流程验收。

## 测试与当前验证

2026-10-12 本轮实际运行：

- 完整 SwiftPM：**186 个 XCTest，0 failures**。数量是本次工作区快照，不是永久保证。
- KeyStats scheme Debug：**BUILD SUCCEEDED**，未启动 App 或安装 Helper。
- `scripts/check_vendored_helper.sh`：实际 cdhash 与记录一致。
- 测试覆盖真实 StatsManager、模型/兼容、归因缓存、consent、Scroll Session 状态、Profile/Breakdown presentation、Physical Mapping、Layout、累计 snapshot、Day Index 和 Progress。
- 不覆盖真实 TCC/Accessibility、完整 XPC 运行、不同硬件媒体键、真实 Trackpad 语义、NSStatusItem 性能或最终视觉验收。
- 本轮在临时暂存快照重跑 prototype build-only 和 geometry smoke：77 键变换后的中心命中、底部抬起/后脚接地、neutral image 与缓存复用通过；命令退出码为 0，日志有一条系统 sandbox-extension warning。2026-10-06 另有完整入画检查记录；这些都不是持续能耗测试或最终视觉验收。
- 本轮 Debug 有 Helper Info.plist 同时出现在 Copy Bundle Resources 的 warning；未在文档整理中改工程。
- `AGENTS.md` 仍记有旧 114 测试快照；本轮只更新 PROJECT，未顺手改它。

当前机器默认 xcode-select 指向 CommandLineTools。本轮通过 `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` 使用完整 Xcode 运行测试/构建，没有全局切换工具链。

## 尚未实现 / 暂缓

- 正式累计 2.5D Keyboard 页面、最终视觉规格、History Replay 和 Live Update。
- Keyboard Interaction Signature：仅调查过 aggregate per-key 分类；未实现 classifier，不把 printable key 命名为 Text Entry。
- 完整后台 pinch/rotate/系统 Space swipe/pressure：独立公开 API 调研后未接入；不使用私有 Multitouch/IOHID hack。
- Privacy Center 与 Analytics Settings 开关。
- per-app mouseDistance、per-app middle click、固定布局外键帽/布局变体。
- Sync 扩展、同步 secret Keychain 迁移和发布基础设施：不得因本文列出就自动实施。
- Windows 扩展、全量 SwiftUI rewrite、无实测依据的大规模性能重构。

本轮已按依赖分组保存本地提交，未 push、创建 PR、deploy 或发布。下一步先审查这些提交与 Atelier 视觉，再由具体产品需求决定是否接入正式页面；后续 Git 或远端操作仍需用户明确授权。
