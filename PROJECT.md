# KeyStatsMac 项目状态

本文记录当前实现、验收边界与提交范围。开发约束见 [AGENTS.md](AGENTS.md)，技术资料入口见 [docs/README.md](docs/README.md)。历史实验保留，但不能覆盖本节的当前结论。

## 2026-10-26：开发交接快照，菜单视觉未通过

用户已查看当前菜单并明确反馈“看着还是一团糟”，随后要求暂停开发，并授权 commit、push，交由其他 AI 分析。当前菜单是供分析的实现快照，**未通过视觉验收，不是设计定稿或发布版本**。不要以已有测试、构建或历史局部认可替代本次整体视觉结论，也不要自行继续添加候选或修改界面。

本次交接包含正式 App、测试、打包素材和四份主项目文档，共 39 个文件；完整白名单见下文“当前待提交工作区与建议分组”。76 个未跟踪历史原型文件继续保留本地，不提交；本地 `build/` 中的 App、QA 脚本、合成数据预览和日志也不上传。其他 AI 可从本文件、AGENTS 和当前正式源码开始分析，远端不会包含这些本地验收产物。历史段落中的“未提交”描述仅代表当时状态，当前提交及远端状态以 Git 记录为准。

此次授权仅为提交和普通推送当前开发快照，不包含 tag、release、部署或启用自动更新。性能与完整可访问性／发布验收仍未完成。

交接前重新验证：完整 SwiftPM **225 项 XCTest、0 failures**，主 App Debug **BUILD SUCCEEDED**，三语资源／Info.plist lint 与 diff 检查通过。日志保留本地 `build/HandoffCommit/`，这些技术检查不改变菜单视觉未通过的结论。

## 2026-10-26：菜单机械特写与五列数据阵列（视觉未通过，已暂停）

按用户给定的完整规格固定本轮方向：原生 `.popover` 宽 384pt、数据区域左右 18pt，顶部 360×92pt 机械键帽特写入口，随后依次为今日双列数据、常用键、历史趋势、鼠标明细和原有底栏；所有统计默认展示，不增加折叠。今日数值改为 30pt medium 等宽数字，移除主指标图标和 KPS 胶囊背景。常用键最多 15 个，按从左至右、从上至下的 5×3 阵列排列；少量键保留同一格宽，空数据保留一行占位。趋势图为 96pt，移除整块背景，使用细网格和 2.25pt 主线，仅保留末点及 hover 点；范围、指标、折线／柱状和本机／同步语义继续复用现有实现。

顶部只显示正式机械网格的 12 键局部特写，示例 Usage 配色沿用正式 palette，蓝色为主、少量琥珀色；没有读取用户数据或额外聚合历史。浅色、深色分别调整方向光／环境光，透明 PNG 各有 360×92px 的 1x 与 720×184px 的 2x，替换旧薄膜＋机械拼图。离线导出和素材检查程序在本地忽略目录 `build/MenuBarCloseup/QA/`，正式 Popover 只读取编译资源。原生按钮的整块文字／图片区域均可命中，支持鼠标、Space 和 Return；hover 图片上移 2pt、箭头前移 2pt，140ms ease-out，移出和关闭立即恢复，Reduce Motion 只有 CTA 颜色变化。

鼠标明细改为全宽短行：左／中／右、可选侧键、移动／滚动。使用三语完整短标签，完整名称保留 tooltip／辅助功能标签，11pt 数值不自动缩小；侧键无数据时移除整行，高度减少 20pt。保留现有底栏入口、统计查询、Helper、存储、Analytics 和 Keyboard 窗口。

验证：完整 SwiftPM **225 项 XCTest、0 failures**，Debug **BUILD SUCCEEDED**；三语 `.strings` lint 和 `git diff --check` 通过。同源隔离 AppKit 检查使用正式菜单源码、隔离统计与服务替身、编译后的 `Assets.car`，覆盖英文／简体／繁体、深浅色、15 键／2 键／空数据、侧键行、图表切换、原生按钮鼠标跟踪与键盘动作、关闭后的订阅和 KPS timer 清理。完整有侧键示例为 **384×626pt**，无侧键为 **384×606pt**，2 键／空数据为 **384×532pt**，三语鼠标短标签均无截断。透明像素、图片尺寸和深浅色独立渲染检查通过。

补充边界检查：英文百万级点击数、`Scroll 534.5 kPx`、未授权状态的权限按钮均未截断或相互覆盖；权限按钮可见的完整示例为 384×639pt。悬停时关闭 Popover、悬停中收到 Reduce Motion 设置通知，均立即复位并移除位移动画。

日志、逐场景 JSON 与缓存绘制预览位于 `build/MenuBarCloseup/`。预览采用合成统计数据，不代表用户真实数据或正式桌面材质。Hover／Reduce Motion 检查使用隔离分支注入，没有修改系统设置；原生鼠标检查直接投递到按钮跟踪，不能冒充正式桌面的真实鼠标／焦点和 VoiceOver 验收。最终视觉仍交用户确认，本轮不自行增加候选，也未做性能收尾或 commit／push。

最终正式 App 已正常退出旧开发实例后，以 `--debug-gui-acceptance --debug-open-statistics` 启动；`build/MenuBarCloseup/app-runtime.log` 确认菜单 `shown=true`、现有已授权 Helper 连接与监听正常，当前真实数据下面板为 384×604pt。此启动跳过 Helper 安装、LaunchAgent 管理和权限迁移。便捷入口为 `build/MenuBarCloseup/Open Menu.command`；App 为 `build/MechanicalFixedModel/DerivedData/Build/Products/Debug/KeyStats.app`。

## 2026-10-26：旧菜单双图 Growth 入口（已被上述规格替代）

按用户确认的产品定位，菜单仍以数据为主体，在今日按键／点击总量之后加入小面积成长键盘入口。预览素材由现有正式薄膜／机械模型在开发阶段预渲染，包含合成示例 Usage 状态，不读取或冒充用户实时累计数据；生产 Popover 只加载 `GrowthKeyboardPopover` PNG，不创建 SceneKit／Metal，不自动旋转、Replay 或新增常驻渲染。入口文案说明 Mac／机械／回放，点击仍打开现有统一 Keyboard 窗口；hover 仅执行一次轻微浮起和箭头前移，Reduce Motion 下禁用位移。

保留全部信息默认展示和无折叠交互。常用键仍在完整数据下最多显示 15 个，历史范围、四指标和折线／柱状控制不变；左／中／右／侧键与移动／滚动改为紧凑三列数据行，侧键仍只在有数据时显示。成长键盘入口不再占用常用键标题行，键位竖分隔线移除，键帽底色与描边减淡，图表高度由 130 调整为 120 点。底栏、统计查询、持久化、Helper、权限和 Analytics 未改。

新增 `KeyStats/Assets.xcassets/GrowthKeyboardPopover.imageset` 的 1x／2x 静态资源及三语入口文案；实现集中于 `StatsPopoverViewController.swift`。实施阶段按用户要求暂未构建／启动，随后用户明确交由 ChatGPT 编译和测试；本轮结果如下，此前候选的验证不作为本轮证据。

2026-10-26 验证：完整 SwiftPM **225 项 XCTest、0 failures**，Debug **BUILD SUCCEEDED**，三语资源 lint 与 `git diff --check` 通过。独立原生检查复用正式菜单源码及最终 App 的 `Assets.car`，使用隔离统计和服务替身，覆盖英文浅色／中文深色完整数据、繁体空数据、15 键展示、三列明细、图表切换、入口 `performClick` 动作分发，以及关闭后的订阅／timer 清理；全部通过。完整示例尺寸 **380 × 699 点**，空数据示例 **380 × 637 点**。

静态图可从编译后的 bundle 加载；入口对象树没有 SCNView／MTKView，tracking area 重建数量稳定。Hover 位移和 Reduce Motion 分支通过隔离注入检查，没有修改系统设置；不等同于真实鼠标、键盘焦点或 VoiceOver 朗读验收。检查程序最初误将 NSButton view 的 AXUnknown 视为错误，对照标准 NSButton 后确认角色由 cell 提供，已修正测试断言，无需修改产品代码。

记录在本地忽略目录 `build/KimiMenuVerification/`：测试／构建日志、`layout-full.json`、`layout-dark.json`、`layout-empty.json` 和 `preview-*.png`。PNG 为隔离示例数据与原生视图缓存绘制，不代表用户实时统计或正式桌面材质。英文三列明细的距离／侧键长标签会省略，值仍显示并保留完整 tooltip；本轮只记录，不调整设计。检查前后菜单源码与新图片资源哈希一致。

正式 App 已正常退出另一个 Xcode 构建目录里的开发实例后，以 `--debug-gui-acceptance --debug-open-statistics` 打开本次构建。`build/KimiMenuVerification/app-runtime.log` 确认菜单显示成功、已有 Helper 连接与监听正常，实际数据下面板尺寸为 380 × 698 点；未安装 Helper 或执行权限迁移。便捷入口为 `build/KimiMenuVerification/Open Verified Menu.command`。

本轮只更新验证文档，没有修改 Kimi 的产品实现。视觉、真实 hover／焦点和性能验收仍待完成；未 commit／push。

