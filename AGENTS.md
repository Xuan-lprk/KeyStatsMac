# KeyStats AI Agent 开发指南

本文档是面向 Codex/AI Agent 的项目操作手册。所有判断以当前源码为准；如果本文档与实现不一致，先核对代码，再以最小范围修正文档或实现。仓库内更深层目录若存在自己的 `AGENTS.md`，该目录下的工作同时受更具体规则约束。

## 默认沟通格式

开始处理任务时，先用 5 行以内告诉用户：

1. 发现了什么；
2. 要不要做；
3. 风险大不大；
4. 会改哪些东西；
5. 下一步是什么。

然后再给技术细节。

## 项目定位

KeyStats 是 macOS 13+ 原生菜单栏应用，主工程使用 Swift 5、AppKit，并在部分界面嵌入 SwiftUI。产品正在从键鼠计数器逐步发展为：

> 隐私优先、低功耗的 macOS 物理交互统计与可视化工具。

长期产品方向包括：

- 键盘、鼠标，以及未来可能加入的 Trackpad 交互统计。
- 长期累计数据的高质量可视化。
- Keyboard Visualization / Growth Keyboard。
- History Replay。
- Interaction Profile。
- 主要供用户自己查看的分应用交互统计。
- Privacy Center。
- 逐步将用户可见页面迁移到 SwiftUI。
- 后台采集保持极低 CPU、内存、wakeups 和磁盘写入。
- 漂亮视觉只在用户正在查看时消耗额外性能。

当前近期重点是 macOS 产品本身。`KeyStats.Windows/` 和多设备同步已经存在，但除非用户明确指定，不要主动扩展 Windows、同步协议或 Worker 基础设施。

## 最高优先级：Git 与远端安全

未经用户在当前对话中明确要求，禁止执行：

- `git commit`
- `git push`
- `git push --force` 或任何形式的 force-push
- 创建或合并 PR
- 创建 tag
- 创建 release
- deploy，包括 staging 和 production
- 任何会修改远端仓库、远端分支或外部部署状态的操作

任务完成后的默认流程是：

1. 修改本地文件。
2. build，并运行相关测试。
3. 查看 `git diff` 和 `git status`。
4. 汇报修改文件、验证结果、重要 diff 与未验证部分。
5. 停止并等待用户审查。

不要因为功能完成、测试通过或改动具备原子性而自动 commit。只有用户明确说出“commit”“push”“deploy”等指令时，才执行对应操作；授权不自动扩展到其他 Git 或远端动作。

## 隐私边界

KeyStats 不是 keylogger。

永远不要记录、持久化、导出或上传：

- 用户实际输入文本。
- 按键顺序，或任何可以重建文本的原始输入序列。
- 鼠标点击的具体坐标。
- 完整鼠标轨迹。
- 用户内容、窗口内容或剪贴板内容。

允许保存的是聚合统计，例如：

- 按键总次数。
- 每个键或组合键名称的累计次数。
- 鼠标各类点击次数。
- 鼠标移动距离和滚动距离。
- KPS / CPS 与峰值。
- 分应用聚合数据。

当前鼠标移动坐标会在内存中以采样后的事件经过 XPC，用于计算相邻点距离；它们不得被日志化、持久化、上传或改造成轨迹历史。按键事件中的 key code 只应用于生成聚合键名和计数，不得形成可回放的原始按键序列。

分应用统计由 `AppActivityTracker` 根据事件来源 PID 解析 bundle ID 和显示名，再由 `StatsManager` 聚合。此数据主要供用户本地查看，不得自动用于产品 Analytics。

## 当前后端架构

正式输入链路是：

```text
macOS input events
→ KeyStatsHelper
→ EventTapController / listen-only CGEventTap
→ PayloadBuilder
→ HelperXPCListener
→ XPC
→ HelperXPCClient
→ RemoteEventProcessor
→ StatsManager
→ UI / UserDefaults persistence
```

不存在由主 App 中 `InputMonitor` 负责全局监听的正式架构。不要按照旧实现或旧文档寻找、恢复或新建 `InputMonitor`。

关键职责如下：

- `KeyStats/AppDelegate.swift`
  - 启动菜单栏 UI、更新与同步协调器。
  - 安装并连接 Helper，设置 XPC event sink。
  - 协调辅助功能权限提示、授权轮询与 Helper 启动。
  - 通过 `AnalyticsManager` 发出既有产品事件。
