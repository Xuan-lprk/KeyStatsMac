# KeyStats AI Agent 开发指南

本文档是面向 Codex/AI Agent 的项目操作手册。所有判断以当前源码为准；如果本文档与实现不一致，先核对代码，再以最小范围修正文档或实现。仓库内更深层目录若存在自己的 `AGENTS.md`，该目录下的工作同时受更具体规则约束。

## 工作区与交接

- 当前真实仓库是 `/Users/quxuan/GitHub/KeyStats/KeyStatsMac`。新对话先核对 `pwd`、`git rev-parse --show-toplevel`、`git status --short`，再读本文和 `PROJECT.md`。
- 旧聊天默认 cwd `/Users/quxuan/Downloads/KeyStats` 不是 Git 仓库。不要在那个目录另建副本，也不要把 `/tmp` 当成项目工作区。
- 工作目录或可写范围不匹配时，先说明并解决访问问题；不要长期依赖 `/tmp/*.patch` 中转源码修改，导致 Edited Files 只显示临时补丁而难以审查真实 diff。
- `/tmp` 可以存放 build、PNG、trace、QA JSON 和日志，它们不是真实源码，也不是待同步 worktree。真实源码变更必须能在真实 repo 中核对。
- 新增未跟踪文件不会出现在普通 `git diff` 中；同时检查 `git ls-files --modified --others --exclude-standard`，不能据此误报文件丢失。
- 当前未提交代码和实验目录必须保留；提交/验收状态及建议分组见 `PROJECT.md`。整理交接不等于获得 commit、push 或历史重写授权。

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

- `KeyStats/AppLaunchMode.swift`
  - 进程级启动策略；仅 Debug 显式参数 `--debug-gui-acceptance` 启用验收模式，Release 忽略，不持久化参数。
  - 验收模式拒绝不匹配的 Helper 协议版本；普通模式保留既有兼容行为。
- `KeyStats/AppDelegate.swift`
  - 启动菜单栏 UI、更新与同步协调器。
  - 安装并连接 Helper，设置 XPC event sink。
  - 协调辅助功能权限提示、授权轮询与 Helper 启动。
  - 通过 `AnalyticsManager` 发出既有产品事件。
- `KeyStatsHelper/main.swift`
  - 启动 `HelperXPCListener` 并保持 Helper run loop。
- `KeyStatsHelper/Package.swift`、`KeyStatsHelper/README.md`、`KeyStatsHelper/Tests/`
  - 独立、无第三方依赖的原生 Helper SwiftPM 构建／测试入口，直接复用正式十份 Swift 源码。SwiftPM 裸可执行文件不替代签名 `.app` 或既有安装流程，不以 `swift run` 启动已安装的服务。
  - 新包清单、README 和具体测试文件通过主工程 helper 同步目录例外排除；新增测试必须同步排除其路径，避免 XCTest 进入生产。根 SwiftPM 的 `KeyStatsEventCore` 继续直接编译原有四份事件源码。
  - c3502 的本地源码评估见 Helper README：当前远程通知／请求与 WebSocket 传输未完成，只能作为未来聚合快照插件的候选。不得把原始按键／移动 payload 接入 c3502，不放宽现有 XPC 鉴权。
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
  - 当前实验菜单保留 384pt 宽、系统 `.popover` 材质、今日双列总量、5×3 常用键阵列、96pt 趋势图、全宽鼠标短行及原有底栏；顶部旧 3D 特写与资源已移除，Growth 改为常用键标题行的轻量文字入口。此前整体视觉未通过，新 Input Pulse 候选不代表这些问题已解决。
  - 只在显示期间订阅统计更新并运行 KPS 刷新 timer。