## 2026-10-26：菜单控件减轻，待视觉验收

用户反馈按钮和控件显得突兀。本轮只调整 `StatsPopoverViewController.swift` 的控件样式，保留全部信息默认展示、原有布局、功能和点击次数：成长键盘、底栏图标／文字按钮改用原生 recessed 样式，仅鼠标悬停时显示边框；底栏符号从 16 pt semibold 改为 14 pt regular；成长键盘文字统一为 12 pt regular；三个图表分段选择器统一为原生 texturedRounded 样式。保留键盘焦点、辅助功能标签、tooltips、target/action 和系统高亮行为，不引入自绘控件、常驻动画或新的依赖。

本轮完整 SwiftPM **225 项 XCTest、0 failures**，Debug **BUILD SUCCEEDED**，`git diff --check` 通过。同源隔离原生检查覆盖完整 15 键及侧键数据的英文浅色与简体中文深色，默认信息可见、图表选项往返切换、弹窗显示订阅与关闭清理均通过，两种示例尺寸仍为 **380 × 691 点**。日志及缓存绘制预览在本地忽略目录 `build/MenuBarControls/`。预览使用示例数据，不能替代正式桌面材质、真实悬停／焦点与完整 VoiceOver 朗读验收。

最终正式 App 已正常退出旧进程后以 `--debug-gui-acceptance --debug-open-statistics` 重开；运行日志位于 `build/MenuBarControls/app-runtime.log`，便捷入口为 `build/MenuBarControls/Open Menu.command`。未抓取正式桌面截图，隔离预览不代表真实数据。

这是待用户视觉确认的局部修改，不代表菜单已验收。未修改统计、Helper、权限、更新配置或 3D 模型；未 commit / push。

## 2026-10-26：菜单默认全部展示，待视觉验收

用户否定折叠版：查看详情需要额外点击。当前菜单取消点击明细、常用键和历史趋势的折叠状态及按钮，默认显示今日按键／点击总量、左中右键明细、距离、最多 15 个常用键、完整趋势与控件。侧键继续沿用仅在有数据时显示的规则；少量键位与空数据仍使用原有预览／占位。成长键盘入口移到常用键标题行右侧，减少独立入口行的占用。保留系统 popover 材质、不加回大卡片背景；没有更改统计口径、持久化、3D 或采集链路。

本轮完整 SwiftPM **225 项 XCTest、0 failures**，Debug **BUILD SUCCEEDED**，`git diff --check` 通过。同源隔离原生检查确认各区域默认可见且未超出视图边界、15 键／2 键／空数据、包含中键的总点击量，以及 30 天／点击／柱状切换后恢复；真实 NSPopover 的可见期间订阅和速率 timer、关闭后清理均通过。完整示例（有侧键、15 键）为 **380 × 691 点**，深色中文／少量键和空数据示例为 **380 × 583 点**。证据在本地忽略目录 `build/MenuBarVisible/`，包括 `tests.log`、`app-build.log`、`layout-full.json`、`layout-dark.json`、`layout-empty.json` 与 `visible-*.png`。PNG 使用隔离示例数据和原生视图缓存绘制，不能替代正式数据或桌面系统材质的视觉验收。

最终正式 App 已正常退出旧进程后，用 `--debug-gui-acceptance --debug-open-statistics` 重开；`build/MenuBarVisible/app-runtime.log` 确认面板显示成功，当前真实数据下为 380 × 644 点。便捷入口为 `build/MenuBarVisible/Open Menu.command`。本轮未抓取正式桌面截图。

这是本地待验收候选；此前 359 点的折叠版未通过用户验收，不再作为当前方向。未 commit / push，未修改 Helper、权限或更新配置；未重做性能和完整 VoiceOver 朗读验收。

## 2026-10-25：十秒速览菜单候选

后续状态：用户认为查看详情需要多次点击，未通过验收，已由 2026-10-26 默认全部展示版替代。以下保留该阶段的实现与验证记录。

按用户确认的短时查看场景收紧菜单：今日按键／点击总量、移动／滚动距离默认显示；点击明细、常用键和历史趋势各自按需展开。去掉统计组的大卡片背景，统一左侧对齐；成长键盘改为独立的文字与图标入口。常用键展开复用最多 15 键列表，少于 6 键或空数据复用原有预览／占位；历史仍保留 7/30 天、四种指标与折线／柱状切换，收起时不执行趋势查询。展开状态只保存在 controller 内存中，不增加持久化、统计语义或 Analytics。

本轮完整 SwiftPM **225 项 XCTest、0 failures**，最终 Debug **BUILD SUCCEEDED**。同源隔离原生检查覆盖完整数据、深色简体中文／少量键位、空数据，以及点击／键位／趋势的八种展开组合；默认均为 **380 × 359 点**，折叠后尺寸恢复。真实 NSPopover 显示／关闭检查确认可见期间订阅与速率 timer 存在，关闭后清除。证据在本地忽略目录 `build/MenuBarCompact/`：`tests.log`、`app-build.log`、`layout-full.json`、`layout-dark.json`、`layout-empty.json`。PNG 来自同源隔离原生视图与示例数据，缓存绘制的背景不能替代实际桌面上的系统材质验收。

这是待用户视觉验收的本地候选，不代表已定稿。未改 Helper、权限、更新配置或 3D 模型；未 commit / push。本轮没有重做性能或完整 VoiceOver 朗读验收。最终正式 App 已正常退出旧进程后，用 `--debug-gui-acceptance --debug-open-statistics` 重开；`build/MenuBarCompact/app-runtime.log` 确认显示成功、尺寸 380 × 359 点。便捷入口为 `build/MenuBarCompact/Open Compact Menu.command`；本轮未抓取正式桌面截图，隔离 PNG 不作为正式数据或桌面材质证据。

## 2026-10-25：日常速览候选，视觉待重新讨论

按用户批准的第一个方向，面板现已并列显示今日按键与点击总量，距离放在辅助行；点击明细默认收起，展开后包含左、中、右键及有数据的侧键。总量直接使用现有 `DailyStats.totalClicks`，没有自行改变计数口径。常用键默认横排最多 5 个，展开恢复原有最多 15 个键位列表，复用行视图、字形与数值更新；新增的 tile cache 只保留当前 Top 5。展开状态仅存在 controller 内存中，不新增持久化或 Analytics。趋势图和底栏沿用上一版。

本轮完整 SwiftPM **225 项 XCTest、0 failures**，Debug **BUILD SUCCEEDED**，`git diff --check` 通过。记录在本地忽略目录 `build/MenuBarOverview/`：同源隔离原生检查覆盖 15 / 2 / 0 个键位、中键与侧键计入总量、两个区域展开收起后的尺寸恢复，以及真实 NSPopover 关闭后的订阅与 timer 清理。默认尺寸为 380 × 578 点；原生预览使用测试数据，图片为 `overview-preview.png`、`expanded-preview.png`、`dark-zh-few-preview.png`，检查为 `layout-full.json` / `layout-few.json` / `layout-empty.json`。正式 App 已以 GUI 验收参数重开，日志 `app-runtime.log` 确认面板显示成功、尺寸 380 × 578；图形工具本轮正式窗口读取超时，未将隔离图片宣称为正式数据截图。

用户随后反馈“跟以前还是很像，希望做出差异化”。因此这版仅保留为本地已实现候选，**未通过视觉验收，不作为定稿或发布依据**。已停止对正式 App 的继续微调，下一方向先用对话中的构图草图讨论：键盘模型成为主视觉、减少大卡片、重新分配数字与趋势的空间。该方向尚未集成，需先确认构图；不自动扩展更多实现候选。未 commit / push，未改 Helper、权限、更新配置、统计 schema 或已认可的键盘模型。

后续“键盘主视觉”和“键盘主区＋鼠标辅区＋七日趋势”两张对话草图也未通过。用户认为后者更适合小组件；这仅作为构图参考，不代表已授权开发 Widget。菜单栏下一步建议收窄为紧凑的原生统计面板，先验证默认信息量与展开层级；该建议尚未实现或验收。不要继续集成上述草图，也不要将用户的“看你吧”记为视觉通过。

## 2026-10-25：菜单栏统计面板原生样式

