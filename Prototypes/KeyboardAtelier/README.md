# Keyboard Atelier — 隔离的 2.5D 视觉实验

独立 AppKit 视觉实验。Porcelain v1 保留 CoreGraphics 方案，
v2 使用 SceneKit 真三维几何按需生成静态图；不是正式页面，也不是实时键盘测试器。

## 打开

在项目根目录运行：zsh Prototypes/KeyboardAtelier/run.sh

或直接打开构建后的 .build/KeyboardAtelier.app。

左侧只比较 Porcelain v1 / v2；右侧沿用真实累计 / 初始 / 成长 / 成熟。
“灰白几何对照”仅关闭使用配色，次数、progress 和相机不变，两版都能使用。
悬停键帽查看精确累计次数与 stable progress，点击固定；Esc / Cmd+Q 退出。
“保存图片”只在你选定路径后输出当前窗口的静态 PNG。

## 数据与边界

- 直接编译共享的 KeyboardLayout、PhysicalKeyMapping、CumulativeKeyboardSnapshot、
  KeyboardTrackingPeriod、KeyboardUsageProgress；不复制它们的计算实现。
- 真实模式只读 com.xuanlprk.KeyStatsMac.plist 已落盘的 dailyStats / dailyStatsHistory。
  保留合法日期 key，非法 key 才 fallback；当前日替换同日历史 snapshot，不重复相加。
- 这是隔离实验的磁盘读适配器，不是正式 StatsManager 查询接线。
  尚未保存的输入与远端 Sync cache 不在此快照中；正式接入时应改用
  StatsManager 的 display-aggregated cumulative / tracking-period 查询。
- 总按键数采用 snapshot 的权威总量；物理键参与次数来自 PhysicalKeyMapping。
  通用修饰键保留旧 Heatmap 的 direct-then-generic fallback，不推断左右。
- 模拟模式是固定虚构分布，仅比较材质成长，不是对用户未来数据的预测。
- 不连接 Helper，不申请权限，不读输入，不运行 Analytics / 网络 / 持久化。
- 无 Timer、DisplayLink、事件全局监听或持续动画。只有窗口曝光、resize、
  控件变化、hover 换键触发绘制。
- v2 的键帽是带收窄侧壁、肩部倒角、顶面和底面的封闭三维 mesh；
  底板与脚垫也是真实几何。所有键、刻字及底板共用居中正交相机，
  取消画面内转角；键盘整体以远端脚垫为支点，让空格键侧实际抬起 5°。
  行线保持水平、各位置键帽不因透视改变大小；刻字随键帽一起倾斜。
- 单一方向光生成实体的受光和投影，环境填充不创建第二套方向阴影。
  无 glow、bloom、噪声动画或绘制出来的“假侧壁”。
- 不使用 SCNView 持续渲染。SCNRenderer 仅在物理次数或灰白状态变化时
  生成静态图片；hover、曝光、缩放使用缓存，命中检测沿用场景相机。
- 没有修改正式 Xcode 工程、Package.swift、Heatmap 或发布流程。
  新文件只属于这个独立 prototype；构建产物在已忽略的 .build/ 中。

## 开发验证

- 只编译：zsh Prototypes/KeyboardAtelier/run.sh --build-only
- 几何 smoke：zsh Prototypes/KeyboardAtelier/run.sh --geometry-check
- 原生静态渲染：zsh Prototypes/KeyboardAtelier/run.sh --render-dir /tmp/keyboard-atelier-previews

输出两版 × 四种数据状态 + 两张灰白对照，共 10 张 PNG。
几何 smoke 检查 77 个键帽变换后的投影中心命中、底板角点完整入画、
近端高于远端、后脚接地与缓存复用，
不模拟用户真实输入。真实模式图片包含本地聚合统计，请勿自动上传。