- `KeyStatsHelper/main.swift`
  - 启动 `HelperXPCListener` 并保持 Helper run loop。
- `KeyStatsHelper/EventTapController.swift`
  - Helper 内唯一正式 `CGEventTap` 所有者。
  - 使用 `.listenOnly` 的 `.cgSessionEventTap` 监听键盘、点击、滚轮和移动事件。
  - 当前对鼠标移动/拖动进行约 30 Hz 采样，并处理 event tap 被禁用后的恢复。
- `KeyStatsHelper/PayloadBuilder.swift`
  - 将 `CGEvent` 转成受限的 XPC 字典字段。
  - 不传输用户文本；移动坐标只用于主 App 计算聚合距离。
- `KeyStatsHelper/HelperXPCListener.swift`
  - 提供 XPC 服务、校验主 App 的签名标识和当前用户 UID。
  - 管理单个活动连接、权限握手、tap 生命周期和事件转发。
- `KeyStats/HelperSupervisor.swift`
  - 从 App bundle 安装 Helper 到 Application Support。
  - 以 cdhash 判断是否需要替换，维护 LaunchAgent；这与 TCC 授权稳定性直接相关。
- `KeyStats/HelperXPCClient.swift`
  - 管理主 App 到 Helper 的连接、握手、状态、重连和权限请求。
  - 使用现有 `NSLock` 与 one-shot completion 保护并发状态。
- `KeyStats/RemoteEventProcessor.swift`
  - 解码 Helper payload，过滤 auto-repeat，处理修饰键状态和键名映射。
  - 将键盘、点击、滚动、移动距离和可选的 App identity 写入 `StatsManager`。
- `KeyStats/AppActivityTracker.swift`
  - 缓存前台 App 与 PID 对应的 bundle ID/显示名，仅为分应用聚合提供 identity。
- `KeyStats/StatsModels.swift`、`KeyStats/AppStats.swift`
  - 定义 `DailyStats`、`AllTimeStats`、`AppStats` 与键位规范化/聚合逻辑。
  - Codable 解码包含历史字段兼容，例如 legacy `otherClicks` 和旧 peak 数值格式。
- `KeyStats/StatsManager.swift`
  - 聚合当前日、历史、每键、每 App、距离、KPS/CPS 和通知数据。
  - 通过 `UserDefaults` 保存 JSON 编码的当前数据与历史。
  - 使用锁、snapshot、延迟保存、UI 更新合并和午夜切日逻辑。
  - 通过 `Environment` 注入存储、时间、日历、日期 key formatter、自动调度和正式运行时副作用，使真实实现可以被 SwiftPM 确定性测试。
  - 区分本机可写历史与包含远端 shard 的显示快照。
- `KeyStats/StatsManagerLiveEnvironment.swift`
  - 为正式 App 提供 `StatsManager.shared`，并连接通知、Sync 展示和真实运行时依赖。
  - SwiftPM 测试不编译该文件，而是通过 `StatsManager.Environment` 创建隔离实例。
- `KeyStats/MenuBarController.swift`
  - 管理 `NSStatusItem`、`NSPopover`、右键菜单和菜单栏更新。
  - 当前菜单栏视图已经使用 `NSHostingView` 嵌入 SwiftUI，但 shell 仍为 AppKit。
- `KeyStats/StatsPopoverViewController.swift`
  - AppKit 统计 popover，部分数值/KPS 视图嵌入 SwiftUI。
  - 只在显示期间订阅统计更新并运行 KPS 刷新 timer。
- `KeyStats/KeyboardHeatmapViewController.swift`
  - AppKit 键盘热力图与日期切换；窗口可见时订阅统计更新。
- `KeyStats/AnalyticsManager.swift`
  - 唯一允许直接接触 PostHog SDK 的产品分析入口。
- `Package.swift`、`KeyStatsTests/`
  - SwiftPM 选择可独立测试的 Core 源文件，并用 XCTest 覆盖模型、兼容解码、热力图聚合、同步核心和更新检查协调逻辑。

## 成熟后端的处理原则

以下模块已形成相互依赖的稳定链路，不要仅以“现代化”“代码较老”或“准备迁移 SwiftUI”为理由重写：