按用户要求参考 Apple HIG 的 [Menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)、[Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers) 和 [Materials](https://developer.apple.com/design/human-interface-guidelines/materials)，整理现有统计面板。保留 `NSStatusItem` / transient `NSPopover` shell、既有显示选项、统计查询、100 ms 菜单栏合并、可见期间订阅与 0.3 s 速率刷新，不引入新版 macOS 专属 API 或新的依赖。

- 使用系统 `.popover` 材质、SF Symbols 和原生按钮/分段控件。顶部明确“今天”，按键总量突出显示；点击和距离统一为两列，侧键仍仅在有数据时出现。
- 保留最多 15 个键位、7/30 天、四个指标与折线/柱状图，将图表控件合并为两排。面板中减淡键位小底色，媒体键使用短符号并保留完整 tooltip / AX 帮助；All-Time 复用的静态字形方法保留原默认样式。
- 统计卡片在目标 view 的 appearance 下解析颜色，避免深色窗口沿用浅色填充。KPS/CPS 徽章成为原生按钮，补齐尺寸、辅助功能名称与当前峰值；图表选择器同步三种语言的辅助功能名称。
- 内容宽 380 点，同源隔离窗口中无侧键为 660 点高、有侧键为 706 点高。Debug 验收模式可加 `--debug-open-statistics` 直接请求显示正式面板；Release 不编译该入口，不写 defaults。
- 正式运行日志暴露既有 `viewDidLayout` 尺寸计算重复调用 `layoutSubtreeIfNeeded` 的警告；该回调现在读取已完成的布局，其他调用仍按需先布局，避免主动重入。

完整 SwiftPM **225 项 XCTest、0 failures**，Debug **BUILD SUCCEEDED**；日志、预览、同源 QA 工具位于本地忽略目录 `build/MenuBarRefresh/`。浅色英文、深色中文、长距离数值、侧键显隐与 30 天/点击/柱状切换已在不连接 Helper 的隔离原生窗口检查，采用 synthetic data，不作为用户统计证据。同一份 controller 的真实 `NSPopover` 打开/关闭检查确认显示时订阅和速率 timer 存在，关闭后均清除，见 `native-lifecycle.json`；同源副本仅替换数据与系统服务边界，UI 来自正式文件。Debug 自动展示入口最初早于状态栏窗口挂载，现用有界 one-shot 延后请求，正式运行日志已确认面板显示成功，最终正式面板截图与 AX 状态分别为 `app-statistics.png` / `app-statistics-ax.txt`；隔离预览继续单独保留。外部点击关闭及不同屏幕边缘的位置仍需用户顺手确认，未重做完整 VoiceOver 朗读或性能验收。

实现集中在 `StatsPopoverViewController.swift`、三种语言资源；`MenuBarController.swift` / `AppDelegate.swift` 仅增加受 Debug + GUI 验收模式双重约束的显示入口和显示状态日志。未更改 Helper、TCC、更新配置或统计 schema，未 commit / push。

最终正式构建已按验收参数重开，日志 `app-runtime-delivery.log` 确认面板显示成功且未见本轮尺寸计算重入警告；已核对真实媒体键符号、30 天 / 点击 / 柱状切换，以及“键盘”按钮打开正式 Keyboard 窗口并关闭面板，见 `app-chart-controls-ax.txt` / `keyboard-navigation-ax.txt`。检查后主 App 留在 Keyboard 窗口，点菜单栏图标可再次显示统计面板；便捷启动器为本地忽略文件 `build/MenuBarRefresh/Open Statistics.command`，运行中再执行不会创建第二份 App。隔离预览 App 已退出。

## 2026-10-25：Keyboard 窗口布局整理

本轮按用户授权调整统一 Keyboard 窗口。顶部集中放 Mac / 机械与“成长统计 / 试打”两个分段选择器；累计总量、截止日期与 Day N 独立成一行；底部将回放、日期导航与时间轴合并为卡片，键位详情与 Usage 图例放在另一张卡片。旧试打复选框已由模式选择器取代，Tab 返回使用模式，Shift-Tab 返回模型选择。英文、简体和繁体文案同步。

仅修改两个 controller 的界面组合与本地化资源，沿用已有场景、相机、配色、按压、正式数据查询与呈现后推进机制。不改变 Helper、权限、更新配置或统计语义，不引入常驻动画。

本轮完整 SwiftPM **225 项 XCTest、0 failures**，Debug **BUILD SUCCEEDED**，日志在 `build/KeyboardWindowRefresh/`。已正常退出旧开发 App，并以 `--debug-gui-acceptance --debug-open-keyboard` 重开最终构建，核对实际数据下 Mac / 机械 Growth、日期导航后的同帧日期与总量，以及试打入口和 Tab 焦点退出；截图为同目录 `mac-growth.png`、`mechanical-growth.png`。另外用不连接 Helper 的隔离原生窗口检查简体中文布局，采用 synthetic data，不作为正式统计证据。未重做完整 Replay、VoiceOver 朗读或性能验收；视觉是否满意仍由用户确认。未 commit / push。

最后一次工具操作曾报告 Mac 锁屏，按用户解锁后的回复继续检查，现已切回机械 Growth / Today，确认截止日期为 2026-10-25、Day 57，时间轴到终点且未播放。最终截图与 AX 状态为 `build/KeyboardWindowRefresh/final-growth.png`、`final-growth-ax.txt`；原有两张 Growth 截图保留。隔离验收 App 已正常退出。本次继续检查未修改代码或重做构建。

## 2026-10-25：用户更新公钥已接入

用户提供了 `SUPublicEDKey`，已校验为 Base64 编码的 32 字节公钥并写入 `KeyStats/Info.plist`。这里只确认格式，不表示已经验证 CI 私钥或发布归档签名；未读取、生成或导出任何私钥。

继续保持 `SUEnableAutomaticChecks = false`，新增显式 `KeyStatsInAppUpdatesEnabled = false`。仅有公钥不能启动 Sparkle：普通模式仍只提供手动 Releases 入口，验收模式仍禁用更新操作。这样不会因准备公钥而触发初始化时的 availability probe。后续启用 App 内更新需另行完成签名发布验收并明确开启开关。

本轮完整 SwiftPM **225 项 XCTest、0 failures**，Debug **BUILD SUCCEEDED**。隔离 bundle 携带与正式构建相同的用户公钥，在普通/验收模式调用真实 UpdateManager 初始化、订阅与探测后，均确认 Sparkle controller 未创建，手动 Releases 路径保留。记录位于 `build/PublicKeySetup/`，不随源码提交；本轮未启动或重启主 App。

## 2026-10-25：辅助功能与自有更新入口

用户要求先检查辅助功能，性能验收留到最终收尾；同时迁移菜单、仓库与更新来源。已确认 origin 为 `Xuan-lprk/KeyStatsMac`；本轮只读查询 GitHub Releases 列表为空，尚无可供验收的发布更新。

- 试打根视图改为有名称、帮助与当前键名的 AX group，不再把 MTKView 暴露为未知类型。Tab / Shift-Tab 分别返回试打开关 / 模型选择；关闭试打时不将焦点留在隐藏画面。两个正式模型的实际焦点退出与方向键精确详情已检查。
- 临时开启真实系统 Reduce Motion，检查 Mac / 机械各 77 键的实际快照没有 Replay 淡化，两套试打曲线使用半行程，均通过；检查后恢复原来的关闭状态。
- VoiceOver 原为关闭，已临时开启，系统 API 确认运行；检查其环境下的 AX 名称、帮助和控件可达性。工具无法可靠捕获语音反馈，VoiceOver 辅助窗口读取也超时，因此不宣称完整朗读验收通过。结束后已恢复关闭，日志记录两项系统设置均恢复原值。
- 设置中的 GitHub、实际 App 的 About 菜单/面板与旧自定义页面均显示自己的项目信息，保留原项目许可与署名。更新地址改为自己仓库的 appcast，移除上游公钥，关闭自动检查。用户明确选择“还没配置签名，先切换链接和地址，暂不启用自动更新”。未配置有效公钥时不创建 Sparkle，普通模式的手动入口为“发布版本”，打开自己的 Releases；验收模式仍禁用更新操作。
- 不改变 Helper、XPC、Bundle ID、签名身份、LaunchAgent 或 TCC；未生成、导出或读取私钥，也未修改 GitHub Secret、发布版本或远端仓库。实际 About 菜单/面板已在最终构建核对，截图为 `build/AccessibilityReview/about.png`。

本轮完整 SwiftPM **225 项 XCTest、0 failures**，Debug **BUILD SUCCEEDED**。公钥格式/模式策略有单测；原生隔离检查覆盖 Tab 焦点和真实 Reduce Motion 分支；真实 UpdateManager 在普通及验收模式下的初始化/订阅/探测均确认未创建 Sparkle controller。本地证据在 `build/AccessibilityReview/`，包括 `focus-check.log`、`reduce-motion.log`、`updater-check.log` 和系统状态恢复日志。Metal 视图验收独立运行，不依赖无 GPU 的 Core XCTest 进程。

## 2026-10-24：键盘进入收尾

用户已认可新机械 77 键造型、相机、无投射阴影与 Usage 配色，授权整理正式 App 的改动。此前收尾保持模型与统计语义，核对接线、生命周期、文档及提交范围；随后用户明确要求补齐机械 Replay，现已复用 Mac 的播放链路。未扩展特效或布局。尚未 commit / push，未删除历史实验。

统一 Keyboard 窗口默认 Mac 3D Growth，可切换机械 3D Growth，共享正式 cumulative/display presentation、日期、Day N、总量与精确键位详情，包含未落盘 Today 和既有 Sync display 语义。旧全局 Heatmap 分页已移除，per-app Heatmap 保留。Editorial 2.5D 实现保留，统一窗口不显示其模式控件。

机械 Growth 高度为 `0.35 + 0.40 × progress` u，复用 `KeyboardUsageProgress` 与 Editorial 浅色→蓝色→琥珀色 palette；改变高度时重连侧壁，保留凹面与收分，未变化的高度复用网格。两种静态场景共用 80 ms 合并与三帧 LRU；日期、次数和详情在新图呈现后共同提交，等待或失焦取消时保留最后完整图。Mac / 机械均支持 Play from Day 1，使用相同的呈现后推进、暂停和生命周期停止逻辑。

“试打”是独立固定高度模式：Mac 视觉高度 0.30u，机械名义高度 10.5 mm，均使用约 72° 正交相机、无投射阴影。Mac 行程约 0.045u、160 ms，机械行程 0.18u、220 ms；连点延续当前位置。字形参考 MacBook 的分类印字规则，保留 77 键 identity，不宣称精确硬件 CAD。窗口 NSResponder 只用物理 keyCode 驱动短暂动画，不读文本、不保存输入顺序、不新增全局监听；虚拟点击不写统计。窗口切换、失焦、隐藏、最小化和关闭会取消调度。

正式源码不依赖 Prototypes，不使用其 plist reader / layer 索引 bridge / OBJ 资产。Helper、XPC、StatsManager 核心、持久化 schema、Sync 协议和 Analytics 数据边界未因这轮视觉功能改变。已有 Debug 验收启动策略是另一项待审查变更，不能漏交或当成数据沙盒。

### 本阶段演进与历史证据

| 阶段 | 已完成事项 | 当时的本地记录 |
| --- | --- | --- |
| 机械正式迁入 | 修正 Copilot 误接旧 Porcelain，改接已认可新网格；77 键射线命中、连点/取消、图像与原验收图一致 | `build/MechanicalIntegration/`，221 项测试、Debug build |
| 统一窗口 | Mac / 机械切换，移除旧 Heatmap 分页，窗口内 keyCode 试打，固定 Aqua 背景 | `build/KeyboardUnified/`，221 项测试、Debug build、基本 GUI |
| 字形与按压 | MacBook 分类印字、F/J 定位、半高方向键；机械行程加强 | `build/KeyboardLegends/`、`build/KeyboardReference/`，221 项测试、Debug build |
| Mac 厚度定稿 | 用户授权直接在 App 内设为 0.30u，不再做四键对照 | `build/MacThickness/`，221 项测试、Debug build |
| 机械 Growth | 正式累计查询、稳定高度与配色、同帧详情、日期及模型切换 | `build/MechanicalGrowth/`，223 项测试、Debug build、离屏与原生窗口检查 |

以上是各阶段历史记录，不等于本轮重跑；本轮结果集中在“测试与当前验证”。此前完整 VoiceOver、Reduce Motion 及能耗尚未验收；最新范围见上方 10 月 25 日记录；旧 Mechanical v3 的否定结论仅指旧造型。

## 新对话接手入口

- 真实 repo：`/Users/quxuan/GitHub/KeyStats/KeyStatsMac`。当前分支 `main`，HEAD 为 `1fbb987dc3f7174700fbd58ac778e73555909a62`（`+Update PROJECT`）。这是交接快照，开始工作时重新核对。
- 旧聊天默认 cwd `/Users/quxuan/Downloads/KeyStats` 不是 Git 仓库。本轮核对另有两个 Copilot 登记 worktree，均未修改；开发与审查以当前真实 repo 为准，不再把 Copilot 的旧 Porcelain 接线当成正确集成。
- 正式 Growth、统一键盘、机械造型/配色、Debug 验收模式和本地 prototype 当前仍未提交。不要清理、覆盖或把它们误认为临时产物；`git diff` 不包含 `??` 文件，需要同时看 status / ls-files。
- 之前因 cwd/可写范围错位，用 `/tmp/*.patch` 中转再批准 CLI 写入真实 repo，导致 Edited Files 难以直接审查。源码实际在真实 repo；临时目录包含补丁、PNG、trace、JSON、日志，不是源码副本。新对话应先使用正确项目目录和访问范围，不继续依赖中转。
- 用户优先级：易读性 → 高级感 → 性能 → 3D 程度。当前统一窗口默认 Mac 3D Growth；机械模型与配色已认可，进入收尾；保留 Editorial 2.5D 实现与共享视觉规则。
- 新目标继续先讨论、批准，再做最小实现并验收；机械 Replay 已获本轮明确授权；不要因收尾自动扩展新布局、材质分支或后台监听。

## 项目定位与边界

> 隐私优先、低功耗的 macOS 物理交互统计与可视化工具。

当前在成熟 upstream 基础上发展分应用展示和长期累计键盘可视化，不重写输入后端。用户可见 UI 可以逐页使用 SwiftUI，AppKit shell 和稳定后端继续保留。

- 这不是 keylogger：不记录实际输入文本、按键顺序、可重建内容的原始输入序列、点击坐标或完整鼠标轨迹。
- 采集和保存的是聚合统计，不通过新功能增加原始输入历史。
- 本地交互统计与产品 Analytics 严格分离；PostHog 不接收键鼠统计、分应用数据或用户 App 列表。
- 准确统计、易读性和低功耗优先；视觉只在用户查看时消耗额外性能。
- History Replay 的目标是回看每日聚合后的累计状态，不是回放原始按键。

## 当前交付状态

### 当前主项目状态摘要

| 范围 | 当前实现 | 验收 / 交付边界 |
| --- | --- | --- |
| 正式 Growth | 默认 Mac 3D，可切换机械 3D；共享 Today / 历史日期、Day N、累计次数、键位选择与时间轴 | 机械造型与配色获用户认可；仍未提交，完整辅助功能及性能验收未完成 |
| 正式 History Replay | Mac / 机械 3D 等当前图像呈现后推进，到 Today 停止；保留 2.5D 实现 | 每日累计快照回放，没有原始输入序列；失焦和切换模型暂停 |
| Debug GUI 验收模式 | 显式参数启用；绕过 Helper 安装、LaunchAgent、旧权限迁移和 Sparkle | 不是只读/离线沙盒，已有 Helper 兼容且获授权时仍会采集；实际启动仍需批准 |
| 共享数据底座 | Cumulative Snapshot、Physical Mapping、KeyboardLayout、Stable Progress；Growth 包含未落盘 Today 和既有 Sync display 语义 | 不新增统计 schema，不复制 prototype 的磁盘数据路径 |
| 试打 | Mac / 机械固定高度，鼠标与窗口内实体键驱动短暂下沉回弹 | 不把虚拟点击写入统计；失焦、隐藏、关闭取消动画 |
| 自有更新入口 | 仓库/菜单/更新地址已迁移，自动检查关闭，用户公钥已接入；显式 App 内更新开关关闭，仅手动查看 Releases | 尚未配置 CI 私钥或发布；签名、公证及 Helper 升级连续性仍需验收 |

### 已提交的基础与产品能力

当前已提交历史止于 `1fbb987`（2026-10-12，`+Update PROJECT`），后续工作区未提交。提交名称不等于实际覆盖范围：

| 提交 | 日期 | 实际内容摘要 |
| --- | --- | --- |
| `1e1ed8c` | 2026-09-01 | 菜单栏 100ms coalescing、测试补强、仓库文档卫生 |
| `f3d20fa` | 2026-09-06 | 真实 StatsManager 的 Environment 注入和隔离测试 |
| `608f425` | 2026-09-06 | 跨日 pending-save 数据保全、历史日期 identity 修复 |
| `9cbc317` | 2026-09-17 | Interaction Profile 纯计算器、System Media Keys、vendored Helper 同步 |
| `4edf43f` | 2026-09-19 | Per-App Key Breakdown、App Detail Dashboard、Profile UI 和日期范围查询接线 |
| `dbee677` | 2026-10-12 | Physical Key Mapping、KeyboardLayout、共享 2D renderer 及测试 |
| `6ead934` | 2026-10-12 | Per-App Keyboard Heatmap |
| `1b5df05` | 2026-10-12 | Cumulative Snapshot、First Tracked Day / Day Index、StatsManager 正式查询 |
| `5b60201` | 2026-10-12 | Stable Keyboard Usage Progress |
| `7ff96d1` | 2026-10-12 | 独立旧 Keyboard Atelier / Porcelain v1/v2 |
| `1fbb987` | 2026-10-12 | 上一版 PROJECT 文档 |

Analytics consent、PID cache 生命周期、per-app key counts、Scroll Session 和 identifier 整理也已存在于提交历史中；不是当前待提交的新功能。

### 已提交的键盘底座

| 能力 | 当前状态 | 边界 |
| --- | --- | --- |
| Per-App Keyboard Heatmap | 已接入 App Detail，和 Key Breakdown 分页切换 | 共享原有 AppKit renderer，不新增采集或 schema |
| Physical Key Mapping | 纯数据层；旧 Heatmap 函数改为薄 adapter | 修复 literal `+` / `Cmd++`，保留 unsupported |
| Keyboard Layout Model | 固定 Mac-style 布局，2D renderer 已读取它 | 6 行、77 个键帽；不支持布局变体 |
| Cumulative Keyboard Snapshot | 纯累计计算和 StatsManager display-history 查询 | 按需派生，不持久化，不自动刷新 |
| First Tracked Day / Day Index | 纯日历日语义及 StatsManager 查询 | 不是 active-day count |
| Stable Count → Progress | 固定 count-only 曲线及测试 | 不替换现有相对 Heatmap normalization |
| 旧 Keyboard Atelier | 独立 prototype，保留 Porcelain v1 / v2 | 不作为当前 Editorial / 3D 的设计基准 |

上述底座已有本地提交，不等于已发布。Editorial 2.5D 的正式页面迁移是后续未提交内容，不能再写成“正式页面尚未实现”。

### 当前待提交工作区与建议分组

交接前的历史基线为 `1fbb987`；此前多轮正式改动均未提交。本次用户已明确授权 commit 和普通 push，下列白名单作为本次完整快照范围，当前提交状态以 Git 记录为准。

第一组是完整可构建的正式 App 改动，共 **35 个文件**。现有 Xcode / Package 注册、菜单静态图片及三语资源跨多个阶段，按完整最终状态一起交接；不要只交 Mechanical 三个文件，遗漏其 Growth 与布局依赖。当前菜单视觉未通过仍保留在快照中，供接手者分析。

```text
KeyStats.xcodeproj/project.pbxproj
KeyStats/Assets.xcassets/GrowthKeyboardPopover.imageset/Contents.json
KeyStats/Assets.xcassets/GrowthKeyboardPopover.imageset/mechanical-closeup-light.png
KeyStats/Assets.xcassets/GrowthKeyboardPopover.imageset/mechanical-closeup-light@2x.png
KeyStats/Assets.xcassets/GrowthKeyboardPopover.imageset/mechanical-closeup-dark.png
KeyStats/Assets.xcassets/GrowthKeyboardPopover.imageset/mechanical-closeup-dark@2x.png
Package.swift
KeyStats/AppLaunchMode.swift
KeyStats/Info.plist
KeyStats/SettingsViewController.swift
KeyStats/MainWindowViewController.swift
KeyStats/AppDelegate.swift
KeyStats/UpdateManager.swift
KeyStats/EditorialKeyboardRenderer.swift
KeyStats/GrowthKeyboardPresentation.swift
KeyStats/GrowthPlaybackState.swift
KeyStats/GrowthKeyboardViewController.swift
KeyStats/GrowthKeyboard3DGeometry.swift
KeyStats/GrowthKeyboard3DScene.swift
KeyStats/GrowthKeyboard3DRenderer.swift
KeyStats/KeyboardVisualizationViewController.swift
KeyStats/KeyboardHeatmapViewController.swift
KeyStats/KeyboardHeatmapWindowController.swift
KeyStats/MechanicalKeyboardGeometry.swift
KeyStats/MechanicalKeyboardScene.swift
KeyStats/MechanicalKeyboardView.swift
KeyStats/MechanicalKeyboardWindowController.swift
KeyStats/MenuBarController.swift
KeyStats/StatsPopoverViewController.swift
KeyStats/en.lproj/Localizable.strings
KeyStats/zh-Hans.lproj/Localizable.strings
KeyStats/zh-Hant.lproj/Localizable.strings
KeyStatsTests/AppLaunchModeTests.swift
KeyStatsTests/GrowthKeyboardTests.swift
KeyStatsTests/GrowthKeyboard3DTests.swift
```

其中 `AppLaunchMode`、`AppDelegate`、`UpdateManager` 与 `AppLaunchModeTests` 必须作为启动策略单独审查：普通模式保持既有 Helper 安装行为；显式 App 内更新开关关闭或公钥无效时不创建 Sparkle，仅可手动打开 Releases。Debug 显式验收参数跳过安装、迁移与 Sparkle，但仍使用正式数据。构建注册同时包含 UI 和验收策略；若要进一步拆成多个提交，需要逐段拆分并重新验证中间状态。

第二组是与当前实现及验收结论一致的 **4 个主项目文档**：`README.md`、`PROJECT.md`、`AGENTS.md`、`docs/README.md`。本次与正式代码一起形成一个开发交接快照。

此前白名单核对覆盖当时的 30 个正式文件与 4 个主项目文档；双图阶段曾为 33 个正式文件，现以 35 个正式文件和 4 份文档为准。此前清单记录为 `build/KeyboardCleanup/commit-scope.json` 和 `build/AccessibilityReview/commit-scope.json`，均不能代替当前范围或视觉验收。

本轮排除 76 个未跟踪实验文件，即整个未跟踪的 `Prototypes/EditorialKeyboard3D/`、`Prototypes/KeyboardAtelierV3/` 与 `Prototypes/README.md`，包括其中未通过的 demo、模型资产和实验脚本，均保留本地。已提交的 `Prototypes/KeyboardAtelier/` 是旧历史，不删除或改写。不要使用 `git add .` / `git add Prototypes`；也不以新增全局 ignore 的方式隐藏这些工作。

`.build`、`build`、DerivedData、trace、QA 预览 PNG、日志与临时补丁不属于提交；上述正式 Asset Catalog 内的四张 PNG 属于 App 资源，包含在快照中。当前主项目文档不依赖上述被排除的本地 README 链接。提交后依然需要独立的发布验收，本次只按明确授权普通 push，不创建 tag、release 或 deploy。

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

## 正式 Growth Keyboard：已接线，仍在工作区

2026-10-19 最初接入 Editorial 2.5D / 3D；2026-10-24 统一窗口改为默认 Mac 3D，并新增机械 3D 与试打切换，2.5D 实现保留。Mac Growth 使用既有 77 键 Geometry v2、相机、光照、Usage palette 和 screen-space 字形。正式 renderer 通过显式只读 scene layout 提供既有比例、路径和字形，不使用 prototype 的 layer 索引 bridge。

3D 的 Today、历史日期、日期步进和时间轴均使用下述同一个正式 presentation → cumulative snapshot → physical mapping → progress 数据链，包含未落盘 Today 和既有 Sync display 语义；没有 prototype plist 读取。支持 hover/点击固定次数、键位选择器和键盘选键。Mac / 机械 3D 均支持 Play from Day 1：每个日历日的累计几何图像就绪后再等 0.35 秒推进，空白日期沿用累计值，到 Today 停止，不循环。日期、总量与键位次数在图像就绪时一起提交；旧图保留到新图就绪，使用 0.12 秒淡化过渡，Reduce Motion 下直接切换。没有新增连续几何插帧、视频导出或全历史预渲染；2.5D 仍沿用 0.15 秒逐日回放。暂停、手动日期/Today/Refresh、切换模式、失焦、隐藏、最小化、关闭均停止回放，恢复焦点不自动继续。

`GrowthKeyboard3DRenderer` 延迟创建 SceneKit，使用三帧 LRU（按物理键 count 与当前 canvas appearance 区分），相同累计值复用图像；新的日期请求合并为可取消 one-shot。窗口隐藏、失焦、最小化、关闭或切回 2.5D 时取消待执行渲染，无 SCNView / Timer / DisplayLink。Mac mesh 保留；机械只在高度变化时重建相应网格，count/hover 只更新文字层。统一窗口当前固定 Aqua 背景。首次冷渲染仍可能有可感知停顿，尚未进行正式窗口性能验收。

最初静态集成阶段的独立 Debug build 与签名验证通过，完整 SwiftPM **217 项 XCTest、0 failures**。当时测试包含实际 Growth controller 的模式/日期切换及禁用 3D Replay；**该禁用状态已被后续 Replay 实现替代**。Geometry v2、缓存上限、取消后的过期工作、同累计值复用和次数详情仍有测试。独立离屏检查用合成累计历史渲染 Day 1 / Mid / Today，77 键投影与未修改 prototype 一致，平均像素通道差异约 `6.5e-7 / 255`，mesh 身份保持；这是历史离屏证据，不是正式 App GUI 或能耗验收。

随后正式 3D Replay 验证：Debug build 成功，完整 **221 项 XCTest、0 failures**；独立真实 SceneKit 检查按合成 8 天累计数据从 Day 1 顺序播至 Today 后停止，复用 77 个 mesh，缓存上限仍为 3。生成的 GIF 是合成 QA 预览，不是正式 App 录像。构建产物路径取决于当次 DerivedData，不能将 `build/GUIAcceptance/.../KeyStats.app` 或任一同名旧产物永久视为最新；以当次 build 日志为准。实际启动前仍须单独批准，并确认 Debug 显式参数 `--debug-gui-acceptance`，不能把参数当成隔离数据沙盒。

入口：菜单栏统计 popover →「键盘」，或菜单栏右键菜单 →「键盘」，均打开统一 Growth 窗口。顶部为 Mac / 机械与“试打”；旧全局 Heatmap 分页移除，per-app Heatmap 不受影响。

| 文件 | 职责 |
| --- | --- |
| `KeyStats/KeyboardHeatmapWindowController.swift` | 沿用的共享窗口 shell，不涉及 Helper 安装 |
| `KeyStats/KeyboardVisualizationViewController.swift` | Mac / 机械模型与试打容器 |
| `KeyStats/GrowthKeyboardViewController.swift` | 日期、Day N、总量、时间轴、回放、键详情和窗口生命周期 |
| `KeyStats/GrowthKeyboardPresentation.swift` | 正式累计数据适配与 session 缓存；缺日期沿用此前累计值 |
| `KeyStats/GrowthPlaybackState.swift` | 有界状态及可取消 one-shot 调度 |
| `KeyStats/EditorialKeyboardRenderer.swift` | 77 键 CALayer 2.5D renderer、动态 count/material、统一 canvas |
| `KeyStats/GrowthKeyboard3DGeometry.swift` | 固定 Geometry v2 高度 / bevel，与统计 progress 分离 |
| `KeyStats/GrowthKeyboard3DScene.swift` | 显式 scene layout → 77 键 SceneKit 实体 → 单次静态图像与投影 rects |
| `KeyStats/GrowthKeyboard3DRenderer.swift` | 80ms 请求合并、懒加载场景、三帧 LRU、overlay / 选择、过期请求取消、呈现回调 |
| `KeyStats/MechanicalKeyboardGeometry.swift` / `MechanicalKeyboardScene.swift` | 已认可的凹面收分网格、固定试打模型与机械 Growth 高度/配色、投影字形 |
| `KeyStats/MechanicalKeyboardView.swift` | 暂停的 MTKView、窗口内 keyCode / 点击按压、有界调度与取消 |
| `KeyStats/MechanicalKeyboardWindowController.swift` | 兼容旧调用，转向统一窗口 |
| `KeyStatsTests/GrowthKeyboardTests.swift` | 正式数据、日期、回放、缓存、背景等测试 |
| `KeyStatsTests/GrowthKeyboard3DTests.swift` | 3D 呈现驱动回放、controller 切换、Geometry v2、LRU、隐藏取消及键位详情 |

正式数据来自 `StatsManager.cumulativeKeyboardTimeline()` / `keyboardTrackingPeriod()`，并用既有 snapshot 查询校验语义；不是 prototype 的 plist reader。包含未落盘 currentStats 和已有 Sync display aggregation。选择日期使用缓存 timeline 的二分查询，不重新读文件或全量历史。

- Date / Day N / cumulative total、previous/next、date picker、timeline、Play/Pause、Today、Refresh 已接入。
- Mac / 机械切换保留日期与所选键，并暂停回放；3D 时间轴在提交选择时请求图像，不逐拖动事件持续渲染。旧历史只有部分键位明细时显示 coverage，缺记录日期沿用之前累计快照并标注，不补造使用量。
- 2.5D Day 1 → Today 每约 150ms 推进一个日历日，3D 在图像就绪后等 350ms 再推进；到 Today 自动停止，不循环，空缺日期不跳过。调度只在可见、key window、App 活跃时存在，失焦/隐藏/最小化/关闭取消，weak self + generation guard 防止过期 callback。
- Today 当前只在打开、重新获得焦点、回到 Today、手动 Refresh 时加载最新累计数据；没有逐事件订阅，不宣称连续 live refresh。
- 数据不变跳过网格更新；机械高度改变时重建对应网格，Mac 保留原几何对象。没有永久 Timer / DisplayLink；试打只在短暂动画期间调度帧。
- count 默认隐藏；hover 精确显示、点击固定，另有原生键位选择器和文字详情。整体 AX description、键盘选键和 Reduce Motion 分支已实现，VoiceOver 完整流程尚未实测验收。
- 保留用户认可的字体、palette、薄侧壁、deck、Depth 与 stable progress；无 Atelier branding、fixture selector、Flat/Neutral 调试开关或直接本地文件读取。
- 同文件 `KeyboardVisualizationCanvasView` 统一窗口和页面背景：浅色 Growth 为 `#F2F2EE`，深色沿用系统色，旧 Heatmap 恢复系统背景；只有最外层能改 window background。renderer 保持透明，并已移除把 AppKit backing layer frame 写成 bounds 的错误。
- 用户已查看并认可当前机械外观和配色；基本窗口/输入检查已做，但不代表完整回放、VoiceOver、Reduce Motion 或能耗均已验收。

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

原 AppKit renderer 从 controller 文件提取到 `KeyboardHeatmapView.swift`；旧全局 controller 和 per-app 共用，SwiftUI 只通过轻量 Representable 嵌入。全局 Heatmap 分页已移除，保留 controller / renderer 源码与 per-app 用途。renderer 负责 frame、颜色、badge、tooltip；相同 per-app snapshot 不重复 apply。

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

## Prototype 地图：与正式 Growth 隔离

| 目录 | 状态 |
| --- | --- |
| `Prototypes/KeyboardAtelier/` | 已提交的旧 Porcelain v1/v2，保留历史对照，不继续以它为设计基准 |
| `Prototypes/KeyboardAtelierV3/` | 未提交的完整 Editorial 2.5D 实验；已认可的视觉来源，其生产部分另迁入 KeyStats |
| `Prototypes/EditorialKeyboard3D/` | 未提交的 77 键 Geometry v2 静态实验，含历史 11 键入口；正式迁移另在 KeyStats 中，不依赖此目录 |

### Mechanical：旧 v3 视觉否定记录

以下记录旧 Mechanical v3 造型被否定时的状态。后续新模型已经另获批准、验收并集成，当前状态见本文开头；不按本节重启已完成流程。

- 已有实现：`MechanicalStudy.swift` / `SpatialRenderer.swift` 的早期加厚挤出方案；`CapDesignGeometry.swift` / `CapDesignRenderer.swift` 的 Cherry-inspired、PBT/ABS 方案；`MechanicalComposition.swift` 的完整布局构图对照；`ImportedCherryModels.swift` / `CherryModelStudy.swift` 的模型导入；`MechanicalV3Geometry.swift` / `MechanicalV3Scene.swift` 的风格化五键方案；`KeyboardStyles77Scene.swift` / `KeyboardStyles77View.swift` / `KeyboardStyles77Study.swift` 的完整 77 键对照。它们均在独立 prototype 中，不是正式 Growth 的模式。
- `MechanicalV3Mesh` 已被 77 键适配层复用；77 键版本与 Mac 共用累计数据、原有字形与 palette。其真实数据对照使用截止 **2026-10-21** 的本机已保存键盘聚合快照，界面显示 `Saved Today`；不等于打开当天的实时 Today，也不包含未落盘输入或远端 Sync display shards。
- 当时用户结论：旧 Mechanical v3 完整 77 键**视觉验收不通过**，与 Mac / Editorial 过于相似。此前五键阶段达到可继续验证的程度，不代表完整键盘视觉获准；构建、拓扑、法线或缓存检查也不能替代视觉验收。
- 当前实验包包含 31 个 Swift 文件、约 4,788 行（含 Package manifest 和独立 Curve Study；不含生成目录与资源）。其中 SwiftPM executable 的 29 个源文件共约 4,498 行；6 个文件分别搭建 SceneKit 场景。该统计只是本轮源码快照，不是长期固定数量。
- Geometry v2、A/B/C 曲线、Press 调度、真实历史适配、旧建模与导入产物均保留本地，不纳入本轮正式提交。
- 当时设定的后续门槛（新模型已按授权完成）：`Plan → Approval → Minimal Prototype → Visual Review → Integration`。明确批准后，第一轮只复用既有 prototype 验证少量真实相邻键帽；未通过视觉，不扩展 77 键、不接正式 App、不开发 Replay / Press 新功能、不做大规模性能优化或新渲染架构。

### 旧 Porcelain v1/v2

位置：`Prototypes/KeyboardAtelier/`。独立构建脚本直接编译共享纯数据文件，不注册到主 Xcode 工程、SwiftPM 或 DMG 流程。当前脚本构建 arm64 macOS 13+，不是 universal 发布产物。

- Porcelain v1 保留 CoreGraphics 表现；v2 使用真实 SceneKit 键帽、底板和脚垫几何。
- 最新 v2 为居中正交相机，无画面内斜转；空格键侧实际抬起约 5°，键帽、刻字随整体倾斜，统一光源。
- 可比较已落盘真实数据、固定低/中/成熟模拟状态，以及灰白几何模式。
- 显示日期、Day N、累计总量、每键次数和 stable progress；支持查看精确 count / 保存图片。
- v2 按数据/灰白状态变化生成静态图并缓存；无 SCNView 持续渲染、Timer 或持续动画。此设计不等于已经完成 Instruments 性能验收。
- 真实数据适配器直接只读本机 preference plist，不启动 StatsManager / Helper，不申请权限，不运行 Analytics 或网络。
- 该磁盘快照不包含未落盘输入或远端 Sync cache；不能冒充正式 display aggregation。正式接入时应使用 StatsManager 的显示查询。
- 解码失败明确显示错误，不静默用模拟数据冒充真实数据。
- 这是旧方向的历史记录，不替换正式 Editorial renderer，也不应被当作新 3D 的默认视觉基准。

### Editorial v3 与新的 3D prototype

v3 的构建、真实已保存数据限制与导出说明见 本地 `Prototypes/KeyboardAtelierV3/README.md`。它保留实验开关和只读本机 plist adapter；正式 Growth 不依赖这个目录，也不沿用它的文件读取逻辑。

3D 详见 本地 `Prototypes/EditorialKeyboard3D/README.md`：

该 README 已更新至 77 键 Geometry v2；以下十一键构建/性能数字是 2026-10-17 的历史记录，不代表当前 77 键或正式 3D Growth 的验收结果。

- A/S/D/F、Shift、Space、Return、四个方向键，共 11 键；未扩 77 键，没有 Growth timeline 或 Replay。
- 本地 SwiftPM dependency / `@testable import KeyStatsCore` 复用共享数据与实际 2.5D renderer。临时 bridge 读取已核对 layer 结构来复用尺寸、top path、attributed legend、palette；不是长期生产 API。
- 三组对照为现有 2.5D 键帽（重新摆到同一观察框）、3D Neutral、3D Usage，不冒充正式页面截图。固定 synthetic aggregate 经 cumulative snapshot / physical mapping / stable progress，不读用户数据、不构造 StatsManager、不启动 Helper、Analytics 或网络。
- SceneKit `SCNRenderer.snapshot` 离屏按需渲染，固定近俯视正交相机约 15°；真实浅挤出 / bevel / deck，一个主光源加环境填充。文字是 projected screen-space 层，不透视变形。
- 启动缓存 Neutral / Usage 图；hover/selected count 不调用 3D。材质更新保留 mesh/node；无 SCNView、Timer、DisplayLink、自动摆动或持续 loop。
- 2026-10-17 build / export / smoke 通过，实际窗口打开，固定 A 显示 6,521、取消恢复隐藏已验证；用户尚未对新 3D 作视觉验收。冷 shader 初始化曾约 0.8s，热更新约 4–8ms，只是 11 键开发测量。
- 同日 M2 / 8GB / macOS 27.0.1 / Debug，exact PID 的 Instruments Activity Monitor 样本约 46.6s：平均 CPU 0.00287%、峰值 0.03215%、footprint 87.52MiB 样本内稳定、compressed 59.39–59.92MiB、idle wakeups 0.322/s、读写增量 0。GPU counter 未取得，不能称 GPU 零工作，也不能推断 77 键或正式 Growth 的能耗。
- 最新临时验收图、trace 与 JSON 在 `/tmp/editorial-3d.dLYYXn/`，可能被系统清理；使用 README 的 export/check 可重新生成，不需要同步临时目录进 repo。

## 标识符、签名与发布边界

identifier 保持冻结：

| 用途 | 值 |
| --- | --- |
| 主 App | `com.xuanlprk.KeyStatsMac` |
| Helper / XPC Mach service / LaunchAgent label | `com.xuanlprk.KeyStatsMac.helper` |

当前 Debug 主 App / Helper 配置使用 Apple Development；Release 配置仍为 ad-hoc，发布脚本和 vendor 签名不能等同于已完成 Developer ID 发布。Helper cdhash 或签名身份变化可能影响 Accessibility 授权，禁止为了整理命名主动变更。

### 普通启动的实际副作用

以下为源码行为，不是对当前已安装系统状态的检查；本轮没有读取或修改系统 Helper / LaunchAgent / TCC。

- `AppDelegate.bootstrapHelperPipeline` 普通模式调用 `HelperSupervisor.ensureInstalled()`。Helper 不存在、任一 cdhash 读取失败、或内嵌/已安装 hash 不同均触发复制；先删除已安装 bundle，再复制内嵌 Helper，复制失败并无自动恢复旧 bundle 的步骤。
- 目标为 `~/Library/Application Support/KeyStatsMac/Helper/KeyStatsHelper.app`；LaunchAgent 为 `~/Library/LaunchAgents/com.xuanlprk.KeyStatsMac.helper.plist`。位置与协议版本由 `KeyStatsHelper/HelperLocations.swift` 定义，当前接口版本为 1。
- 即使 hash 相同，plist 内容不同或服务未加载仍会管理 LaunchAgent；已复制或 plist 改变时可 bootout / bootstrap。因此 hash 一致不是普通启动“无修改”的充分条件。
- 普通模式在安装流程之后调用 `HelperMigrationPresenter`。迁移标记 `KeyStats.HelperMigrationShown` 未置位且此前安装过的用户，可能进入旧 `com.keystats.app` Accessibility reset 与提示；普通 Debug 跳过部分启动权限 alert，不等于跳过迁移。
- Helper listener 同时只接受一个活动 XPC 连接。日常 App 与开发 App 不应同时连接同一服务，第二份连接可能被拒绝；不能通过更改 Bundle ID、Mach service 或签名来临时绕开。

### 自有更新地址与当前状态

`KeyStats/Info.plist` 的 `SUFeedURL` 已为 `https://github.com/Xuan-lprk/KeyStatsMac/releases/latest/download/appcast.xml`，`SUEnableAutomaticChecks = false`，保留 `SUScheduledCheckInterval = 86400`。上游 `SUPublicEDKey` 已替换为用户提供的公钥，`KeyStatsInAppUpdatesEnabled = false`。显式 App 内更新开关关闭或公钥无效时，UpdateManager 的初始化、popover 探测及订阅不创建 Sparkle；普通模式的手动入口只打开自己仓库的 Releases 页面，Debug 验收模式不执行更新操作。

公钥格式检查不等于签名发布验收。自己的公钥、CI 私钥、appcast 与归档签名必须匹配；本轮未生成密钥、未访问 Keychain 项目或 GitHub Secret、未运行发布 workflow。已有 workflow 的 appcast 下载前缀使用当前仓库，但 Homebrew / Scoop 推送目标仍含 upstream 配置，后续首次发布前必须单独审查；本轮不修改或运行这些发布步骤，也不扩展 Windows。

发布前仍需确认 Developer ID、Hardened Runtime、notarization/stapling、XPC signer validation、自有 appcast/归档签名、Helper 升级权限连续性、Sparkle 原地升级、重装及登录冷启动。既有 upstream Helper/LaunchAgent 并存或迁移策略也未作为完整发布流程验收。

### 自有更新签名配置

Sparkle 的 Ed25519 密钥用于验证更新归档，与 Apple 的 Developer ID 代码签名是两件事。官方说明见 [Sparkle documentation](https://sparkle-project.org/documentation/)。当前本地已有官方工具，已只读核对 `--help`：

```bash
./build/GUIAcceptance/SwiftPM/artifacts/sparkle/Sparkle/bin/generate_keys --account KeyStatsMac
```

生成操作需要用户明确授权后才能执行（当前公钥已由用户提供，无需 Agent 再生成）：工具在登录钥匙串保存私钥，并打印可公开的公钥；同一 account 已有密钥时复用，不为每次发布重新生成。公钥用于 `KeyStats/Info.plist` 的 `SUPublicEDKey`，私钥不能写进源码、聊天或构建日志。工具路径属于本地忽略的依赖缓存，其他 checkout 需先构建依赖或使用官方 Sparkle 工具包。

本机发布可让官方 `generate_appcast --account KeyStatsMac` 使用相同 account 的钥匙串密钥；使用现有 GitHub Actions 时，需要用户自行将对应私钥安全配置在仓库 Settings → Secrets and variables → Actions 的 `SPARKLE_PRIVATE_KEY`。当前 workflow 已读取该 Secret 并传给 `generate_appcast --ed-key-file`。仅添加 Secret 不代表已经完成自己的发布渠道；首次启用前还需核对公钥、打包/签名和上述 CI 发布目标。

当前自动更新继续关闭，不因解释配置步骤而生成密钥或发布。恢复 App 内更新（`KeyStatsInAppUpdatesEnabled`）和自动检查应作为后续明确授权的发布配置目标，并验证已发布 appcast 与更新包实际签名，而不是只把开关打开。

## 测试与当前验证

### Debug GUI 验收启动参数

Debug 构建显式传入 `--debug-gui-acceptance` 才启用；Release 忽略该参数，不写入 defaults。验收模式跳过 Helper 安装/替换、LaunchAgent 管理和旧 Accessibility 迁移/reset，且不会初始化 Sparkle updater；popover 的更新探测与手动检查也不启动 updater。

仅尝试连接现有 Mach service。Helper 握手协议版本不匹配时断开，不启动采集；连接失败或权限不足时只报告诊断，GUI 仍可用，不安装修复、不申请权限、不权限轮询或自动重连，也不提示启用登录启动。**协议兼容且已有 Accessibility 授权时仍会请求 startMonitoring**。实际连接兼容性仍需获准启动后验证；不要同时运行两份正式 App。此模式仍使用正式统计、持久化、Analytics consent 和 Sync 行为，退出时仍 stopMonitoring / disconnect 并 flushPendingSave，不是只读数据沙盒或全局离线模式。未传参数的 Debug 仍会执行原安装和更新流程。

| 文件 | 验收策略职责 |
| --- | --- |
| `KeyStats/AppLaunchMode.swift` | Debug 显式参数、Release 忽略、验收模式严格 Helper 版本判断；不写 defaults |
| `KeyStats/AppDelegate.swift` | 跳过安装与迁移、限制连接失败/权限分支、保留正常兼容路径 |
| `KeyStats/UpdateManager.swift` | 初始化、可用性探测、popover 订阅后的探测与手动检查均不创建 Sparkle updater |
| `KeyStatsTests/AppLaunchModeTests.swift` | 参数匹配、编译配置差异与版本允许策略；不模拟系统权限安装 |

2026-10-19 验收模式验证：独立 DerivedData 的 Debug build 成功；完整 Debug SwiftPM 210 项 XCTest、Release 参数策略 4 项均通过。独立检查直接调用真实 UpdateManager 的初始化、popover 订阅、探测及手动检查，确认 Sparkle controller 始终未创建。未启动正式 App，尚未验证实际 XPC 握手和 GUI。

### 当前可核验的验证记录与覆盖范围

2026-10-25 菜单栏、Keyboard 界面、公钥接入和辅助功能验证分别见本文开头，对应日志为 `build/MenuBarRefresh/`、`build/KeyboardWindowRefresh/`、`build/PublicKeySetup/` 与 `build/AccessibilityReview/`；下列 10 月 24 日记录保留为历史证据。

2026-10-24 机械 Replay：用户明确要求补齐后，仅移除 `GrowthKeyboardViewController` 的按钮禁用条件与播放 guard，复用已有 driver、80 ms 合并、三帧 LRU、呈现确认和 350 ms 逐日等待。模型、配色、统计和输入链路保持原样。两模型在新图就绪后推进日期，到 Today 停止；Pause、Today、手动选日期、模型/试打切换、失焦、隐藏及关闭沿用原有取消逻辑。

本轮完整 SwiftPM **224 项 XCTest、0 failures**，主 App Debug **BUILD SUCCEEDED**，记录位于 `build/MechanicalReplay/`。既有 controller 测试改为要求机械 Play 可用（修改前失败）；共享回放测试同时覆盖 Mac 与机械，机械分支核对 77 键高度、正式 palette、逐帧确认、缺记录日期复用和 Today 停止。

隔离原生窗口使用八天合成统计、真实机械网格与独立 UserDefaults，确认两个缺记录日期不跳过、日期/累计详情一致、缓存不超过三帧、Today 后无待渲染工作；Pause、失焦及恢复不自动播放、模型切换和 Today 中断均通过。日志为 `build/MechanicalReplay/native-check.log`，本地程序为 `QA/main.swift`；不是后台采集或能耗基线。

最终正式 App 已按 Debug 验收参数重启，确认机械按钮可用，实际完成 Day 1→Today 的 56 天回放并在终点停止；再次启动后手动 Pause 和 Today 均正常。当前停在机械 Today，截图为 `build/MechanicalReplay/playing.png` / `app-window.png`。构建路径和带参数启动器沿用下文，未执行 commit / push。

以下为此前收尾的验证记录：

2026-10-24 本轮收尾重新运行完整 SwiftPM：**224 项 XCTest、0 failures**；主 `KeyStats` scheme Debug **BUILD SUCCEEDED**。日志为 `build/KeyboardCleanup/tests.log`、`app-build.log`，目录被 Git 忽略，不随提交分发。原有 Helper Copy Bundle Resources 包含 Info.plist 的 warning 仍存在，未借本轮修改构建流程。

本轮复现并修正一项窗口恢复缺陷：`GrowthKeyboard3DRenderer.setActive(false)` 曾丢弃最新快照的呈现回调，恢复后可能图像已更新但日期/详情未提交。现在只取消调度，保留最新确认；隐藏期间不渲染或确认，新请求覆盖旧请求，恢复后只确认最新图像一次。新增回归测试修复前失败、修复后通过；回放仍由 token 与暂停状态阻止自动继续。

隔离原生窗口使用合成计数和独立 UserDefaults，重跑 Today→上一日→Today、精确累计详情、模型切换保留日期、三帧缓存上限；两种试打模型检查按压/复位、短时空闲绘制次数不变、隐藏/失焦/最小化/关闭取消、重开可响应，均通过。记录为 `build/KeyboardCleanup/native-check.log`，验收程序源码在同目录 `QA/main.swift`，只作为本地证据，不加入正式源码。

最终 Debug App 已使用 `--debug-gui-acceptance --debug-open-keyboard` 打开，正式窗口确认机械上一日/Today 的日期、总量与图像共同更新，Mac 回放启动/暂停，以及两种模型的实体 A/S 键映射。当前留在机械 Today 统计视图，截图为 `build/KeyboardCleanup/app-window.png`。这些是基本 GUI 检查，不表示完整长期回放、VoiceOver、系统 Reduce Motion 或 Instruments 能耗已验收。

最新构建位于 `build/MechanicalFixedModel/DerivedData/Build/Products/Debug/KeyStats.app`；验收启动器为 `build/KeyboardUnified/Open Keyboard.command`。路径取决于本地构建目录，不是发布包；直接双击 App 在下次启动时走普通模式，验收继续使用带参数启动器。构建和已授权验收启动不授权 commit、push 或发布。

测试覆盖正式累计数据、模型/日期切换、呈现后推进、过期确认、图像与日期/次数一致、Geometry v2、机械高度与正式配色、网格复用、LRU、隐藏取消及键位详情。源码方法数量不替代执行日志；此前 223 / 221 / 217 等数量仅为历史阶段记录。

根 `Package.swift` 编译正式 Core / Growth / Mechanical 源码和 Helper 的白名单 payload / media-key / button-role 纯逻辑；Analytics 使用 `KeyStatsTestSupport/PostHog` 替身。它不编译 AppDelegate、UpdateManager、HelperSupervisor、XPC 服务或真实 EventTap / TCC 路径，不执行完整 App 启动。正式 Sparkle 接线、签名、Helper 安装、系统权限、真实采集、完整 VoiceOver 和 GPU / 能耗必须单独验收。

以下为 2026-10-17 的历史验证快照；2026-10-18 交接只修改文档：

- 完整 SwiftPM：**206 个 XCTest，0 failures**。正式迁移从 186 增至 202，后两轮背景各补 2 个至 206；3D smoke 是独立检查，不计入 XCTest 数。
- KeyStats scheme Debug：**BUILD SUCCEEDED**，包括最终背景代码。原有 Info.plist / Copy Bundle Resources 等 warning 未顺手修改。
- 新 3D 独立 build / export / smoke 通过；源代码在独立目录，主工程不引用 prototype。
- Growth tests 覆盖真实 StatsManager 未保存 Today、display/Sync 去重、历史与 DST/空白日期、回放边界/取消/过期 callback、actual renderer 路径复用、physical counts → stable progress、旧历史 partial details、窗口背景和 appearance 语义。
- build 和对象单测不证明 GUI/VoiceOver/Reduce Motion、正式 77 键 replay 能耗、Helper/TCC 升级连续性。新 3D 仅有上述 scoped idle，不是正式四场景 baseline。
- 2026-10-15 尝试正式 GUI 验收时内嵌/已安装 Helper cdhash 不同，按用户“hash 一致才启动”条件停止。之后用户手动打开过正式页；不能据此假定今后的 Helper 更新自动保留权限。每次启动前按需重新核对实际 hash，不沿用旧数值。
- 2026-10-12 曾验证 vendored Helper 与记录一致；本交接只核对记录文件 `vendor/KeyStatsHelper.cdhash.txt`，没有重建或安装 vendor。

默认 xcode-select 曾指向 CommandLineTools；当前完整 Xcode 可用路径为 `/Applications/Xcode-beta.app/Contents/Developer`，运行命令时可设置 `DEVELOPER_DIR`，不要全局切换工具链：

```bash
cd /Users/quxuan/GitHub/KeyStats/KeyStatsMac
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project KeyStats.xcodeproj -scheme KeyStats -configuration Debug \
  -destination 'platform=macOS' build
```

构建主 scheme 可能重新生成不同 cdhash 的 Helper；不要为了 UI 验收自动启动并触发安装、替换、签名或 TCC 操作。单独启动 3D prototype 不需要 Helper。

## 尚未实现 / 暂缓

- 完整 VoiceOver 朗读反馈验收；Reduce Motion 实际分支已检查。正式 77 键 Instruments 性能验收按用户要求留到最终收尾。
- Today 自动低频 live refresh；当前主动刷新语义应保留，不能为了实时感恢复逐键重绘。
- 正式 77 键 3D 静态/Replay 的 GUI、Reduce Motion、可访问性和性能验收；有界逐日回放已实现，连续几何插帧和播放速度选择尚未实现。
- Keyboard Interaction Signature：仅调查过 aggregate per-key 分类；未实现 classifier，不把 printable key 命名为 Text Entry。
- 完整后台 pinch/rotate/系统 Space swipe/pressure：独立公开 API 调研后未接入；不使用私有 Multitouch/IOHID hack。
- Privacy Center 与 Analytics Settings 开关。
- per-app mouseDistance、per-app middle click、固定布局外键帽/布局变体。
- Sync 扩展、同步 secret Keychain 迁移和发布基础设施：不得因本文列出就自动实施。
- Windows 扩展、全量 SwiftUI rewrite、无实测依据的大规模性能重构。

正式代码与 prototype 均保留在真实 repo，现有工作区仍未提交。当前模型进入收尾；下一步先审查上述正式文件白名单，再由用户明确授权提交。实验、发布和后续产品功能不随收尾自动扩展。
