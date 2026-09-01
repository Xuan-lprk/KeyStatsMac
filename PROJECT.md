# KeyStatsMac 项目状态

`PROJECT.md` 用于记录 KeyStatsMac 当前的产品方向、技术基础、已完成差异和阶段性决策。它不是面向用户的安装说明，也不是按提交排列的 changelog。

## 项目定位

KeyStatsMac 正在从一个键鼠统计工具逐步发展为：

> 隐私优先、低功耗的 macOS 物理交互统计与可视化工具。

长期方向包括：

- 键盘、鼠标及可通过公开 API 可靠获取的其他物理交互统计。
- 长期累计数据的高质量可视化。
- Keyboard Visualization / Growth Keyboard。
- History Replay。
- Interaction Profile。
- 分应用交互统计。
- Privacy Center。
- 用户可见 UI 逐步迁移到 SwiftUI。
- 后台长期运行保持低 CPU、低内存、低 wakeups 和低磁盘写入。

KeyStatsMac 不是 keylogger。产品边界是：

- 不记录用户实际输入的文本。
- 不记录按键顺序，不保存可重建用户内容的原始输入序列。
- 不保存鼠标点击坐标或完整鼠标轨迹。
- 键盘、鼠标和分应用交互数据以聚合统计形式保存在本地，主要用于展示给用户自己。
- PostHog 只用于了解用户如何使用 KeyStatsMac 产品本身，不上传本地键鼠统计、分应用统计或历史交互数据。

## 从 upstream 继承的基础