- `KeyStatsHelper`
- `CGEventTap`
- XPC 协议与连接
- `HelperSupervisor`
- `HelperXPCClient`
- `RemoteEventProcessor`
- `StatsManager` 核心统计逻辑
- 现有持久化兼容逻辑
- 权限与 TCC 处理

只有具体功能或已确认缺陷确实要求时，才在这些模块做最小修改。不要为了 SwiftUI 迁移而改写后端、事件链路或存储模型。

涉及 Helper、Bundle ID、Mach service、签名、cdhash、LaunchAgent、entitlements、TCC 或 Accessibility 的改动一律视为高风险。修改前必须完整追踪安装、签名、权限和 XPC 两端的影响。

## UI 技术方向

当前 UI 以 AppKit 为主，并已有少量 SwiftUI 嵌入。未来可逐页迁移用户可见页面，例如：

- Keyboard Visualization
- Stats Popover
- All-Time Stats
- App Stats
- Settings
- Privacy Center

迁移规则：

- 不进行一次性全量 SwiftUI rewrite。
- 每次只迁移边界清晰、可独立验证的页面或组件。
- 可以长期保留 `NSStatusItem`、`NSPopover`、`NSWindow`、`NSWindowController` 等 AppKit shell。
- 不为了“纯 SwiftUI”牺牲菜单栏、窗口焦点、popover、快捷键、权限提示或现有行为。
- 动画和高频刷新只应在相关窗口可见时运行，消失或关闭时必须停止订阅和 timer。

## Analytics 规则

当前 Analytics consent 后端由 `AnalyticsManager` 管理：

- consent key 是 `analytics.optIn.v1`。
- key 不存在时视为关闭，默认不启用 Analytics。
- 关闭时不得初始化 PostHog，也不得发送事件。
- 所有 `trackEvent`、`trackClick`、`trackPageView` 必须经过 `AnalyticsManager`。
- 禁止在其他文件直接调用 `PostHogSDK` 或另建绕过 consent 的分析通道。

PostHog 只用于了解用户如何使用 KeyStats 产品本身，例如 App 版本、macOS 版本、页面打开、功能操作和设置状态。不得把下列内容放入 Analytics event 或 properties：

- 按键次数、键位或组合键统计。
- 鼠标点击、移动或滚动统计。
- KPS / CPS。
- 分应用统计、App 列表或用户使用了哪些 App。
- 历史交互数据或任何可关联的原始输入事件。

新增 Analytics 事件前先检查 properties 的隐私边界；不要因为本地已有某项统计，就默认它可以上传。

## 持久化与兼容性

- 不要随意改名或删除已有 `UserDefaults` key、Codable 字段、导入导出字段或同步 schema。
- 修改 `DailyStats`、`AppStats`、`StatsManager` 时，必须考虑旧版本历史数据的解码和迁移。
- 新字段应有安全默认值；需要改变旧字段语义时，先设计明确迁移方案并添加兼容测试。
- `dailyStatsHistory` 中每个 `DailyStats` 是某一天的完整累计 snapshot，不是可以任意相加的数据片段；日期 collision 不得默认 merge。
- 合法的 `yyyy-MM-dd` history key 是用户记录产生时的本地日期身份。`normalizedHistory` 必须保留合法 key，并把内部 `DailyStats.date` 对齐到该 key；只有非法 key 才回退到内部日期。fallback collision 必须使用确定性规则，当前规则为合法 key 优先、多个非法 key 按原 key 字典序选择第一个。
- 跨日 rollover 在替换 `currentStats` 前，必须把上一日的最新完整 snapshot 写入对应历史，不能依赖 delayed-save 已经执行；同日手动 reset 不应因此被归档。
- 不要把完整长期历史在每个输入事件上重新序列化；沿用当前延迟保存与 snapshot 模式，除非 Instruments 数据证明需要调整。
- 不要混淆本机可写历史、远端缓存和用于 UI 的聚合显示快照。

## 线程与性能原则

后台统计的准确性和低功耗优先于实时视觉刷新。

- 键盘和点击计数可以逐事件精确更新；UI 不需要逐事件重绘。
- 能 debounce、coalesce 或批量处理的 UI 更新与落盘应合并。
- 鼠标移动等高频事件必须保留合理 sampling，不要把所有 movement event 直接送入重型逻辑。
- 不要在窗口不可见时运行视觉动画、`TimelineView`、`CVDisplayLink`、高频 `Timer` 或持续刷新。
- 避免无意义的长期 global event monitor；已有 monitor 也必须有明确用途和清理路径。
- 避免在输入热路径执行网络请求、磁盘 I/O、完整历史聚合或昂贵 App 查询。
- 性能调整优先依据 Instruments 的 CPU、Allocations、Energy Log、wakeups 和文件写入实测，不做纯理论的大重构。