- `KeyStats/TypingPulseView.swift`
  - 顶部 132pt Input Pulse：复用可见期间现有 0.3s KPS timer 读取 `currentRatesSnapshot()`，以双层 CAShapeLayer 波形显示 KPS／CPS；约 12 秒、40 个聚合速率样本只存内存，不接收键名、原始时间戳或输入顺序。
  - 聚合统计更新可触发有节流、最多 10 个的一次性键帽光点；无新 Timer／DisplayLink／全局监听，空闲零样本不持续更新波形。关闭时停止采样、清空样本并移除光点及动画；Reduce Motion 禁用路径过渡和光点。2026-10-29 已将波形改为直接生成 CGMutablePath，修正 macOS 13 兼容性，Debug 构建与 225 项核心测试通过（核心测试不覆盖该 App-only 视图）；视觉、真实输入和能耗未验收。
- `KeyStats/KeyboardHeatmapViewController.swift`
  - AppKit 键盘热力图与日期切换；窗口可见时订阅统计更新。
- `KeyStats/KeyboardVisualizationViewController.swift`、`GrowthKeyboardViewController.swift`
  - 统一 Keyboard 窗口的 Mac / 机械模型与试打切换；Growth 使用正式累计显示查询、日期选择和有界回放，旧全局 Heatmap 分页已移除。
- `KeyStats/GrowthKeyboardPresentation.swift`、`GrowthPlaybackState.swift`
  - 缓存 display-aggregated timeline、日历日选择，以及可取消的 one-shot 回放；不读取历史文件或新增持久化。
- `KeyStats/EditorialKeyboardRenderer.swift`
  - 正式 77 键 Editorial 2.5D renderer；静态路径/layer 缓存，动态 count/material 更新。
  - 同文件的 `KeyboardVisualizationCanvasView` 统一窗口/页面背景；只有最外层 canvas 可修改 window background。AppKit backing layer frame 由 AppKit 管理，不得在 layout 中设置为局部 bounds。
- `KeyStats/GrowthKeyboard3DGeometry.swift`
  - 正式 Geometry v2 的固定 progress → height / bevel 映射；与统计 progress 分离，不按当天最高值或日期归一化。
- `KeyStats/GrowthKeyboard3DScene.swift`
  - 消费 Editorial 的显式只读 scene layout，保留 77 键几何对象，执行一次静态 SceneKit snapshot；无 prototype 文件依赖或持续渲染回调。
- `KeyStats/GrowthKeyboard3DRenderer.swift`
  - 管理懒加载场景、80ms one-shot 合并、按 counts / canvas 区分的三帧 LRU、字形与次数 overlay、键位选择及取消 token。
  - 3D 回放在图像、次数就绪后通知 controller 提交日期，再由 playback driver 等待并推进。
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

### 构建、普通启动与 GUI 验收模式

- build-only 不等于启动授权。普通 Debug 仍执行 `HelperSupervisor.ensureInstalled()`、LaunchAgent 管理、旧权限迁移；Sparkle 还需有效公钥与显式 App 内更新开关均就绪才启动；Debug 跳过部分权限提示不表示这些副作用关闭。
- `--debug-gui-acceptance` 仅在 Debug 生效，跳过上述安装/迁移与 Sparkle 初始化。`UpdateManager` 的初始化、popover 探测、手动更新入口均有策略 guard，不能只在 AppDelegate 中跳过单例就宣称 updater 不会创建。
- 在上述验收模式内可加 `--debug-open-keyboard` 或 `--debug-open-statistics` 请求显示相应界面；这些便捷入口仅 Debug 编译，不写 defaults，也不改变验收模式的其他数据与 Helper 边界。
- 验收模式仍连接现有 Helper。协议版本必须等于 `KeyStatsHelper/HelperLocations.swift` 的 `interfaceVersion`；兼容且已有授权时仍会 `startMonitoring`，没有授权或连接失败时仅报告，不安装修复、不权限轮询或自动重连。
- 此模式不是只读数据沙盒或全局离线模式；正式 StatsManager 持久化、Analytics consent、Sync 启动及退出时 flush 仍存在。Helper 只接受一个活动连接，不同时运行两份主 App。
- 普通安装路径在 Helper 缺失、任一 cdhash 读取失败或 hash 不同时复制；即使 hash 相同，LaunchAgent plist 不同或服务未加载仍可能写配置/注册服务。hash 一致不能单独证明普通启动无系统改动。
- 2026-10-25 用户授权更新来源迁移：`KeyStats/Info.plist` 已指向 `Xuan-lprk/KeyStatsMac` 的 appcast，`SUEnableAutomaticChecks = false`，上游公钥已替换为用户提供的公钥。`KeyStatsInAppUpdatesEnabled = false`，仅配置公钥不启用更新；未明确开启 App 内更新或公钥无效时，`UpdateManager` 初始化、探测和订阅不创建 Sparkle；普通模式的手动入口仅打开自己的 Releases 页面。不得自行生成/导出私钥、启用自动更新或发布；Keychain、CI Secret、签名和首发验收仍需相应授权。