当前项目基于 [`debugtheworldbot/keyStats`](https://github.com/debugtheworldbot/keyStats)。成熟后端和主要产品能力来自 upstream，包括：

- `KeyStatsHelper`。
- listen-only `CGEventTap`。
- Helper → XPC → 主 App 的输入事件链路。
- Accessibility / TCC 权限流程。
- 键盘总量与每键统计。
- 鼠标点击统计。
- 鼠标移动距离与滚动距离。
- KPS / CPS。
- 分应用聚合统计。
- 每日数据、历史数据与持久化兼容逻辑。
- Keyboard Heatmap。
- All-Time Stats / App Stats。
- Sparkle 更新基础。
- E2EE 多设备同步基础。

这些能力是 KeyStatsMac 的稳定起点，不应被误写成 KeyStatsMac 新增功能，也不应仅为了“现代化”而重写。

## KeyStatsMac 相比 upstream 的已完成改动

### Analytics Consent

Upstream 在 App 启动时默认初始化 PostHog。KeyStatsMac 新增集中式 `AnalyticsManager`：

- consent key 为 `analytics.optIn.v1`。
- 默认关闭；key 不存在时视为未授权。
- 只有用户主动 opt-in 后才初始化 PostHog。
- Analytics 关闭时所有 tracking 调用安全 no-op。
- 所有事件统一经过 `AnalyticsManager`，不得绕过它直接调用 PostHog SDK。
- Analytics 不允许包含本地键鼠统计、分应用交互统计或用户使用的 App 列表。

目前只有后端 consent 机制，尚未实现 Settings UI 开关。

### Menu Bar Update Coalescing

Upstream：

- 每次键盘或鼠标统计事件都会直接触发菜单栏 SwiftUI / `NSStatusItem` 刷新。

KeyStatsMac：

- 统计仍逐事件准确处理。
- 菜单栏 UI 刷新合并到最高约 10 Hz。
- burst 期间刷新时读取最新统计，不丢失统计数据。
- 不使用常驻 10 Hz timer，idle 时不产生额外周期 wakeup。
- 真人 Instruments 测试中，快速输入时主 App CPU 从修改前约 43% 单核 CPU，降至一次选定 12 秒输入区间中的约 0.6% 平均单核 CPU。
- 上述数值来自 Debug 构建和真人 workload 的开发测试，不作为正式 Release benchmark。

### App Attribution Reliability

Upstream 的 `AppActivityTracker` 会缓存 PID 到 App identity 的映射，但不会在 App 退出时及时清理，存在 macOS 复用 PID 后错误归因的风险。

KeyStatsMac 已：

- 监听 `NSWorkspace.didTerminateApplicationNotification`。
- App 退出时清理对应 PID cache。
- 同时匹配 PID 和 bundle ID，避免迟到的退出通知误删已被新进程复用的 PID。
- 保留可安全复用的 bundle ID → display name cache。
- 为缓存清理和 PID reuse 场景补充测试。

### Per-App Key Distribution

Upstream 的 `AppStats` 只有每个 App 的按键总量等聚合数据。KeyStatsMac 新增：

- `keyPressCounts: [String: Int]`。
- 全局每键计数增加时，对应 App 的每键计数同步增加。
- 复用现有 canonical key naming，不建立第二套键名体系。
- 旧 JSON 缺少该字段时解码为空字典。
- 只保存累计计数，不记录顺序、时间戳序列、输入文本或原始事件历史。

该数据为未来 per-app Keyboard Heatmap 和 Interaction Profile 提供基础，目前没有新增 UI、Analytics 或 Sync 字段。

### Scroll Session

Upstream 已有 `scrollWheel` 事件链路和 scroll distance 统计。KeyStatsMac 在此基础上新增的是 **Scroll Session 聚合计数**，不是“新增滚动统计”。

- Helper 通过 CoreGraphics 读取 scroll phase、momentum phase 和 continuous 标记。
- phase 数据沿用现有 Helper → XPC → `RemoteEventProcessor` → `StatsManager` 链路。
- 一次 `began → changed… → ended` 只记为 1 个 session。
- 多个 `changed` 不重复计数。
- momentum 属于原 session，不创建第二个 session。
- cancelled 和缺少对应 began 的 ended 不计数。
- `DailyStats` 和 `AppStats` 均保存累计 `scrollSessions`，旧 JSON 默认解码为 0。
- 沿用延迟持久化，不增加 Timer、global monitor 或额外保存频率。

真实运行已验证：

- Finder 单次滚动准确增加 1。
- Chrome 两次明确分开的滚动准确增加 2。
- 分应用归因正确，原有 scroll distance 正常增加。
- App 重启后从持久化值继续累计。

**Scroll Session 不等于 Trackpad Gesture。** 公开 API 无法可靠区分 Trackpad、Magic Mouse 和其他支持连续精确滚动的设备，因此产品和代码均不把它命名为 Trackpad Scroll。

### Trackpad Feasibility Research

已在主仓库之外完成独立 `TrackpadProbe` 技术验证，未接入 KeyStatsMac 正式代码。

结论为“部分值得”：

- 公开 API 可以在后台可靠获取普通 Scroll，并可观察 phase / momentum 生命周期。
- pinch、rotate、系统 Space 三指/四指 swipe、Force Click 等无法通过公开 API 在全局后台状态下稳定获取。
- 近期不实现完整 Trackpad Gesture 统计。
- 不使用私有 `MultitouchSupport.framework`、私有 Multitouch API 或 IOHID hack。

### Product Identity / Identifier

当前 identifier 已冻结为：

- 主 App：`com.xuanlprk.KeyStatsMac`
- Helper：`com.xuanlprk.KeyStatsMac.helper`
- XPC Mach service：`com.xuanlprk.KeyStatsMac.helper`
- LaunchAgent label：`com.xuanlprk.KeyStatsMac.helper`

Debug 真机已验证 Helper 安装、LaunchAgent、XPC、Accessibility 和 Scroll Session 均正常工作。除非发现明确技术错误，不再修改这些 identifier。

### Agent / Development Rules

`AGENTS.md` 已按当前 Helper / XPC 架构和产品方向重写。核心规则包括：

- AI Agent 未经用户在当前对话中明确授权，不得 commit、push、force-push、创建 PR 或 deploy。
- 默认开发流程是：本地修改 → build / test → 查看 diff / status → 汇报 → 等待审查。
- 不因为任务完成或测试通过自动修改 Git 或远端状态。

## 当前阶段

**Backend Foundation / Product Exploration**

核心后端链路已经稳定可用，KeyStatsMac 已开始在成熟 upstream 基础上增加自己的数据能力。当前不急于制作新 UI，也不再为了“完善后端”无目的增加字段或抽象层。

后续数据和架构变化应由明确的产品用途驱动：先确认用户将如何理解和使用数据，再决定是否扩展模型。

## 当前数据能力

以下只记录当前源码已经存在的数据能力。

### Global

- Key presses。
- Canonical per-key / shortcut counts。
- Left、right、middle、side-back、side-forward click counts。
- Mouse movement distance。
- Scroll distance。
- Scroll sessions。
- KPS / CPS 与每日峰值。
- Daily stats、history 和 all-time aggregation。

### Per-App

- App identity（bundle ID / display name）。
- Total key presses。
- Canonical per-key counts。
- Left、right、side-back、side-forward click counts。
- Scroll distance。
- Scroll sessions。

## 当前暂缓

以下方向当前不做或暂缓；“暂缓”不代表永远放弃：

- 完整 Trackpad Gesture 统计。
- 私有 Multitouch API 或 IOHID hack。
- 多设备 Sync 协议和产品能力扩展。
- Middle Click 记录链路优化。
- 一次性 SwiftUI 全量迁移。
- 大规模重构 `StatsManager`。
- 为“现代化”重写 Helper、CGEventTap 或 XPC。
- 正式发布签名工作。

## 发布前必须处理

以下事项是正式发布前的检查清单，不是当前开发重点。AI Agent 不应因为看到这些条目就自动实现：

- Developer ID signing。
- 主 App 和 Helper 的 Hardened Runtime 配置。
- notarization / stapling。
- 更严格的 XPC signer validation，例如固定 identifier + Team ID / Developer ID anchor。
- KeyStatsMac 自己的 Sparkle feed 和 signing key。
- Helper 升级后的 TCC / Accessibility 连续性验证。
- Sparkle 原地升级验证。
- macOS 重启或重新登录后的冷启动验证。
- 明确旧 upstream Helper / LaunchAgent 是允许并存还是执行一次性清理。

当前 Xcode Debug 主 App 与 Helper 使用个人 Apple Development 签名；正式 release tooling 仍需要迁移到稳定的 Developer ID 签名并重新验证 vendored Helper、升级和 TCC 连续性。Helper 的签名身份发生实质变化时，仍可能需要一次明确的权限迁移。

## 下一步候选

以下仅为候选探索方向，不自动构成 roadmap，也不代表已经决定优先级。

### Interaction Profile

利用现有 keys、per-key distribution、clicks、mouse movement、scroll distance、scroll sessions 和 per-app data，探索不同 App 的交互模式，例如 keyboard-heavy、scroll-heavy、pointer-heavy。

### Performance Baseline

用 Instruments 建立真实性能基线：

- Idle CPU。
- Memory。
- Wakeups。
- Disk writes。
- Active typing。
- Active scrolling。

性能调整应以实测为依据，不做纯理论重构。

### Data Model Evolution

只有当具体产品功能需要时才继续扩展 `AppStats` / `DailyStats`。不提前创建万能事件模型、原始交互历史或无法证明用途的字段。

### SwiftUI Product UI

未来可逐页重做：

- Keyboard Visualization。
- Stats Popover。
- App Stats。
- Privacy Center。

目前不是优先项，不进行一次性全量迁移，必要的 AppKit shell 可以长期保留。
