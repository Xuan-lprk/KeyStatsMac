# 菜单 UI 风格交接

设置 → 菜单栏 → 菜单 UI 风格，提供「Input Pulse（原版）」和「极客风（独立副本）」。选择写入 `menuUIStyle.v1`，下次打开菜单生效，未知值回退原版。范围仅为菜单统计面板，不切换 Settings 或独立 Keyboard 窗口。

最初复制时两套外观一致；极客风现已修改为独立视觉候选，原版保留。极客隔离预览曾在启动时因外观回调递归加载 view 而栈溢出，已加初始化检查并通过中英文隔离预览复测；这不代表正式运行和视觉验收完成，详见 PROJECT 最新记录。

| 范围 | 原版（保留） | 极客风（修改这里） |
| --- | --- | --- |
| 面板布局、控件、图表、底栏 | `KeyStats/StatsPopoverViewController.swift` | `KeyStats/GeekStatsPopoverViewController.swift` |
| Input Pulse 波形及光点 | `KeyStats/TypingPulseView.swift` | `KeyStats/GeekTypingPulseView.swift` |

极客风副本的顶层辅助类型已加 `Geek` 前缀，与原版隔离。此次按用户明确要求复制，不做共享组件重构。修改第二套时保留原版文件；新增文案用 `geek.*` key 并同步三语，避免改动共享字符串影响原版。

切换接线在 `MenuUIStyle.swift`、`MenuBarController.swift`，设置入口在 `SettingsViewController.swift`。控制器按风格懒创建且每套最多一个；原版默认选择，无额外统计 schema、采集或 Analytics 改动。两套各自保留原有显示订阅、关闭清理和速率 timer 生命周期。

Kimi 可以调整极客风的 UI、布局、颜色和局部有界动画；继续遵守 AGENTS 的隐私、可见期间运行及 Reduce Motion 规则，不重写 Helper、StatsManager 或持久化。当前复制并不代表任何新视觉方案已获验收。