## UI 技术方向

- 极客主题已从初始副本演进为单独候选，代码保留，视觉及完整正式运行未验收。2026-10-29 隔离启动崩溃已定位为 loadView 设置 appearance 时同步回调递归访问 view；GeekStatsPopoverViewController.updateAppearance 必须在 isViewLoaded 且控件已创建后执行。中英文隔离预览复测、Debug 构建及 225 项核心测试通过，不能替代正式风格切换和真实输入验收。

- 菜单两套风格在 Settings 的「菜单 UI 风格」选择，`menuUIStyle.v1` 默认 standard、另一项 geek，下次打开菜单生效。保留 `StatsPopoverViewController`／`TypingPulseView` 原版；用户明确要求的独立副本为 `GeekStatsPopoverViewController`／`GeekTypingPulseView`，供 Kimi 改第二套，当前两套外观相同。修改边界见 `docs/menu-ui-styles.md`；不把副本存在视为新设计已通过。MenuBarController 每套最多缓存一个控制器，隐藏期间按原生命周期停止更新。

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

## 键盘视觉与 prototype 边界

- 当前正式入口为统一 Keyboard 窗口：默认 Mac 3D Growth，可切换机械 3D Growth；两者共用日期、累计数据和键位详情。顶部通过“成长统计 / 试打”分段选择器切换，试打进入固定高度模型，鼠标或窗口内实体按键触发短暂下沉回弹。累计总量与截止日期位于键盘上方，回放/时间轴和键位详情集中在底部卡片。旧全局 Heatmap 分页已移除，per-app Heatmap 保留；Editorial 2.5D 实现仍保留，但统一窗口不显示其切换控件。
- 2026-10-24 用户已认可新机械 77 键、相机、无投射阴影、字形及 Growth 配色，当前进入收尾。旧 Mechanical v3 因与 Mac 太相似被否定，属于历史实验，不能再据此禁止当前已获授权的新模型集成。完整 VoiceOver / Reduce Motion / 能耗和发布验收仍单独记录。
- Mechanical 使用 `MechanicalKeyboardGeometry` / `MechanicalKeyboardScene` / `MechanicalKeyboardView`；布局复用 Editorial 的显式只读 `sceneLayout`。机械 Growth 高度为 `0.35 + 0.40 × progress` u，颜色复用 Editorial Usage palette；高度变化重连侧壁，不拉伸顶面。Mac / 机械共用 Play from Day 1，复用同一 playback driver 与呈现确认，不另建机械播放调度。
- 试打只通过窗口 NSResponder 的 `keyDown` / `flagsChanged` 接收物理 keyCode，不读取文本、不保存顺序、不新增全局监听；虚拟点击不写入统计。Mac 固定视觉高度 0.30u；Mac / 机械均有有界按压，切换、失焦、隐藏、最小化和关闭时取消。试打根视图提供 AX group、帮助与当前键名；Tab / Shift-Tab 分别返回使用模式 / 模型选择，退出试打不将焦点留在隐藏画面。
- 正式 Growth 的数据只能来自 StatsManager 的 cumulative/display 查询，包含未落盘 currentStats 和既有 Sync display 语义；不得复制 prototype 的磁盘读取路径。Today 在打开/获得焦点、回到 Today、手动刷新时更新，不逐事件重绘。
- 静态 3D 复用 `GrowthKeyboard3DRenderer` 的 80ms one-shot 合并、三帧 LRU、键位选择和取消 token。新帧呈现后再共同提交日期、次数和详情；等待或失焦取消时保留最后完整帧及最新呈现确认，恢复后确认最新图像，不在隐藏期间确认或自动继续播放。两种模型的 Replay 均等当前图像呈现后推进，到 Today 停止；没有永久 Timer / DisplayLink。
- `KeyboardLayout` 提供共享 identity/结构；保留已认可的 Editorial 比例、Usage palette 和 stable progress。优先级为易读性、高级感、性能、3D 程度；不因收尾重设计模型、布局、配色或统计语义。
- 正式源码与 Xcode target 不依赖 `Prototypes/`。实验的 `@testable` / layer-introspection bridge、plist reader、OBJ 资产不属于生产 API；历史实验保留本地，未通过的 demo 不加入本轮提交。已提交的旧 Porcelain 也不为此改写历史。
- 后续新造型或交互目标继续遵循 `Plan → Approval → Minimal Prototype → Visual Review → Integration`，每次只做一个经过验收的小目标。当前模型已完成相应授权，不重复要求从四键开始；新需求不能借收尾自动扩展。
- 原型性能不等于正式 Growth 性能，11 键数据不能代表正式 77 键。构建、拓扑或单测通过不能代替视觉、GUI 和能耗验收。

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