并发修改时优先沿用当前经过验证的 `NSLock`、串行队列和 snapshot 模式。不要未经验证就把 Helper、XPC 或 `StatsManager` 整体改成 Actor。所有 AppKit/SwiftUI 状态更新必须回到主线程；闭包和 observer 按现有模式使用 `[weak self]`，并在生命周期结束时清理。

## 代码修改规则

1. 修改前阅读调用链两端和相关测试，不依据文件名猜实现。
2. 优先最小修改，不做“顺便重构”。
3. 不为了统一代码风格而重写成熟模块。
4. 用户要求具体功能时，不自动扩展成架构重写、数据迁移或额外产品功能。
5. 不修改无关文件；工作区已有改动默认属于用户，必须保留。
6. 新增用户可见文本时使用 `NSLocalizedString`，并同步检查 `en`、`zh-Hans`、`zh-Hant` 资源。
7. 新增文件时确认它同时进入正确的 Xcode target；若是 App-only 文件，也要检查 `Package.swift` 是否需要排除。
8. 涉及数据、权限、Helper 或同步时，先写清兼容和失败路径，再实现。

## 深色/浅色模式

- `CALayer.backgroundColor`、`borderColor` 等 `CGColor` 是静态快照，不会自动随 appearance 更新。
- 动态 `NSColor` 转 `CGColor` 时，在目标 view 的当前 `effectiveAppearance` 下解析。
- appearance 变化后重新赋值 layer colors，不依赖旧 `CGColor` 自动变化。
- 沿用已有 `AppearanceTrackingView`、`NSApp.effectiveAppearance` observation 和 `resolvedCGColor` / `resolvedColor` 模式。
- 排查主题问题时先确认 app、window、view 的 appearance 及最终解析颜色。

## 构建与测试

常用命令：

```bash
swift test

xcodebuild \
  -project KeyStats.xcodeproj \
  -scheme KeyStats \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

当前自动测试事实：

- `Package.swift` 定义 `KeyStatsCore` 和 `KeyStatsCoreTests`。
- `KeyStatsTests/` 当前覆盖模型、App attribution、Analytics consent、`StatsManager` 的本地持久化/导入/合并/历史、同步核心和更新检查协调逻辑。
- 本次文档更新时共发现 114 个 XCTest；这是当前快照，不是永久数量保证。
- SwiftPM 会编译真实 `StatsManager.swift`，测试通过独立 `UserDefaults`、固定时间和关闭自动调度的 environment 创建隔离实例。
- `StatsManagerTests` 当前直接覆盖持久化、import/merge、跨日 rollover、历史日期 identity 和异常 history key 的确定性 normalization。
- SwiftPM 不编译 App-only 的 `StatsManagerLiveEnvironment.swift`，也不覆盖 AppDelegate、Helper、XPC、TCC/权限或实际 UI 行为。

每次实现完成后至少：

1. 运行相关 XCTest；适合时运行完整 `swift test`。
2. 构建 `KeyStats` scheme。
3. 查看 `git diff --check`、`git diff` 和 `git status`。
4. 确认没有无关文件变化。

`BUILD SUCCEEDED` 只证明编译和链接成功。涉及 Helper、权限、TCC、XPC、输入采集、窗口生命周期或能耗时，还需要对应的真机手动验证或 Instruments 数据；不能仅凭 build 成功宣称功能已完全验证。

## 部署与同步边界

- staging 和 production 都禁止自动部署。
- 修改 `services/sync-worker/**`、`contracts/sync/v1/**`、迁移或 workflow 也不能触发自动部署。
- 不自动应用 D1 migration，不自动发布 DMG、release 或 Scoop 包。
- 多设备同步不是近期开发重点；除非用户明确要求，不主动修改同步协议、Crypto、远端缓存、Worker 或部署配置。
- 如果任务确实涉及同步，优先保持现有 E2EE、schema、设备绑定和历史兼容行为，并运行对应 Core/Worker 测试。