- `Package.swift` 定义 `KeyStatsCore`、`KeyStatsEventCore`、本地 PostHog 测试替身和 `KeyStatsCoreTests`；SwiftPM 不使用正式 PostHog SDK 发送数据。
- `KeyStatsTests/` 当前覆盖模型、App attribution、Analytics consent、`StatsManager` 的本地持久化/导入/合并/历史、同步核心和更新检查协调逻辑。
- 2026-10-28 原生 Helper 分离检查在 `build/HelperSeparation/`：独立包 8 项 XCTest、根工程 225 项 XCTest 和正式 Debug 构建通过。Helper 十份运行源码与主 App 安装／权限链未改，重建前后 Helper cdhash 与两个 Mach-O 的被签名内容相同，Debug 签名区字节有差异；本机开发证书的 strict 校验在前后均报 `CSSMERR_TP_NOT_TRUSTED`。vendor helper 校验通过且未更新；没有启动、安装、重新授权或进行 c3502 端到端测试，不能据此宣称 TCC 或发布签名验收通过。
- 最新菜单特写与阵列布局检查在 `build/MenuBarCloseup/`：225 项 XCTest、Debug 构建、三语资源 lint 通过；同源隔离原生检查覆盖三语、深浅色、15／2／空键位及侧键行，完整有侧键为 384×626pt、无侧键为 384×606pt、2 键／空数据为 384×532pt，鼠标短标签无截断。静态图透明通道、1x／2x 尺寸与独立深浅色渲染检查通过；原生按钮鼠标跟踪、键盘动作、图表切换和关闭清理通过。Hover／Reduce Motion 使用隔离分支注入，不能替代正式桌面的真实悬停、完整 VoiceOver 和能耗验收；用户已否定整体视觉，当前仅保留分析快照。
- 旧双图入口验证在 `build/KimiMenuVerification/`：225 项 XCTest、Debug 构建、资源 lint、三语同源隔离原生检查通过。该阶段英文紧凑长标签省略已由当前短行布局替代，旧记录不代表当前界面。
- 菜单控件减轻检查在 `build/MenuBarControls/`：225 项 XCTest、Debug 构建、英文浅色与中文深色的同源隔离原生检查通过，完整示例尺寸仍为 380 × 691 点；真实悬停／焦点及用户视觉验收未完成。
- 默认全部展示菜单记录在 `build/MenuBarVisible/`：225 项 XCTest、Debug 构建及完整／深色中文／空数据的同源隔离原生检查通过。完整示例 380 × 691 点，少量键／空数据示例 380 × 583 点，默认可见与图表切换、弹窗关闭清理通过；用户视觉验收仍待确认。
- 历史折叠菜单候选记录在 `build/MenuBarCompact/`：225 项 XCTest、Debug 构建及完整／深色中文／空数据的同源隔离原生检查通过，默认 380 × 359 点，八种展开组合可恢复；正式 App 验收参数启动日志确认显示成功。该折叠布局已被用户否定，见 `PROJECT.md` 最新记录。
- 最近一轮界面验证见 `PROJECT.md` 开头；2026-10-25 `build/MenuBarOverview/` 为 **225 个 XCTest、0 failures** 与 Debug `BUILD SUCCEEDED`，同源隔离检查覆盖 Top 5、展开收起、中键总量和空数据；用户视觉验收未通过，正式窗口读取限制单独记录。此前 MenuBarRefresh / KeyboardWindowRefresh / AccessibilityReview / PublicKeySetup 为 225 项，MechanicalReplay / KeyboardCleanup 为 224 项，MechanicalGrowth 为 223 项。日志位于本地忽略目录，旧数量仅作为对应阶段历史保留，不能当作新一轮执行结果。
- SwiftPM 会编译真实 `StatsManager.swift`，测试通过独立 `UserDefaults`、固定时间和关闭自动调度的 environment 创建隔离实例。
- `StatsManagerTests` 当前直接覆盖持久化、import/merge、跨日 rollover、历史日期 identity 和异常 history key 的确定性 normalization。
- 当前还覆盖 Physical Mapping、KeyboardLayout、Cumulative Snapshot、Day Index、Stable Progress，以及 Growth 的正式数据适配、回放取消、实际 renderer 路径缓存、窗口背景语义。AppKit 对象单测不等于完整 GUI / VoiceOver / 能耗验收。
- `GrowthKeyboard3DTests.swift` 覆盖逐帧呈现后推进、过期确认、日期/次数与图像一致、正式 controller 的模式与日期、三帧 LRU、隐藏取消、键位详情和 Geometry v2；`AppLaunchModeTests.swift` 覆盖参数的 Debug / Release 条件与 Helper 版本策略。启动策略单测不等于真实 XPC / TCC 或 Sparkle 安装更新的验收。
- SwiftPM 不编译 App-only 的 `StatsManagerLiveEnvironment.swift`，也不覆盖 AppDelegate、Helper、XPC、TCC/权限或实际 UI 行为。

每次实现完成后至少：

1. 运行相关 XCTest；适合时运行完整 `swift test`。
2. 构建 `KeyStats` scheme。
3. 查看 `git diff --check`、`git diff` 和 `git status`。
4. 确认没有无关文件变化。

纯文档任务按用户范围只做源码对照、链接、diff 和文件变更检查；用户禁止构建/测试/GUI 时不执行它们，也不把旧日志写成新测试结果。

`BUILD SUCCEEDED` 只证明编译和链接成功。涉及 Helper、权限、TCC、XPC、输入采集、窗口生命周期或能耗时，还需要对应的真机手动验证或 Instruments 数据；不能仅凭 build 成功宣称功能已完全验证。

## 部署与同步边界

- staging 和 production 都禁止自动部署。
- 修改 `services/sync-worker/**`、`contracts/sync/v1/**`、迁移或 workflow 也不能触发自动部署。
- 不自动应用 D1 migration，不自动发布 DMG、release 或 Scoop 包。
- 多设备同步不是近期开发重点；除非用户明确要求，不主动修改同步协议、Crypto、远端缓存、Worker 或部署配置。
- 如果任务确实涉及同步，优先保持现有 E2EE、schema、设备绑定和历史兼容行为，并运行对应 Core/Worker 测试。
