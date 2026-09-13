# 浅色主题全仓审计 · 2026-09-12

本报告按 TASK.md §1 的方案执行。阶段一完成令牌层和会话列表；阶段二完成 P0 聊天与 P1 外壳/导航，P2+ 页面保持只读。视觉取舍由 Leader 验收。

## 范围与复验方法

- 扫描 `lib/` 全部 **234** 个 Dart 文件，记录 **1775** 个颜色引用/常量/别名透明度使用点。按实际目录补入下载、诊断和内置服务，不沿用旧目录快照假定覆盖。
- 语义色取自 Flutter **3.47.0** / Dart **3.13.0** 的 `packages/flutter/lib/src/cupertino/colors.dart` 普通浅色分支；增强对比度和暗色保留分支另标豁免。
- WCAG：sRGB 通道 `c<=0.04045 ? c/12.92 : ((c+0.055)/1.055)^2.4`；相对亮度 `0.2126R+0.7152G+0.0722B`；比值 `(L高+0.05)/(L低+0.05)`。先按实际 alpha 在 sRGB 合成，再线性化；中间值不取整，表格保留六位小数。
- 正文 AA 门槛 4.5:1，功能图标/数据图形按 3:1；纯装饰面、边框、投影不套正文 AA。低对比度卡片面仍可存在视觉分层问题，不能用“装饰豁免”宣称已经分层充分。
- 逐文件表三向列为：该色合成到**页面底 P**、**白卡 C**、**黑色 label L** 后各自的对比度。会话列表、聊天及侧栏工具条 P 用新 page，空态详情 P 用白面，其余文件 P 用现行全局分组背景。它们是明确的承载面参考值；反色内容和已知彩色组合另列附录，不能拿白字对白卡的参考值误判反色 tooltip。
- 静态审计列出所有可解析颜色及来源、透明度和组件默认色。运行时透明度/任意图片内容不能由单个基色证明 AA，表中明确保留限制；本轮没有逐页启动所有状态，也不声称全仓视觉验收通过。
- `python tools/light_theme_contrast.py` 输出本报告全文；`--tokens` 复算令牌注释；`--write-report` 生成文件；`--check-report` 校验报告与当前源码/SDK 完全一致。无第三方 Python 依赖。没有 `.dart_tool/package_config.json` 时可传 `--flutter-sdk <SDK根目录>`。

## 阶段一结果及保留项

- page/card 的对比度由 1.115871 变为 1.115871；cardBorder 对白卡为 1.543866，对新页面为 1.383553。描边取 #CCD0DA、0.5–1 逻辑像素（v2：主人实机反馈灰底过深后，page 退回 #F2F2F7 并以加深描边承担分层），视觉差由 before/after 供 Leader 判断。
- 原候选 #6E6E73 对新页面仅 4.544721；保持 R=G、B=R+5，#6A6A6F 为最浅整字节达标值；再浅一档 #6B6B70 为 4.749720。
- 新 page 仅用于会话列表和其侧栏复用区，局部导航背景同步；全局 buildCupertinoTheme 未改。白卡、搜索框、次级文案/菜单图标、过滤 Sheet、批量栏、弃用 disclosure 计数、FAB 工作区浮层接入。选中和按下反馈只在浅色分支启用。
- 源码未渲染时间戳文字（时间只参与分组排序），没有为满足任务描述而新增时间戳或改业务数据流。三点菜单/副标题/置顶图标使用新次级色。
- #EEFFFFFF 与 #B3FFFFFF 的普通浮层面归 card；#1F000000 作为普通浮层边框的调用归 cardBorder，作为投影的调用保留。#F0000000 是反色 tooltip，白字组合见附录，保留其语义。
- 深色 helper 使用原语义色并显式 resolve；历史未 resolve 的灰图标和选中蓝图标保留原实际绘制 ARGB，避免顺手改变深色增强对比度像素。暗色路径无新增按下/选中填色。
- README 截图工装原样调用，通过外部 comparator 重定向到 `C:/tmp/light-theme-shots/before/` 与 `after/`；没有写入 `docs/screenshots/`。该工装的 CupertinoApp 未接 buildCupertinoTheme，改造前页面使用其默认背景；全局主题数值以源码和正式金照为准。

## 阶段二 P0 结果及保留项

- 聊天页局部 page/bar 接 LightSurfaces.page（现 #F2F2F7）；动作色 #005FB8，不改全局主题。次级文字、占位符、功能灰图标按各自承载面接令牌。
- 审批/澄清/错误/绿色提示面固定为不透明 tint，输入框、工具卡、选中上下文、注入卡和媒体占位接白面/描边；模型/工作区/推理选择保留勾选并增加选中、按下面。
- 用户主气泡 #007AFF + 白字按 Leader 决定保留（实算 4.016976:1，未达正文 AA）。白字降透明度或加字重不能达到 4.5:1；代码/链接/附件/引用的局部底 #005FB8 与白字为 6.308159:1。主气泡后续可选 #006FE8（白字 4.730779:1），待 Leader 裁决，未实施。
- assistant Markdown 新样式由聊天调用点 useLightSurfaces 显式启用；记忆页和文件预览的共享默认保持不变。普通用户消息仍为原纯文本渲染，未改动 Markdown 触发条件。
- 暗色语义色保留原 resolve；历史未解析图标保留原实际 ARGB。固定黑底媒体、Mermaid 深底配置、重复文字语义的状态圆点及装饰轨线保留且显式标注用途。
- 本阶段截图目录 `C:/tmp/light-theme-shots-p2/before/`、`after/`；P0 单区留证另存 `after-p0/`。P0 验收：analyze 零告警，test 2710 passed / 8 skipped；13 张既有暗色金照、7 张 README 暗色截图和 24 张暗色状态图共 44/44 SHA256 一致。证据在 `after-p0-verification.json`，docs/screenshots 的 7 张原图未写入。
- README 演示数据固定在 2026-09-12，原工装的分组时钟却读取系统日期；跨午夜后出现今天/昨天漂移。临时工装仅补 sessionListNowProvider 固定为演示日期，重录后与原始改码前暗色 PNG 字节一致；生产代码和原工装均未修改。

## 阶段二 P1 结果及保留项

- 侧栏工具条固定 page、inactive 图标接 textSecondary（对 page 4.820554:1），激活图标用 statusBlueText 配 selection。空态详情保持白面，副标题/图标接 textSecondary，新建按钮仅浅色改用可读深蓝底。分栏手柄复用 divider，命中区、拖拽和导航回调不变。
- 通用 popover/dropdown 面接 card、1px cardBorder；菜单标题和普通/强调/危险文字分开校验。桌面菜单按下用 pressed；原生 ActionSheet 保留 SDK 面和遮罩，动作文字用 menuAction #004A94（既有状态调色板增强蓝），其半透明按下面另算，不只拿白卡证明 AA。
- AdaptiveMenuItem 没有禁用项 API，未新增业务状态；现有空内容消息菜单的禁用文字在实际白卡/原生操作表普通面核验。AppBackButton 和快捷导航入口只有图标，继承主色对本区页面面色达图标 3:1，源码和路由保持不变。
- 原生按钮的短暂透明反馈、遮罩与装饰阴影保留；不把任意图片作为背景或动画过渡每一帧宣称为已审计。固定反色退出 toast 的白字组合已达标，未改码；分隔线/投影明确按装饰层级处理。
- 双主题菜单按下/禁用态与普通/增强对比度、base/elevated 外壳截图另存 before/shell、after/shell；P1 改码前先拍补充基线。最终共 43 张暗态截图和 13 张既有暗色金照，56/56 SHA256 一致；证据为 `C:/tmp/light-theme-shots-p2/after-verification.json`。12 张范围外浅色金照、7 张 docs 截图及 185 个范围外 lib 文件均与任务前散列相同。
- P1 本地验收：analyze 零告警，test 2726 passed / 8 skipped，金照单独复跑 26 passed；fake gateway 15 项检查全部 PASS。浅色筛选重录曾产生范围外引导页金照差异，完整测试捕获图与原基线 SHA256 完全一致，因此恢复原基线并全量复验；引导页代码未改。

## 阶段二优先级

| 顺序 | 改法建议 | 预估影响面 |
|---|---|---|
| P0 聊天 | 蓝气泡白字/代码、可读次级文字、提示卡与工具卡轮廓 | chat_page + chat/widgets，历史/流式/输入/审批/媒体 |
| P1 外壳/导航 | 工具条、空态提示、菜单文字与浮层面分开迁移 | app/shell + app/widgets，所有宽屏及弹层入口 |
| P2 看板/用量 | 白卡轮廓、状态文字/轴标签、保留图形触摸态 | Kanban 主/详情/创建，Insights 总览/图表 |
| P3 设置 | 次级说明、地址、placeholder，子区逐一接入 | settings 全部子页/表单及 sidecar 设置 |
| P4 引导 | 表单/步骤/日志优先，hero 装饰独立评估 | onboarding 宽/窄屏、连接及安装向导 |
| 后续配套 | 按共用令牌修元数据与表单，预览反色 UI 单独验收 | 工作区、Git、技能、记忆、任务、下载、诊断、通知、项目、提示词库 |

## 硬编码定位与代码可判定的发现

- `lib/features/chat/chat_page.dart:1496,1628,1729`：绿色提示卡已接 tintGreen + cardBorder；正文、状态图标和关闭图标的实际组合见附录 P0。暗色 #2C2C2E 及原描边、投影保留。
- `lib/features/onboarding/widgets/onboarding_hero_motion.dart:277`：品牌图标承载面；halo 的透明渐变、轨道线在同文件 _HaloPainter 中，属无交互装饰，按设计保留/后续整体评估。
- `lib/features/chat/widgets/mermaid_block.dart:58,63,68`：`core.Color` 是 Mermaid 深色 theme 的 primaryText/text/title 配置，不是浅色 Flutter 卡片面，归配置豁免。
- 旧 secondaryText/secondaryLabel 实际浅色是 #3C3C43/153，不符合旧注释所述正文 AA；参见附录的逐背景实算。tertiaryLabel/placeholderText 更浅；输入占位属于可读信息，不能因为名字含 tertiary 就豁免。
- 主色 #007AFF 的小字号白字/蓝字也不自动满足正文 AA。阶段一保持品牌/全局按钮语义；会话搜索命中改用 statusBlueText，批量栏危险文字使用 statusRedText 的浅色分支。其他品牌动作/禁用态列入后续，不宣称会话页所有文字已全域达标。

## 框架默认面和文字（逐文件的“默认控件”引用此表）

| 控件/默认路径 | 来源及浅色语义 | 验证要点 |
|---|---|---|
| CupertinoPageScaffold / NavigationBar / SliverNavigationBar | buildCupertinoTheme.scaffold/bar → systemGroupedBackground；label 黑；primaryColor #007AFF | 会话列表局部 page 例外；导航底边/遮罩另算装饰 |
| CupertinoListSection.insetGrouped / CupertinoListTile | 分组底 systemGroupedBackground；白卡 secondarySystemGroupedBackground；separator；label / secondaryLabel；按下 systemGrey4 | 没有显式 color 的页面也使用这些语义；选中/按下不等于卡片边框 |
| CupertinoTextField | systemBackground / 默认输入框装饰，placeholderText，label；边框与光标另算 | 默认 placeholder 的 AA 数字见附录 |
| CupertinoSearchTextField | tertiarySystemFill 透明面，secondaryLabel 占位和图标 | 会话列表已显式白底+placeholder；其余按各页面底合成 |
| CupertinoButton / filled / AccessibleButton | primaryColor 动作字或按钮底，primaryContrastingColor 白字；禁用色由框架控制 | 普通动作正文、白字按钮、图标和禁用态分开验收 |
| CupertinoAlertDialog / CupertinoActionSheet / ModalPopup | SDK 动态背景/模糊/遮罩；label、destructiveRed、primaryColor | 透明背景/模糊须结合下层截图，不能静态保证所有任意下层 AA |

## 逐页、逐组件源色清单

每个表包含该文件的所有可解析显式颜色（含定义、分支和透明度别名），同色同用途合并行号。无显式颜色的 UI 文件仍列出默认控件；纯逻辑文件也单列覆盖清单。表内“复用色”按普通文字做保守的承载面参考，具体反色或非文本用途依局部组合/说明判定。

### P0 聊天

阶段二已接入局部 page/bar、可读次级文字及状态色、输入框/工具/审批/注入卡/媒体占位轮廓和选中按下面。assistant 正文仍直接落在页面底；共享 Markdown 默认不影响记忆和文件预览。用户主蓝气泡是 Leader 授权保留项；代码、链接、附件和引用局部底单独达 AA。确认弹窗仅调整浅色动作文字，保留 SDK 暗色默认。完整组合与限制见附录 P0。

#### `lib/features/chat/chat_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoTextField`、`CupertinoButton`、`CupertinoNavigationBar`、`CupertinoAlertDialog`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.page` L247 | 面 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.textSecondary` L277,1142,1357,1541,1695,1800 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L278,289 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L288,1125,1239 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.page` L403,404 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.userDetail` L405 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L428,436,630,638,661,722,730,756,808,828 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.card` L608,699,1187 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L610,701,1027,1091,1189,1295,1391,1454,1503,1648,1744 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.placeholder` L620,711,1203 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L669,764,1412 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.tintWarning` L1022,1447 | 面 | #FFF4E8 | 1.028595 | 1.084850 | 19.357512 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemOrange @ 0.12` L1023 | 暗色保留豁免 | #FF9500 / α=0.120000 | 1.091038 | 1.101384 | 1.142773 | 暗色保留豁免 |
| `statusOrangeText` L1040,1122,1468 | 文字 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemOrange` L1041 | 暗色保留豁免 | #FF9500 | 1.970414 | 2.198728 | 9.550978 | 暗色保留豁免 |
| `LightSurfaces.tintClarification` L1086 | 面 | #F3F2FF | 1.007248 | 1.107841 | 18.955790 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemIndigo @ 0.12` L1087 | 暗色保留豁免 | #5856D6 / α=0.120000 | 1.173728 | 1.182180 | 1.073074 | 暗色保留豁免 |
| `CupertinoColors.systemIndigo` L1102 | 图标/图形 | #5856D6 | 5.062968 | 5.649619 | 3.717065 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemIndigo` L1110 | 文字 | #5856D6 | 5.062968 | 5.649619 | 3.717065 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L1126,1143,1240 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `CupertinoColors.placeholderText` L1204 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.698832 | 1.725396 | 1.121334 | 暗色保留豁免 |
| `LightSurfaces.selection` L1288 | 面 | #E0ECFF | 1.068576 | 1.192393 | 17.611640 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemBlue @ 0.1` L1289 | 暗色保留豁免 | #007AFF / α=0.100000 | 1.130522 | 1.137765 | 1.068037 | 暗色保留豁免 |
| `CupertinoColors.systemBlue @ 0.2` L1296 | 暗色保留豁免 | #007AFF / α=0.200000 | 1.282430 | 1.300076 | 1.181780 | 暗色保留豁免 |
| `statusBlueText` L1308 | 图标/图形 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemBlue` L1309,1323,1341 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `statusBlueText` L1322,1340 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF8E8E93)` L1358,1542,1696,1801 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `LightSurfaces.tintError` L1384 | 面 | #FFF4F3 | 1.035448 | 1.077670 | 19.486486 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemRed @ 0.1` L1385 | 暗色保留豁免 | #FF3B30 / α=0.100000 | 1.136301 | 1.142997 | 1.070337 | 暗色保留豁免 |
| `CupertinoColors.systemRed @ 0.2` L1392 | 暗色保留豁免 | #FF3B30 / α=0.200000 | 1.294146 | 1.310797 | 1.196593 | 暗色保留豁免 |
| `CupertinoColors.systemRed` L1402,1423 | 图标/图形 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemYellow @ 0.15` L1448 | 暗色保留豁免 | #FFCC00 / α=0.150000 | 1.056810 | 1.071510 | 1.275209 | 暗色保留豁免 |
| `CupertinoColors.systemYellow @ 0.25` L1455 | 暗色保留豁免 | #FFCC00 / α=0.250000 | 1.094583 | 1.120768 | 1.689856 | 暗色保留豁免 |
| `CupertinoColors.systemBrown` L1469 | 暗色保留豁免 | #A2845E | 3.137394 | 3.500926 | 5.998413 | 暗色保留豁免 |
| `LightSurfaces.tintGreen` L1496 | 面 | #F0FAF2 | 1.044745 | 1.068080 | 19.661457 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGreen @ 0.12` L1497 | 暗色保留豁免 | #34C759 / α=0.120000 | 1.091985 | 1.102490 | 1.142405 | 暗色保留豁免 |
| `CupertinoColors.systemGreen @ 0.2` L1504 | 暗色保留豁免 | #34C759 / α=0.200000 | 1.157848 | 1.177121 | 1.322856 | 暗色保留豁免 |
| `statusGreenText` L1516,1668,1764 | 图标/图形 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGreen` L1517,1669,1765 | 暗色保留豁免 | #34C759 | 1.989440 | 2.219959 | 9.459636 | 暗色保留豁免 |
| `statusGreenText` L1528 | 文字 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF2C2C2E)` L1628,1729 | 暗色保留豁免 | #2C2C2E | 12.489479 | 13.936646 | 1.506819 | 暗色保留豁免 |
| `LightSurfaces.tintGreen` L1628,1729 | 面/复用 | #F0FAF2 | 1.044745 | 1.068080 | 19.661457 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.white @ 0.92` L1630,1731 | 暗色保留豁免 | #FFFFFF / α=0.920000 | 1.106310 | 1.000000 | 17.551417 | 暗色保留豁免 |
| `CupertinoColors.label` L1631,1732 | 文字/复用 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey @ 0.18` L1645,1741 | 暗色保留豁免 | #8E8E93 / α=0.180000 | 1.178927 | 1.195123 | 1.201993 | 暗色保留豁免 |
| `CupertinoColors.black` L1653,1749 | 装饰线/投影豁免 | #000000 | 18.819381 | 21.000000 | 1.000000 | 装饰线/投影豁免 |

#### `lib/features/chat/widgets/attachment_pending_bar.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L27,84 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L28,85 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L89 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L90 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.card` L94 | 面/复用 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemBackground` L95 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L151 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L152 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |

#### `lib/features/chat/widgets/chat_input_bar.dart`

默认控件：`CupertinoTextField`、`CupertinoAlertDialog`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusRedText` L494,536 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L499,529 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.divider` L590 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.separator` L591 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.divider` L682 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.systemGrey4` L683 | 暗色保留豁免 | #D1D1D6 | 1.363500 | 1.521490 | 13.802256 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L719,738,1105,1124 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF8E8E93)` L720,739,1106,1125 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `LightSurfaces.card` L804,1027 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L806,1029 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.placeholder` L817,1039 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemRed` L904,1176 | 图标/图形 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.activeBlue` L915,930,1187,1201 | 图标/图形 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 非文本：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/chat/widgets/chat_media_view.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoButton`、`CupertinoNavigationBar`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.card` L112,1150,1189 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey5` L113,1151,1190,1385 | 暗色保留豁免 | #E5E5EA | 1.125061 | 1.255423 | 16.727430 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L119,1196,1423 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.systemGrey4` L120,1197,1269 | 暗色保留豁免 | #D1D1D6 | 1.363500 | 1.521490 | 13.802256 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L138,1214 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L139,155,1215,1232,1395 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L154,1231,1245 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L172,1293 | 面 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 装饰面豁免；分层强弱见三向值 |
| `theme.primaryColor` L173,1294 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `CupertinoColors.white` L186,693,732,793,1324 | 文字 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.white` L601,611,684,723,781,1068,1075 | 图标/图形 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 非文本：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemBackground` L654 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey` L704,984 | 文字 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 固定黑底媒体文字；实际组合见 P0/media inverse secondary |
| `CupertinoColors.black` L715 | 面 | #000000 | 18.819381 | 21.000000 | 1.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.black @ 0.7` L717 | 面 | #000000 / α=0.700000 | 8.105273 | 8.520033 | 1.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.tertiaryLabel` L1246 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.698832 | 1.725396 | 1.121334 | 暗色保留豁免 |
| `LightSurfaces.pressed` L1268 | 面 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.label` L1280 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L1379 | 面/复用 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.white @ 0.22` L1380 | 暗色保留豁免 | #FFFFFF / α=0.220000 | 1.024816 | 1.000000 | 1.793638 | 暗色保留豁免 |
| `LightSurfaces.card` L1384 | 面/复用 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.white` L1388,1391 | 复用色；按承载面判级 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.label` L1389 | 复用色；按承载面判级 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L1394 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/chat/widgets/chat_message_list.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.label` L214,249 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `theme.primaryColor` L2504 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.secondarySystemGroupedBackground` L2506 | 面/复用 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L2511 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L2513 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `CupertinoColors.black @ 0.12` L2531 | 装饰线/投影豁免 | #000000 / α=0.120000 | 1.311692 | 1.315107 | 1.000000 | 装饰线/投影豁免 |
| `CupertinoColors.systemRed` L2702 | 复用色；按承载面判级 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemOrange` L2708,2715 | 复用色；按承载面判级 | #FF9500 | 1.970414 | 2.198728 | 9.550978 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L2724 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L2725,2808 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `CupertinoColors.systemYellow` L2734 | 复用色；按承载面判级 | #FFCC00 | 1.354970 | 1.511972 | 13.889146 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGreen` L2744,2754 | 复用色；按承载面判级 | #34C759 | 1.989440 | 2.219959 | 9.459636 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L2807 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/chat/widgets/chat_outline_sheet.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.card` L180 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemBackground` L181 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.divider` L187 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L188,215 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `CupertinoColors.black @ 0.12` L194 | 装饰线/投影豁免 | #000000 / α=0.120000 | 1.311692 | 1.315107 | 1.000000 | 装饰线/投影豁免 |
| `LightSurfaces.divider` L214 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `statusBlueText` L252 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.activeBlue` L253 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `CupertinoColors.label` L257 | 文字/复用 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.page` L274 | 面 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey5` L275 | 暗色保留豁免 | #E5E5EA | 1.125061 | 1.255423 | 16.727430 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L289 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L290 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |

#### `lib/features/chat/widgets/collapsible_process_capsule.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L93,178 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L94,179 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `Color(0x1F000000)` L100 | 复用色；按承载面判级 | #000000 / α=0.121569 | 1.316603 | 1.320084 | 1.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0x26FFFFFF)` L101 | 其他主题定义豁免 | #FFFFFF / α=0.149020 | 1.016768 | 1.000000 | 1.387647 | 其他主题定义豁免 |
| `statusBlueText` L120,211 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L192 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.tertiaryLabel` L193 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.698832 | 1.725396 | 1.121334 | 暗色保留豁免 |

#### `lib/features/chat/widgets/context_window_indicator.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.white @ 0.12` L51 | 暗色保留豁免 | #FFFFFF / α=0.120000 | 1.013489 | 1.000000 | 1.268235 | 暗色保留豁免 |
| `CupertinoColors.black @ 0.12` L52 | 复用色；按承载面判级 | #000000 / α=0.120000 | 1.311692 | 1.315107 | 1.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.white @ 0.92` L54 | 暗色保留豁免 | #FFFFFF / α=0.920000 | 1.106310 | 1.000000 | 17.551417 | 暗色保留豁免 |
| `CupertinoColors.black @ 0.82` L55 | 复用色；按承载面判级 | #000000 / α=0.820000 | 12.580032 | 13.598961 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L62 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemRed` L63 | 暗色保留豁免 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 暗色保留豁免 |
| `statusOrangeText` L68 | 复用色；按承载面判级 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemOrange` L69 | 暗色保留豁免 | #FF9500 | 1.970414 | 2.198728 | 9.550978 | 暗色保留豁免 |
| `CupertinoColors.label` L77 | 文字/复用 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L80 | 文字/复用 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L81 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |

#### `lib/features/chat/widgets/context_window_popover.dart`

默认控件：`CupertinoListTile`、`CupertinoTextField`、`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L318,537,1142,1160 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L319,538,975,1143,1161 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L532,1225,1230 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L533,1226,1231 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.card` L679,741,850,914 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemBackground` L680,742,851,915 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `CupertinoColors.label` L700,766,868,1275,1332,1390 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L974 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L1148 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemRed` L1149,1215 | 暗色保留豁免 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 暗色保留豁免 |
| `statusOrangeText` L1154 | 复用色；按承载面判级 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemOrange` L1155,1221 | 暗色保留豁免 | #FF9500 | 1.970414 | 2.198728 | 9.550978 | 暗色保留豁免 |
| `LightSurfaces.tintError` L1185 | 面 | #FFF4F3 | 1.035448 | 1.077670 | 19.486486 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemRed @ 0.12` L1186 | 暗色保留豁免 | #FF3B30 / α=0.120000 | 1.166066 | 1.174456 | 1.090290 | 暗色保留豁免 |
| `LightSurfaces.tintWarning` L1193 | 面 | #FFF4E8 | 1.028595 | 1.084850 | 19.357512 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemOrange @ 0.12` L1194 | 暗色保留豁免 | #FF9500 / α=0.120000 | 1.091038 | 1.101384 | 1.142773 | 暗色保留豁免 |
| `LightSurfaces.page` L1200,1205 | 面 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey5` L1201,1206 | 暗色保留豁免 | #E5E5EA | 1.125061 | 1.255423 | 16.727430 | 暗色保留豁免 |
| `statusRedText` L1214 | 装饰线/投影豁免 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 装饰线/投影豁免 |
| `statusOrangeText` L1220 | 装饰线/投影豁免 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 装饰线/投影豁免 |
| `statusBlueText` L1272,1329,1387 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.activeBlue` L1273,1288,1330,1345,1388,1403 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `statusBlueText` L1287,1344,1402 | 图标/图形 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.selection` L1423 | 复用色；按承载面判级 | #E0ECFF | 1.068576 | 1.192393 | 17.611640 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.card` L1423 | 复用色；按承载面判级 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.pressed` L1424 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

#### `lib/features/chat/widgets/injected_notice_card.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.cardBorder` L36 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L37 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.card` L41 | 面/复用 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemBackground` L42 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `CupertinoColors.label` L44 | 文字/复用 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L47 | 文字/复用 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L48 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.page` L52 | 面/复用 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey6` L53 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |

#### `lib/features/chat/widgets/markdown_styles.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.label` L81,457 | 文字/复用 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusBlueText` L87 | 文字/复用 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.link` L88 | 文字/复用 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 非聊天共享默认/暗色分支；聊天浅色已显式传入令牌 |
| `LightSurfaces.card` L90,462 | 面/复用 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey5` L91,463 | 面/复用 | #E5E5EA | 1.125061 | 1.255423 | 16.727430 | 非聊天共享默认/暗色分支；聊天浅色已显式传入令牌 |
| `LightSurfaces.divider` L93 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L94 | 装饰线/投影豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 装饰线/投影豁免 |
| `LightSurfaces.cardBorder` L96,468 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `statusBlueText` L144 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `theme.primaryColor` L144 | 文字 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.white` L152 | 复用色；按承载面判级 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.userDetail` L167,497 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L188,195,204 | 面 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 装饰面豁免；分层强弱见三向值 |
| `white @ 0.22` L189 | 暗色保留豁免 | #FFFFFF / α=0.220000 | 1.024816 | 1.000000 | 1.793638 | 暗色保留豁免 |
| `white @ 0.15` L196 | 暗色保留豁免 | #FFFFFF / α=0.150000 | 1.016879 | 1.000000 | 1.392133 | 暗色保留豁免 |
| `white @ 0.12` L205 | 暗色保留豁免 | #FFFFFF / α=0.120000 | 1.013489 | 1.000000 | 1.268235 | 暗色保留豁免 |
| `white @ 0.4` L213 | 装饰线/投影豁免 | #FFFFFF / α=0.400000 | 1.045403 | 1.000000 | 3.657366 | 装饰线/投影豁免 |
| `CupertinoColors.systemGrey5` L287 | 复用色；按承载面判级 | #E5E5EA | 1.125061 | 1.255423 | 16.727430 | 非聊天共享默认/暗色分支；聊天浅色已显式传入令牌 |
| `CupertinoColors.label` L296 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0x00000000)` L301 | 文字/复用 | #000000 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.white @ 0.22` L498 | 暗色保留豁免 | #FFFFFF / α=0.220000 | 1.024816 | 1.000000 | 1.793638 | 暗色保留豁免 |
| `CupertinoColors.white` L504 | 文字 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

#### `lib/features/chat/widgets/mermaid_block.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `core.Color(0x00000000)` L56 | 图表深色配置豁免 | #000000 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 图表深色配置豁免 |
| `core.Color(0xff2c2c2e)` L57,65,69 | 图表深色配置豁免 | #2C2C2E | 12.489479 | 13.936646 | 1.506819 | 图表深色配置豁免 |
| `core.Color(0xffffffff)` L58,63,68 | 图表深色配置豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 图表深色配置豁免 |
| `core.Color(0xff48484a)` L59,64,67 | 图表深色配置豁免 | #48484A | 8.177462 | 9.124992 | 2.301372 | 图表深色配置豁免 |
| `core.Color(0xff3a3a3c)` L60 | 图表深色配置豁免 | #3A3A3C | 10.170553 | 11.349024 | 1.850379 | 图表深色配置豁免 |
| `core.Color(0xff8e8e93)` L61,62 | 图表深色配置豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 图表深色配置豁免 |
| `core.Color(0xff1c1c1e)` L66 | 图表深色配置豁免 | #1C1C1E | 15.247942 | 17.014735 | 1.234224 | 图表深色配置豁免 |
| `CupertinoColors.label` L116 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L268 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L269,280 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L279 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/chat/widgets/mermaid_fullscreen_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoButton`、`CupertinoNavigationBar`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `Color(0xFF1C1C1E)` L30 | 面 | #1C1C1E | 15.247942 | 17.014735 | 1.234224 | 装饰面豁免；分层强弱见三向值 |
| `Color(0xCC1C1C1E)` L33 | 面 | #1C1C1E / α=0.800000 | 8.327541 | 8.930117 | 1.166066 | 装饰面豁免；分层强弱见三向值 |

#### `lib/features/chat/widgets/message_action_menu.dart`

默认控件：`CupertinoListTile`、`CupertinoButton`、`CupertinoAlertDialog`、`CupertinoActionSheet`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.userDetail` L63,242 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L66,253 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L69,78 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.placeholder` L300 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.placeholderText` L301 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.698832 | 1.725396 | 1.121334 | 暗色保留豁免 |
| `statusRedText` L306 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.destructiveRed` L307 | 暗色保留豁免 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 暗色保留豁免 |
| `CupertinoColors.label` L309 | 复用色；按承载面判级 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.card` L313 | 复用色；按承载面判级 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.pressed` L314 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

#### `lib/features/chat/widgets/message_bubble.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.activeBlue` L130 | 面 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.white` L269 | 文字 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.label` L355,532 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L441 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L442 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.card` L519 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey6` L520 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L523 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |

#### `lib/features/chat/widgets/message_highlight.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.systemYellow @ 0.28` L69 | 面 | #FFCC00 / α=0.280000 | 1.105861 | 1.135763 | 1.858581 | 装饰面豁免；分层强弱见三向值 |

#### `lib/features/chat/widgets/perf_monitor_panel.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusRedText` L241 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemRed` L242 | 暗色保留豁免 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 暗色保留豁免 |
| `statusOrangeText` L248 | 复用色；按承载面判级 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemOrange` L249 | 暗色保留豁免 | #FF9500 | 1.970414 | 2.198728 | 9.550978 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L254,273,516 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L255,274,517 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |

#### `lib/features/chat/widgets/selected_context_card.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.cardBorder` L28 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L29 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.card` L33 | 面/复用 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemBackground` L34 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L38 | 文字/复用 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L39 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `statusBlueText` L43 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.activeBlue` L44 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |

#### `lib/features/chat/widgets/selection_chips.dart`

默认控件：`CupertinoTextField`、`CupertinoButton`、`CupertinoAlertDialog`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L53 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L54,93 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L82,206 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L83 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.card` L87 | 面/复用 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemBackground` L88 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L92 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusBlueText` L136 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.activeBlue` L137 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `LightSurfaces.card` L204 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.placeholder` L216 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L229,236 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/chat/widgets/steer_banner.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `Color(0xFF2C2C2E)` L32,101 | 暗色保留豁免 | #2C2C2E | 12.489479 | 13.936646 | 1.506819 | 暗色保留豁免 |
| `LightSurfaces.card` L35,104 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey6` L36,105 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L42,111 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L43,112 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L55,124 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L56,71,125,144,160 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L70,143,159 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.selection` L174 | 面 | #E0ECFF | 1.068576 | 1.192393 | 17.611640 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.activeBlue @ 0.12` L175 | 暗色保留豁免 | #007AFF / α=0.120000 | 1.159087 | 1.168124 | 1.085680 | 暗色保留豁免 |
| `statusBlueText` L186 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.activeBlue` L187 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |

#### `lib/features/chat/widgets/tool_call_card.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusRedText` L90 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemRed` L91,488,527 | 暗色保留豁免 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 暗色保留豁免 |
| `statusBlueText` L96 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.activeBlue` L97,159,259,292,474 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `statusGreenText` L101 | 复用色；按承载面判级 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGreen` L102,493 | 暗色保留豁免 | #34C759 | 1.989440 | 2.219959 | 9.459636 | 暗色保留豁免 |
| `CupertinoColors.systemRed @ 0.08` L105 | 面/复用 | #FF3B30 / α=0.080000 | 1.107398 | 1.112530 | 1.052766 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.activeBlue @ 0.08` L107 | 面/复用 | #007AFF / α=0.080000 | 1.102812 | 1.108385 | 1.052763 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemTeal @ 0.08` L110 | 面/复用 | #5AC8FA / α=0.080000 | 1.044950 | 1.052306 | 1.093510 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.tintError` L131 | 面 | #FFF4F3 | 1.035448 | 1.077670 | 19.486486 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.card` L133,445 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.tintGreen` L134 | 面 | #F0FAF2 | 1.044745 | 1.068080 | 19.661457 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L138,452,859 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `statusBlueText` L158,258,291,473 | 图标/图形 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L192,210,270,303,538 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L193,211,224,271,304,539,552,843 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L223,551 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.divider` L326 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey4` L327,453 | 暗色保留豁免 | #D1D1D6 | 1.363500 | 1.521490 | 13.802256 | 暗色保留豁免 |
| `CupertinoColors.label` L346,435,882 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey6` L446 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `statusRedText` L487 | 图标/图形 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `statusGreenText` L492 | 图标/图形 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L526 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L842 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.tintClarification` L853 | 面 | #F3F2FF | 1.007248 | 1.107841 | 18.955790 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemPurple @ 0.08` L854 | 暗色保留豁免 | #AF52DE / α=0.080000 | 1.098178 | 1.103836 | 1.055732 | 暗色保留豁免 |
| `CupertinoColors.systemPurple` L874 | 图标/图形 | #AF52DE | 3.701328 | 4.130204 | 5.084495 | 非文本：页面达 / 白卡达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/chat/chat_controller.dart`、`lib/features/chat/chat_diff_merge.dart`、`lib/features/chat/chat_draft_provider.dart`、`lib/features/chat/chat_models.dart`、`lib/features/chat/chat_providers.dart`、`lib/features/chat/chat_server_api.dart`、`lib/features/chat/chat_state.dart`、`lib/features/chat/pending_attachments_provider.dart`、`lib/features/chat/selection_provider.dart`、`lib/features/chat/widgets/chat_media_parser.dart`、`lib/features/chat/widgets/chat_text_selection.dart`。

### P1 自适应外壳

侧栏工具条接 page、textSecondary、selection，空态详情使用白面和可读次级文字，新建按钮使用局部状态蓝。分栏手柄及工具条结构线复用 divider。固定反色退出 toast 保持原样，附录 P1 给出实算。导航/拖拽回调、外壳布局和所有暗色分支不变。

#### `lib/app/shell/adaptive_shell.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.black @ 0.82` L228 | 面 | #000000 / α=0.820000 | 12.580032 | 13.598961 | 1.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.black @ 0.2` L232 | 装饰线/投影豁免 | #000000 / α=0.200000 | 1.598086 | 1.605929 | 1.000000 | 装饰线/投影豁免 |
| `CupertinoColors.white` L241 | 文字 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

#### `lib/app/shell/empty_detail_pane.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoButton`。

参考页面 P=#FFFFFF；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.card` L24 | 面 | #FFFFFF | 1.000000 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.textSecondary` L37 | 图标/图形 | #6A6A6F | 5.379116 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.tertiaryLabel` L38 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.725396 | 1.725396 | 1.121334 | 暗色保留豁免 |
| `CupertinoColors.label` L47 | 文字 | #000000 | 21.000000 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L60 | 文字 | #6A6A6F | 5.379116 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L61 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.438200 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `statusBlueText` L67 | 面 | #005FB8 | 6.308159 | 6.308159 | 3.329022 | 装饰面豁免；分层强弱见三向值 |

#### `lib/app/shell/sidebar_resize_handle.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.divider` L49 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.separator` L50 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |

#### `lib/app/shell/sidebar_utility_toolbar.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusBlueText` L97 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `theme.primaryColor` L98 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L101 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L102 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.selection` L141 | 复用色；按承载面判级 | #E0ECFF | 1.068576 | 1.192393 | 17.611640 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.transparent` L143 | 复用色；按承载面判级 | #000000 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.divider` L164 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.separator` L165 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.page` L171 | 面 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/app/shell/android_back_interceptor.dart`、`lib/app/shell/session_sidebar.dart`。

### P1 通用导航、菜单和浮层

通用 popover/dropdown 接白面与 cardBorder，标题、副标、普通/强调/危险动作文字和按下面完成局部核验。原生操作表用更深动作蓝适配半透明按下面，保留原生面、遮罩和行为；阴影只作装饰豁免。导航代理本身无独立低对比文字，返回/下拉图标继承色按 3:1 验收。

#### `lib/app/widgets/adaptive_action_menu.dart`

默认控件：`CupertinoListTile`、`CupertinoButton`、`CupertinoActionSheet`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L86,128 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L87 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.divider` L98 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.separator` L99 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `statusRedText` L146 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L147,160 | 文字 | #004A94 | 7.818165 | 8.724063 | 2.407135 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L188 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.destructiveRed` L189 | 暗色保留豁免 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 暗色保留豁免 |
| `statusBlueText` L194 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.activeBlue` L195 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `CupertinoColors.label` L197 | 复用色；按承载面判级 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.card` L209 | 复用色；按承载面判级 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.pressed` L210 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

#### `lib/app/widgets/adaptive_popover.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `Color(0x00000000)` L371 | 面 | #000000 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.card` L405 | 面/复用 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemBackground` L406 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L415 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.systemGrey4` L416 | 暗色保留豁免 | #D1D1D6 | 1.363500 | 1.521490 | 13.802256 | 暗色保留豁免 |
| `CupertinoColors.systemGrey3 @ 0.5` L422 | 装饰线/投影豁免 | #C7C7CC / α=0.500000 | 1.218767 | 1.281204 | 3.531785 | 装饰线/投影豁免 |

#### `lib/app/widgets/adaptive_sliver_navigation_bar.dart`

默认控件：`CupertinoNavigationBar`。

无额外显式颜色，继承上表语义。

#### `lib/app/widgets/large_title_sliver_header.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.label` L147 | 文字/复用 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/app/widgets/popover_dropdown.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.card` L19 | 面/复用 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemBackground` L20 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L24 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L25 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `CupertinoColors.systemGrey3 @ 0.35` L36 | 装饰线/投影豁免 | #C7C7CC / α=0.350000 | 1.146727 | 1.186447 | 2.217171 | 装饰线/投影豁免 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/app/widgets/cupertino_popover.dart`、`lib/app/widgets/hermes_page_route.dart`、`lib/app/widgets/narrow_navigation_dropdown.dart`。

### P2 看板

卡片 secondarySystemBackground 与旧分组页面底同为浅灰，不能形成卡片层级；灰色描边只提供弱轮廓。顶部选中标签为蓝底白字，详情/元数据 secondaryText，failed 状态仍返回 systemRed。建议白卡+轮廓、可读状态文字、选择状态和详情空占位一起迁移；预计涉及看板列/卡片/详情/创建弹层，不涉及 WS 或排序逻辑。

#### `lib/features/kanban/kanban_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoTextField`、`CupertinoButton`、`CupertinoNavigationBar`、`CupertinoAlertDialog`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `Color(0xFF111113)` L20 | 复用色；按承载面判级 | #111113 | 16.902364 | 18.860856 | 1.113417 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF3A3A3C)` L21 | 装饰线/投影豁免 | #3A3A3C | 10.170553 | 11.349024 | 1.850379 | 装饰线/投影豁免 |
| `Color(0xFF2C2C2E)` L22 | 面/复用 | #2C2C2E | 12.489479 | 13.936646 | 1.506819 | 装饰面豁免；分层强弱见三向值 |
| `Color(0xFF4A3F14)` L24 | 面/复用 | #4A3F14 | 9.352299 | 10.435958 | 2.012273 | 装饰面豁免；分层强弱见三向值 |
| `statusGreyText` L81 | 复用色；按承载面判级 | #595959 | 6.277365 | 7.004729 | 2.997975 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusBlueText` L83,999,1474,1478 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusOrangeText` L87 | 复用色；按承载面判级 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusGreenText` L91 | 复用色；按承载面判级 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusTealText` L102,103 | 复用色；按承载面判级 | #0E7C86 | 4.432283 | 4.945856 | 4.245979 | 正文 AA：页面不达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemRed` L106 | 复用色；按承载面判级 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `statusRedText` L107,108 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L111 | 复用色；按承载面判级 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L112 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemPurple` L115,116 | 复用色；按承载面判级 | #AF52DE | 3.701328 | 4.130204 | 5.084495 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.selection` L254,262,1002,1395,1477 | 复用色；按承载面判级 | #E0ECFF | 1.068576 | 1.192393 | 17.611640 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.pressed` L256,1002 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.card` L257,1394 | 复用色；按承载面判级 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.activeBlue` L259 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.transparent` L263 | 复用色；按承载面判级 | #000000 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `statusBlueText` L274 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.label` L275,279,699,782,915 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.black` L278 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.activeBlue` L290 | 面 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L308,683,1388,1496,1506 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.divider` L342 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.textSecondary` L384,422,460,713,1217 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L385,423,461,714,1218 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L397,435,581,601,727,912,970,1068,1093,1312,1347,1416 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L398,436,582,602,728,913,971,1069,1094,1313,1348,1417 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `statusRedText` L475,1234 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L517,1190 | 文字 | #004A94 | 7.818165 | 8.724063 | 2.407135 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.pressed` L675 | 面 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.card` L675,1492,1504 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemBackground` L676 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.tintWarning` L757 | 面 | #FFF4E8 | 1.028595 | 1.084850 | 19.357512 | 装饰面豁免；分层强弱见三向值 |
| `statusOrangeText` L770 | 图标/图形 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemYellow` L771 | 暗色保留豁免 | #FFCC00 | 1.354970 | 1.511972 | 13.889146 | 暗色保留豁免 |
| `LightSurfaces.page` L891,941,1020,1046,1472,1473 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGroupedBackground` L892,942,1021,1047 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.divider` L896,946,1025,1051 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.divider` L1486 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.placeholder` L1514 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/kanban/kanban_api.dart`、`lib/features/kanban/kanban_providers.dart`。

### P2 洞察/用量

分组统计卡继承白卡，secondaryText 用于时间、说明及坐标轴；蓝色柱本身可按非文本图形判级，但轴标签仍须正文 AA。#004999 是柱图触摸态，属于数据图形，不能当浅色卡片替换。建议卡片轮廓及轴标签优先，保留现有柱形高亮；预计影响统计总览、模型列表及日用量图。

#### `lib/features/insights/insights_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoListTile`、`CupertinoButton`、`CupertinoAlertDialog`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.page` L61,62 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.page` L99 | 面/复用 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGroupedBackground` L100 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.divider` L104 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L105 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.card` L110 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L112 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.textSecondary` L237,255,292,384,528,669 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L238,256,293,385,670 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L316,366 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF8E8E93)` L318,368 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `statusRedText` L332 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusBlueText` L339 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemBlue` L501,630 | 图标/图形 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `statusBlueText` L540 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF007AFF)` L542 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `Color(0xFF004999)` L629 | 图标/图形 | #004999 | 7.799167 | 8.702863 | 2.412999 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L741 | 文字 | #004A94 | 7.818165 | 8.724063 | 2.407135 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/insights/insights_api.dart`、`lib/features/insights/insights_providers.dart`。

### P3 设置及全部子区

settings_page / settings_subpages / profile / extensions / MCP / auxiliary_models / webui_sidecar 都继承分组面。先修服务器地址、说明、辅助模型元数据以及输入框 placeholder；各状态色虽有 AA 版，仍要核对 resolve 与真实背景。新增面令牌按子区接入，影响全部设置表单、子页和弹层；不改持久化键或文案。

#### `lib/features/settings/auxiliary_models_section.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoListTile`、`CupertinoNavigationBar`、`CupertinoAlertDialog`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L82,127,237,308 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L83,128,238,309 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L137 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF8E8E93)` L138 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |

#### `lib/features/settings/extensions_section.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoListTile`、`CupertinoTextField`、`CupertinoButton`、`CupertinoNavigationBar`、`CupertinoAlertDialog`、`CupertinoActionSheet`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L77,119,355 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L78,120,356 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `statusGreenText` L116 | 文字 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L365 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF8E8E93)` L366 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `statusRedText` L411 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/settings/mcp_section.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoListTile`、`CupertinoTextField`、`CupertinoButton`、`CupertinoNavigationBar`、`CupertinoAlertDialog`、`CupertinoActionSheet`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusGreenText` L106 | 文字 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusGreyText` L106 | 文字 | #595959 | 6.277365 | 7.004729 | 2.997975 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L458 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L496,520 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L497,521 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |

#### `lib/features/settings/profile_section.dart`

默认控件：`CupertinoListSection`、`CupertinoListTile`、`CupertinoAlertDialog`、`CupertinoActionSheet`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusRedText` L77 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/settings/settings_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoListTile`、`CupertinoTextField`、`CupertinoButton`、`CupertinoNavigationBar`、`CupertinoAlertDialog`、`CupertinoActionSheet`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L335,1066,1500,1527,1554,1567,1920,2113 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L336,1067,1501,1528,1555,1568,1921 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L346,571,589,604,620,638,656,674,692 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L347 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `Color(0xFF8E8E93)` L572,590,605,621,639,657,675,693 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `statusBlueText` L974 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemBlue` L1079 | 图标/图形 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L1102,1319,1592,1876 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemRed` L1103 | 暗色保留豁免 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 暗色保留豁免 |
| `LightSurfaces.menuAction` L1107 | 文字 | #004A94 | 7.818165 | 8.724063 | 2.407135 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.activeBlue` L1108 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `statusRedText` L1141,1864,1902 | 图标/图形 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFFFF3B30)` L1142,1865,1877,1903 | 暗色保留豁免 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 暗色保留豁免 |
| `LightSurfaces.tintError` L1841 | 面 | #FFF4F3 | 1.035448 | 1.077670 | 19.486486 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.destructiveRed` L1842,1851 | 暗色保留豁免 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 暗色保留豁免 |
| `LightSurfaces.divider` L1850 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `secondaryText` L2114 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |

#### `lib/features/settings/settings_subpages.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoListTile`、`CupertinoNavigationBar`。

无额外显式颜色，继承上表语义。

#### `lib/features/settings/settings_surfaces.dart`

默认控件：`CupertinoListSection`、`CupertinoListTile`、`CupertinoButton`、`CupertinoAlertDialog`、`CupertinoActionSheet`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.page` L21,22,45,286 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.selection` L25,151,287 | 复用色；按承载面判级 | #E0ECFF | 1.068576 | 1.192393 | 17.611640 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.divider` L49 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L57,106,362 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.card` L63,156 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L78,157 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.divider` L89 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.pressed` L125 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L133,143 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.white` L162 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.black` L163 | 其他主题定义豁免 | #000000 | 18.819381 | 21.000000 | 1.000000 | 其他主题定义豁免 |
| `Color(0x33000000)` L168 | 装饰线/投影豁免 | #000000 / α=0.200000 | 1.598086 | 1.605929 | 1.000000 | 装饰线/投影豁免 |
| `Color(0x33FFFFFF)` L169 | 其他主题定义豁免 | #FFFFFF / α=0.200000 | 1.022544 | 1.000000 | 1.662095 | 其他主题定义豁免 |
| `LightSurfaces.placeholder` L182 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.placeholderText` L183 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.698832 | 1.725396 | 1.121334 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L190,262,352 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L190,355 | 复用色；按承载面判级 | #004A94 | 7.818165 | 8.724063 | 2.407135 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.divider` L237 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `Color(0x4D000000)` L238 | 暗色保留豁免 | #000000 / α=0.301961 | 2.101806 | 2.120350 | 1.000000 | 暗色保留豁免 |
| `CupertinoColors.black` L258,261 | 复用色；按承载面判级 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusGreenText` L259 | 复用色；按承载面判级 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.card` L263,264 | 复用色；按承载面判级 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `statusRedText` L307 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L308 | 文字 | #004A94 | 7.818165 | 8.724063 | 2.407135 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L354 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/settings/webui_sidecar_section.dart`

默认控件：`CupertinoListSection`、`CupertinoListTile`、`CupertinoTextField`、`CupertinoButton`、`CupertinoAlertDialog`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L273,375,447 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L274,284,448,522 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L283,521 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L318,344,402 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF8E8E93)` L376 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `statusGreenText` L471 | 复用色；按承载面判级 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusBlueText` L491 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L494,504 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusGreyText` L507 | 复用色；按承载面判级 | #595959 | 6.277365 | 7.004729 | 2.997975 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/settings/chat_send_shortcut_settings.dart`、`lib/features/settings/composer_settings.dart`、`lib/features/settings/cron_visibility_settings.dart`、`lib/features/settings/injected_notice_settings.dart`、`lib/features/settings/perf_monitor_settings.dart`、`lib/features/settings/settings_providers.dart`、`lib/features/settings/smooth_streaming_settings.dart`、`lib/features/settings/tool_group_settings.dart`。

### P4 引导页、连接向导与安装向导

hero 中 #E5E5EA 是品牌图标承载面，柔光/轨道/配准线为 ExcludeSemantics 内的装饰，不承担表单可读性；保持动画设计，不用提高装饰对比度替代文字修复。优先修连接表单 placeholder、说明、错误/步骤状态和安装日志的真实承载面。预计影响宽屏品牌/表单双栏及窄屏连接表单，保持 reduceMotion 和窄屏几何。

#### `lib/features/onboarding/install_guide_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoTextField`、`CupertinoButton`、`CupertinoNavigationBar`、`CupertinoActionSheet`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L308,518,546,558,693,808,917,1105 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L335,367 | 文字 | #004A94 | 7.818165 | 8.724063 | 2.407135 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusGreyText` L345 | 文字 | #595959 | 6.277365 | 7.004729 | 2.997975 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L346,519,547,559,694,809,918,1106 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `statusGreenText` L355,655 | 图标/图形 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.page` L387,397 | 面 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.divider` L392,605,788,950 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `statusOrangeText` L426 | 图标/图形 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemYellow` L427 | 暗色保留豁免 | #FFCC00 | 1.354970 | 1.511972 | 13.889146 | 暗色保留豁免 |
| `LightSurfaces.userDetail` L439,1075,1123,1164 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.divider` L571,619 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey5` L572 | 暗色保留豁免 | #E5E5EA | 1.125061 | 1.255423 | 16.727430 | 暗色保留豁免 |
| `statusGreenText` L582 | 面 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.card` L598,781,889 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemGroupedBackground` L599,782 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `CupertinoColors.separator` L606,620,789,951 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L643,930,1086 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.tertiaryLabel` L644 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.698832 | 1.725396 | 1.121334 | 暗色保留豁免 |
| `statusRedText` L662,732 | 图标/图形 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.tintError` L712 | 面 | #FFF4F3 | 1.035448 | 1.077670 | 19.486486 | 装饰面豁免；分层强弱见三向值 |
| `statusRedText @ 0.08` L713 | 暗色保留豁免 | #B3001B / α=0.080000 | 1.157968 | 1.161333 | 1.020135 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L719,894 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `statusRedText @ 0.3` L720 | 暗色保留豁免 | #B3001B / α=0.300000 | 1.790104 | 1.816604 | 1.158749 | 暗色保留豁免 |
| `statusRedText` L740,750,871 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L759 | 面 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.white` L765,1000,1020 | 文字 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.tertiarySystemFill` L890 | 暗色保留豁免 | #767680 / α=0.117647 | 1.141332 | 1.150191 | 1.087601 | 暗色保留豁免 |
| `CupertinoColors.systemGrey` L931 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `CupertinoColors.darkBackgroundGray` L945 | 面 | #171717 | 16.066232 | 17.927840 | 1.171363 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey` L969 | 图标/图形 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 非文本：页面不达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L976,1040 | 文字 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.black` L1034 | 面 | #000000 | 18.819381 | 21.000000 | 1.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGreen` L1052 | 文字 | #34C759 | 1.989440 | 2.219959 | 9.459636 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGrey4` L1139 | 复用色；按承载面判级 | #D1D1D6 | 1.363500 | 1.521490 | 13.802256 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.black` L1148 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/onboarding/onboarding_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoTextField`、`CupertinoButton`、`CupertinoNavigationBar`、`CupertinoAlertDialog`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusRedText` L346,653,773 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L356 | 文字 | #004A94 | 7.818165 | 8.724063 | 2.407135 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.page` L396,406,433,443 | 面 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.divider` L401,438 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.textSecondary` L512,590,632,674,712,752 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L513,591,633,675,713,753 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.userDetail` L543 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L550 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `statusGreenText` L644,695,764 | 文字 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusGreenText` L687 | 图标/图形 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 非文本：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/onboarding/widgets/builtin_tab.dart`

默认控件：`CupertinoListSection`、`CupertinoListTile`、`CupertinoTextField`、`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L376,459,760,903 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L377,460,761,774,904 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.tintWarning` L412 | 面 | #FFF4E8 | 1.028595 | 1.084850 | 19.357512 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemOrange @ 0.12` L413,549 | 暗色保留豁免 | #FF9500 / α=0.120000 | 1.091038 | 1.101384 | 1.142773 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L421,612,649,798 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.systemOrange @ 0.35` L422 | 暗色保留豁免 | #FF9500 / α=0.350000 | 1.287731 | 1.327518 | 1.921126 | 暗色保留豁免 |
| `statusOrangeText` L436 | 图标/图形 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `statusOrangeText` L446 | 文字 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusOrangeText` L476 | 面 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.activeOrange` L477 | 暗色保留豁免 | #FF9500 | 1.970414 | 2.198728 | 9.550978 | 暗色保留豁免 |
| `CupertinoColors.white` L488 | 文字 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.pressed` L504 | 面 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey5` L505 | 暗色保留豁免 | #E5E5EA | 1.125061 | 1.255423 | 16.727430 | 暗色保留豁免 |
| `CupertinoColors.label` L516 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusOrangeText` L545 | 复用色；按承载面判级 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.tintWarning` L548 | 复用色；按承载面判级 | #FFF4E8 | 1.028595 | 1.084850 | 19.357512 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `statusGreenText` L562 | 复用色；按承载面判级 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.tintGreen` L565 | 复用色；按承载面判级 | #F0FAF2 | 1.044745 | 1.068080 | 19.661457 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGreen @ 0.12` L566 | 暗色保留豁免 | #34C759 / α=0.120000 | 1.091985 | 1.102490 | 1.142405 | 暗色保留豁免 |
| `statusBlueText` L572 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.selection` L575 | 复用色；按承载面判级 | #E0ECFF | 1.068576 | 1.192393 | 17.611640 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemBlue @ 0.12` L576 | 暗色保留豁免 | #007AFF / α=0.120000 | 1.159087 | 1.168124 | 1.085680 | 暗色保留豁免 |
| `statusRedText` L582 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.tintError` L585 | 复用色；按承载面判级 | #FFF4F3 | 1.035448 | 1.077670 | 19.486486 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemRed @ 0.12` L586 | 暗色保留豁免 | #FF3B30 / α=0.120000 | 1.166066 | 1.174456 | 1.090290 | 暗色保留豁免 |
| `statusGreyText` L592 | 复用色；按承载面判级 | #595959 | 6.277365 | 7.004729 | 2.997975 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.page` L595 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGrey @ 0.12` L596 | 暗色保留豁免 | #8E8E93 / α=0.120000 | 1.114697 | 1.124644 | 1.112837 | 暗色保留豁免 |
| `LightSurfaces.tintError` L642 | 面 | #FFF4F3 | 1.035448 | 1.077670 | 19.486486 | 装饰面豁免；分层强弱见三向值 |
| `statusRedText @ 0.08` L643 | 暗色保留豁免 | #B3001B / α=0.080000 | 1.157968 | 1.161333 | 1.020135 | 暗色保留豁免 |
| `statusRedText @ 0.25` L650 | 暗色保留豁免 | #B3001B / α=0.250000 | 1.614942 | 1.633458 | 1.113405 | 暗色保留豁免 |
| `statusRedText` L663,817,857,939 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusBlueText` L680 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L699,722 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L729,773,968 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.card` L796 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.divider` L803 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.separator` L804 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `CupertinoColors.secondaryLabel` L969 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |

#### `lib/features/onboarding/widgets/onboarding_field_style.dart`

默认控件：`CupertinoTextField`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.card` L12 | 复用色；按承载面判级 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.cardBorder` L13 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.placeholder` L22 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/onboarding/widgets/onboarding_hero_motion.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.label` L140 | 复用色；按承载面判级 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L253 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L254 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `Color(0xFF1C1C1E)` L276 | 暗色保留豁免 | #1C1C1E | 15.247942 | 17.014735 | 1.234224 | 暗色保留豁免 |
| `Color(0xFFE5E5EA)` L277 | 面 | #E5E5EA | 1.125061 | 1.255423 | 16.727430 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.separator` L280 | 装饰线/投影豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 装饰线/投影豁免 |
| `CupertinoColors.white` L291 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `CupertinoColors.black` L292 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0x384F6076)` L319 | 纯装饰豁免 | #4F6076 / α=0.219608 | 1.357617 | 1.375907 | 1.147194 | 纯装饰豁免 |
| `Color(0x18546983)` L319 | 纯装饰豁免 | #546983 / α=0.094118 | 1.126773 | 1.133098 | 1.058581 | 纯装饰豁免 |
| `Color(0x00546983)` L319 | 纯装饰豁免 | #546983 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 纯装饰豁免 |
| `Color(0xE6FFFFFF)` L320 | 纯装饰豁免 | #FFFFFF / α=0.901961 | 1.104161 | 1.000000 | 16.825959 | 纯装饰豁免 |
| `Color(0x1895A4B9)` L320 | 纯装饰豁免 | #95A4B9 / α=0.094118 | 1.069922 | 1.078070 | 1.097879 | 纯装饰豁免 |
| `Color(0x0095A4B9)` L320 | 纯装饰豁免 | #95A4B9 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 纯装饰豁免 |
| `Color(0x26CCD4DF)` L324 | 纯装饰豁免 | #CCD4DF / α=0.149020 | 1.042478 | 1.057795 | 1.280875 | 纯装饰豁免 |
| `Color(0x22596879)` L325 | 纯装饰豁免 | #596879 / α=0.133333 | 1.186782 | 1.196394 | 1.085103 | 纯装饰豁免 |
| `Color(0x466F8299)` L327 | 纯装饰豁免 | #6F8299 / α=0.274510 | 1.342829 | 1.370545 | 1.338633 | 纯装饰豁免 |
| `Color(0x3864788E)` L328 | 纯装饰豁免 | #64788E / α=0.219608 | 1.290641 | 1.310354 | 1.204910 | 纯装饰豁免 |
| `Color(0x405F6C7D)` L330 | 纯装饰豁免 | #5F6C7D / α=0.250980 | 1.378437 | 1.401588 | 1.216382 | 纯装饰豁免 |
| `Color(0x305D626B)` L331 | 纯装饰豁免 | #5D626B / α=0.188235 | 1.288334 | 1.303141 | 1.124429 | 纯装饰豁免 |
| `Color(0x998CA4BC)` L333 | 纯装饰豁免 | #8CA4BC / α=0.600000 | 1.604304 | 1.698227 | 3.376596 | 纯装饰豁免 |
| `Color(0x80778CA1)` L334 | 纯装饰豁免 | #778CA1 / α=0.501961 | 1.672526 | 1.746116 | 2.191687 | 纯装饰豁免 |

#### `lib/features/onboarding/widgets/wide_dual_pane.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.divider` L55 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.separator` L56 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `Color(0xFF0A0A0C)` L88 | 暗色保留豁免 | #0A0A0C | 17.726852 | 19.780878 | 1.061631 | 暗色保留豁免 |
| `CupertinoColors.systemGroupedBackground` L89 | 面 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/onboarding/onboarding_providers.dart`。

### 后续 会话工作区

文件列表、空态和选中文件信息仍使用分组面及 secondaryText。建议白卡轮廓、可读的文件大小/路径/空态提示；选中态和媒体反色控件单列。影响单会话浏览/上传/预览，不改文件/API 操作。

#### `lib/features/workspace/workspace_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoTextField`、`CupertinoButton`、`CupertinoAlertDialog`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.card` L248 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L251 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.divider` L258 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L289,342,701,739,788,977,996 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L290,343 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `statusRedText` L304 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L311 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L356,661,712,750,811,838,866,959 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L357,662,839,867,960 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `CupertinoColors.quaternaryLabel` L688,726,799 | 复用色；按承载面判级 | #3C3C43 / α=0.176471 | 1.351231 | 1.362437 | 1.064897 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.userDetail` L702,740 | 图标/图形 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L713,751,812,880 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.tertiaryLabel` L789,978 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.698832 | 1.725396 | 1.121334 | 暗色保留豁免 |
| `CupertinoColors.systemRed` L854 | 图标/图形 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L997 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `CupertinoColors.tertiarySystemFill` L1029 | 面 | #767680 / α=0.117647 | 1.141332 | 1.150191 | 1.087601 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemFill` L1030 | 面 | #787880 / α=0.156863 | 1.191278 | 1.203984 | 1.129452 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondaryLabel` L1042,1107 | 复用色；按承载面判级 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L1043 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGreen` L1045,1070,1089 | 复用色；按承载面判级 | #34C759 | 1.989440 | 2.219959 | 9.459636 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `statusGreenText` L1046 | 复用色；按承载面判级 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemTeal` L1048,1074,1079 | 复用色；按承载面判级 | #5AC8FA | 1.698980 | 1.895843 | 11.076868 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `statusTealText` L1049 | 复用色；按承载面判级 | #0E7C86 | 4.432283 | 4.945856 | 4.245979 | 正文 AA：页面不达 / 白卡达；反色见局部组合 |
| `CupertinoColors.label` L1056 | 复用色；按承载面判级 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemBlue` L1062,1097 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemPurple` L1064,1102 | 复用色；按承载面判级 | #AF52DE | 3.701328 | 4.130204 | 5.084495 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemPink` L1066,1105 | 复用色；按承载面判级 | #FF2D55 | 3.268088 | 3.646764 | 5.758530 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/workspace/workspace_api.dart`、`lib/features/workspace/workspace_providers.dart`。

### 后续 工作区管理及共享文件预览

注册表、添加 Sheet、文件预览正文分属不同承载面。预览代码背景 systemGrey6 与页面灰接近；多媒体黑底上的白字属于反色 UI，保留语义并按实际黑底测量。建议目录/路径/元数据先修，office/媒体预览单独做视觉验收。影响注册表及聊天附件/下载复用的预览入口。

#### `lib/features/workspace_manager/add_workspace_sheet.dart`

默认控件：`CupertinoTextField`、`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.systemBlue` L105,203 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `statusBlueText` L106 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.inactiveGray` L108 | 暗色保留豁免 | #999999 | 2.553188 | 2.849028 | 7.370936 | 暗色保留豁免 |
| `LightSurfaces.placeholder` L109 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.page` L117 | 面 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemBackground` L118 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `statusRedText` L146 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.tertiaryLabel` L172 | 面 | #3C3C43 / α=0.298039 | 1.698832 | 1.725396 | 1.121334 | 装饰面豁免；分层强弱见三向值 |
| `statusBlueText` L204 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondarySystemBackground` L245 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.card` L246 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L250 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.placeholder` L266,303 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.placeholderText` L267,304 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.698832 | 1.725396 | 1.121334 | 暗色保留豁免 |
| `CupertinoColors.transparent` L273,310 | 面 | #000000 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.textSecondary` L360 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L361 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.divider` L384,416 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.separator` L385,417 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.pressed` L404 | 面 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.tertiarySystemFill` L405 | 暗色保留豁免 | #767680 / α=0.117647 | 1.141332 | 1.150191 | 1.087601 | 暗色保留豁免 |
| `LightSurfaces.userDetail` L437 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/workspace_manager/file_preview_body.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L686,1104,1163 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L687,1105,1164 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `CupertinoColors.systemBackground` L723 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.divider` L869 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.separator` L870,974 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `CupertinoColors.secondarySystemBackground` L879 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.card` L882 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L886 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.tertiarySystemFill` L897 | 面 | #767680 / α=0.117647 | 1.141332 | 1.150191 | 1.087601 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.textSecondary` L909,950,1009,1084,1121,1326,1337 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L910,951,1010,1085,1122,1327,1338 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.divider` L973 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.userDetail` L1134,1189 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L1178 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.activeBlue` L1293 | 图标/图形 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 非文本：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/workspace_manager/file_preview_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoButton`、`CupertinoAlertDialog`。

无额外显式颜色，继承上表语义。

#### `lib/features/workspace_manager/workspace_manager_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoTextField`、`CupertinoButton`、`CupertinoAlertDialog`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.card` L141 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L144 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.divider` L151 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L158,262,603 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L159,263,604 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L196,245,630 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L197,246 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `statusRedText` L211,445,567 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L218 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0x99000000)` L340 | 复用色；按承载面判级 | #000000 / α=0.600000 | 5.554744 | 5.741836 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L370,395,424,468 | 文字 | #004A94 | 7.818165 | 8.724063 | 2.407135 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L631 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `CupertinoColors.tertiarySystemFill` L653 | 面 | #767680 / α=0.117647 | 1.141332 | 1.150191 | 1.087601 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.label` L659 | 图标/图形 | #000000 | 18.819381 | 21.000000 | 1.000000 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemBlue @ 0.15` L676 | 暗色保留豁免 | #007AFF / α=0.150000 | 1.203594 | 1.215577 | 1.116793 | 暗色保留豁免 |
| `LightSurfaces.selection` L679 | 面 | #E0ECFF | 1.068576 | 1.192393 | 17.611640 | 装饰面豁免；分层强弱见三向值 |
| `statusBlueText` L686 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/workspace_manager/office_document.dart`、`lib/features/workspace_manager/workspace_manager_api.dart`、`lib/features/workspace_manager/workspace_manager_providers.dart`。

### 后续 Git 面板

分组列表、分支树、diff 增删及操作提示存在多套灰阶与状态色。优先次级元数据和 diff 正文对比度，新增白卡描边；状态圆点不能替代文件变更文字语义。影响分支、状态和差异视图，不改 Git 操作。

#### `lib/features/git/git_branch_tree.dart`

默认控件：`CupertinoListSection`、`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.systemBlue` L58 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemTeal` L59 | 复用色；按承载面判级 | #5AC8FA | 1.698980 | 1.895843 | 11.076868 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemPurple` L60 | 复用色；按承载面判级 | #AF52DE | 3.701328 | 4.130204 | 5.084495 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemOrange` L61 | 复用色；按承载面判级 | #FF9500 | 1.970414 | 2.198728 | 9.550978 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemIndigo` L62 | 复用色；按承载面判级 | #5856D6 | 5.062968 | 5.649619 | 3.717065 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemPink` L63 | 复用色；按承载面判级 | #FF2D55 | 3.268088 | 3.646764 | 5.758530 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.card` L89 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L91,284,350 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.divider` L93 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemBlue @ 0.07` L188 | 暗色保留豁免 | #007AFF / α=0.070000 | 1.089269 | 1.094052 | 1.045714 | 暗色保留豁免 |
| `LightSurfaces.selection` L191,258,418 | 面 | #E0ECFF | 1.068576 | 1.192393 | 17.611640 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemBlue` L208,240 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `statusBlueText` L209 | 面 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.separator` L213,349 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.divider` L214 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `statusBlueText` L243,266 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.label` L244 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemBlue @ 0.16` L255 | 暗色保留豁免 | #007AFF / α=0.160000 | 1.218886 | 1.231923 | 1.128448 | 暗色保留豁免 |
| `CupertinoColors.systemGrey5` L278 | 暗色保留豁免 | #E5E5EA | 1.125061 | 1.255423 | 16.727430 | 暗色保留豁免 |
| `LightSurfaces.page` L279,345 | 面 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `secondaryText` L295,304,360,376,389,451 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L296 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L305,361,377,390,431,452,491 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusGreenText` L317 | 文字 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusOrangeText` L326 | 文字 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondarySystemBackground` L343 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `CupertinoColors.systemGreen` L406 | 暗色保留豁免 | #34C759 | 1.989440 | 2.219959 | 9.459636 | 暗色保留豁免 |
| `statusGreenText` L407 | 图标/图形 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemBlue @ 0.12` L415 | 暗色保留豁免 | #007AFF / α=0.120000 | 1.159087 | 1.168124 | 1.085680 | 暗色保留豁免 |
| `CupertinoColors.activeBlue` L429 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `LightSurfaces.userDetail` L432,492 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L467 | 图标/图形 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L475 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.white` L583 | 复用色；按承载面判级 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.white @ 0.8` L594 | 装饰线/投影豁免 | #FFFFFF / α=0.800000 | 1.092065 | 1.000000 | 13.076547 | 装饰线/投影豁免 |

#### `lib/features/git/git_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoListTile`、`CupertinoTextField`、`CupertinoButton`、`CupertinoActionSheet`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.systemRed` L91,723 | 复用色；按承载面判级 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGreen` L92,721 | 复用色；按承载面判级 | #34C759 | 1.989440 | 2.219959 | 9.459636 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L171,223,237,249,530,563,651,671,858 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L172,531,859 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.card` L201,291,329,401 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L203,293,331,403,906 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.divider` L205,295,333,405 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemBlue` L211 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `statusBlueText` L212 | 图标/图形 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L238,672 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.placeholder` L350 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.placeholderText` L351 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.698832 | 1.725396 | 1.121334 | 暗色保留豁免 |
| `LightSurfaces.userDetail` L362,416,427,438,487 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L467,514 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L468,515 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L481 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L575,585 | 文字 | #004A94 | 7.818165 | 8.724063 | 2.407135 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemRed` L685 | 暗色保留豁免 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 暗色保留豁免 |
| `statusRedText` L686 | 图标/图形 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemOrange` L725 | 复用色；按承载面判级 | #FF9500 | 1.970414 | 2.198728 | 9.550978 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGrey` L727 | 复用色；按承载面判级 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGrey2` L729 | 复用色；按承载面判级 | #AEAEB2 | 1.981608 | 2.211219 | 9.497025 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemBlue` L732 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `statusGreenText` L738,905 | 复用色；按承载面判级 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L740,904 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusOrangeText` L742 | 复用色；按承载面判级 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L744 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.placeholder` L746 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusBlueText` L749 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondarySystemBackground` L815 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.page` L816 | 面 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGreen` L843 | 暗色保留豁免 | #34C759 | 1.989440 | 2.219959 | 9.459636 | 暗色保留豁免 |
| `statusGreenText` L844 | 图标/图形 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.tintError` L902 | 复用色；按承载面判级 | #FFF4F3 | 1.035448 | 1.077670 | 19.486486 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.tintGreen` L902 | 复用色；按承载面判级 | #F0FAF2 | 1.044745 | 1.068080 | 19.661457 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/git/git_api.dart`、`lib/features/git/git_providers.dart`。

### 后续 技能

白色分组列表/搜索与灰色摘要，空态图标和说明须分别判级。建议摘要、路径和 placeholder 使用达标次级文字，白卡补轮廓。影响技能列表/详情及搜索。

#### `lib/features/skills/skills_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoSearchTextField`、`CupertinoButton`、`CupertinoAlertDialog`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.card` L98,156 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L100,159 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.placeholder` L104 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L108 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L109 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.page` L150 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGroupedBackground` L151 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.divider` L153 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L197,245,420 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L199,247 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `statusRedText` L213 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L219 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L264,402,437,546 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L265,403,438,547 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.userDetail` L302 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.label` L405,553,585 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.tertiaryLabel` L421 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.698832 | 1.725396 | 1.121334 | 暗色保留豁免 |
| `CupertinoColors.secondarySystemFill` L576 | 面 | #787880 / α=0.156863 | 1.191278 | 1.203984 | 1.129452 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.tertiarySystemFill` L577 | 面 | #767680 / α=0.117647 | 1.141332 | 1.150191 | 1.087601 | 装饰面豁免；分层强弱见三向值 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/skills/skills_api.dart`、`lib/features/skills/skills_providers.dart`。

### 后续 记忆

分组卡、记忆编辑框、覆盖提示、字数和空态共享次级灰。建议可读文字与装饰分隔分开，编辑背景和 placeholder 配套修复。影响记忆列表与编辑表单，不改写入行为。

#### `lib/features/memory/memory_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoTextField`、`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.page` L270 | 面/复用 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGroupedBackground` L271 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.card` L275,674 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L277,676 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.divider` L280 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.textSecondary` L436,484,924 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L438,486 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `statusRedText` L452,695 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L458,724 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L497,756,789 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L498,566,757,790,877,948 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L565,876,947 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.label` L580,891 | 图标/图形 | #000000 | 18.819381 | 21.000000 | 1.000000 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.placeholder` L685 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L713 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.label` L834 | 文字/复用 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey5` L835 | 面/复用 | #E5E5EA | 1.125061 | 1.255423 | 16.727430 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondaryLabel` L925 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/memory/memory_api.dart`、`lib/features/memory/memory_providers.dart`。

### 后续 定时任务

列表和编辑/详情页继承 Cupertino 分组面，副标题及参数提示使用 secondaryText；状态颜色按文字和图标分别核对。建议卡片轮廓、次级文字、输入占位依次落地。影响任务列表/创建/详情。

#### `lib/features/tasks/tasks_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoListTile`、`CupertinoTextField`、`CupertinoButton`、`CupertinoNavigationBar`、`CupertinoAlertDialog`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusGreenText` L59 | 复用色；按承载面判级 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusBlueText` L62,131,946 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusOrangeText` L64,70 | 复用色；按承载面判级 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusGreyText` L66 | 复用色；按承载面判级 | #595959 | 6.277365 | 7.004729 | 2.997975 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L68 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.page` L105,890,892 | 面 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.page` L132,133,179,947,948 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGroupedBackground` L180 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.divider` L181 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.card` L184,988 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L187,991 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.textSecondary` L198,295,547,975 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L238,282,577 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L239,283,578,642 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `statusRedText` L253,405 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L296,548,637,976 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.menuAction` L396,430 | 文字 | #004A94 | 7.818165 | 8.724063 | 2.407135 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.label` L526 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.pressed` L603 | 面 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.page` L625 | 面/复用 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemBackground` L626 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.card` L630 | 面/复用 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.tertiarySystemBackground` L631 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `CupertinoColors.label` L633 | 文字/复用 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L636,641 | 文字/复用 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.divider` L646,895 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L647 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.selection` L951 | 复用色；按承载面判级 | #E0ECFF | 1.068576 | 1.192393 | 17.611640 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.placeholder` L999 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/tasks/tasks_api.dart`、`lib/features/tasks/tasks_providers.dart`。

### 后续 项目选择 Sheet

主要使用标准 Cupertino 列表与输入控件，显式颜色少不代表没有默认 placeholder/按下色。建议随通用 Sheet 令牌迁移；影响项目选择、新建及移动会话入口。

#### `lib/features/projects/project_picker_sheet.dart`

默认控件：`CupertinoTextField`、`CupertinoAlertDialog`、`CupertinoActionSheet`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L38 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L51,84,96,204 | 文字 | #004A94 | 7.818165 | 8.724063 | 2.407135 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.card` L126 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L128 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.placeholder` L137 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L145,153,274 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L214 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L215 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `statusRedText` L284 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/projects/project_providers.dart`。

### 后续 提示词库

收藏列表/编辑 Sheet 的 secondaryLabel、搜索占位和空态需随白卡一起迁移。影响聊天输入栏提示词选择和编辑，不改收藏内容。

#### `lib/features/prompts/widgets/saved_prompts_sheet.dart`

默认控件：`CupertinoListTile`、`CupertinoButton`、`CupertinoAlertDialog`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusRedText` L115,314 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L121,298,325 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.divider` L157,214,405 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.separator` L158,215,406 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.userDetail` L168 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.white` L174 | 图标/图形 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 非文本：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L198,247 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L199,248 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.card` L233 | 复用色；按承载面判级 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.pressed` L234 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `statusRedText` L265 | 图标/图形 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.card` L365 | 面/复用 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey6` L366 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L374 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.systemGrey3` L391 | 面 | #C7C7CC | 1.509207 | 1.684080 | 12.469719 | 装饰面豁免；分层强弱见三向值 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/prompts/prompts_providers.dart`。

### 后续 下载

灰色进度轨道、白卡和多类状态色共存；文件路径/字节进度 secondaryLabel 未达正文 AA。进度轨道属于非文本对照物，按钮白图标需按其真实底色判定。建议先修可读元数据，保留下载状态机。

#### `lib/features/downloads/download_confirm_dialog.dart`

默认控件：`CupertinoAlertDialog`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.menuAction` L66,76 | 文字 | #004A94 | 7.818165 | 8.724063 | 2.407135 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/downloads/download_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoButton`、`CupertinoNavigationBar`、`CupertinoAlertDialog`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.menuAction` L87,97,183,244 | 文字 | #004A94 | 7.818165 | 8.724063 | 2.407135 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey5` L323 | 复用色；按承载面判级 | #E5E5EA | 1.125061 | 1.255423 | 16.727430 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `theme.primaryColor` L325,580,653,704 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.page` L382,386,766 | 面 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGroupedBackground` L383 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.divider` L389 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `Color(0x4D000000)` L392 | 装饰线/投影豁免 | #000000 / α=0.301961 | 2.101806 | 2.120350 | 1.000000 | 装饰线/投影豁免 |
| `LightSurfaces.userDetail` L408 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `theme.primaryColor` L409 | 文字 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L445,640,689,732 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.tertiaryLabel` L446 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.698832 | 1.725396 | 1.121334 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L456 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L457,641,690,733 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `statusGreyText` L495,538 | 复用色；按承载面判级 | #595959 | 6.277365 | 7.004729 | 2.997975 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusBlueText` L517 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusGreenText` L523 | 复用色；按承载面判级 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L526,534 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.pressed` L553 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGrey4` L554 | 暗色保留豁免 | #D1D1D6 | 1.363500 | 1.521490 | 13.802256 | 暗色保留豁免 |
| `CupertinoColors.label` L565,789 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L579,652,703 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.white` L604,670,714 | 文字 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.card` L747 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemGroupedBackground` L748 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L752 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.systemGrey6` L767 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `CupertinoColors.activeBlue` L774 | 图标/图形 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 非文本：页面达 / 白卡达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/downloads/download_controller.dart`、`lib/features/downloads/download_models.dart`、`lib/features/downloads/download_providers.dart`、`lib/features/downloads/download_repository.dart`、`lib/features/downloads/download_save_service.dart`。

### 后续 诊断及详情 Sheet

日志级别、筛选标签、展开箭头、代码/复制区共享灰面，动态级别 tint 叠加透明底。建议逐级别测量真实 tint/background 组合，修时间、来源、正文灰。影响诊断列表及详情，不改日志采集。

#### `lib/features/diagnostics/diagnostics_detail_sheet.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoButton`、`CupertinoNavigationBar`、`CupertinoAlertDialog`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.tintWarning` L14 | 复用色；按承载面判级 | #FFF4E8 | 1.028595 | 1.084850 | 19.357512 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.tintError` L16 | 复用色；按承载面判级 | #FFF4F3 | 1.035448 | 1.077670 | 19.486486 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.selection` L18 | 复用色；按承载面判级 | #E0ECFF | 1.068576 | 1.192393 | 17.611640 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.tintClarification` L20 | 复用色；按承载面判级 | #F3F2FF | 1.007248 | 1.107841 | 18.955790 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.page` L22 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.menuAction` L48,82 | 文字 | #004A94 | 7.818165 | 8.724063 | 2.407135 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.page` L65,67,142 | 面 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.divider` L70 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `Color(0x4D000000)` L73 | 装饰线/投影豁免 | #000000 / α=0.301961 | 2.101806 | 2.120350 | 1.000000 | 装饰线/投影豁免 |
| `LightSurfaces.card` L97,224,260 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemGroupedBackground` L98,225,261 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L102,229,265 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.systemGrey5` L143 | 暗色保留豁免 | #E5E5EA | 1.125061 | 1.255423 | 16.727430 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L154,168,183,212,248 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L155,169,184,213,249 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `statusRedText` L195 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/diagnostics/diagnostics_models.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusGreyText` L54 | 复用色；按承载面判级 | #595959 | 6.277365 | 7.004729 | 2.997975 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `_statusDebugText` L56,68 | 复用色；按承载面判级 | #4A6B82 | 5.063617 | 5.650343 | 3.716588 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusBlueText` L58 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusOrangeText` L60 | 复用色；按承载面判级 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L62 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF4A6B82)` L70 | 文字/复用 | #4A6B82 | 5.063617 | 5.650343 | 3.716588 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF7AA5C2)` L71 | 其他主题定义豁免 | #7AA5C2 | 2.355787 | 2.628754 | 7.988577 | 其他主题定义豁免 |
| `Color(0xFF2C4D64)` L72 | 其他主题定义豁免 | #2C4D64 | 7.999175 | 8.926046 | 2.352665 | 其他主题定义豁免 |
| `Color(0xFF99C2DF)` L73 | 其他主题定义豁免 | #99C2DF | 1.689850 | 1.885654 | 11.136718 | 其他主题定义豁免 |

#### `lib/features/diagnostics/diagnostics_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoListTile`、`CupertinoSearchTextField`、`CupertinoButton`、`CupertinoNavigationBar`、`CupertinoAlertDialog`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.tintWarning` L19 | 复用色；按承载面判级 | #FFF4E8 | 1.028595 | 1.084850 | 19.357512 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.tintError` L21 | 复用色；按承载面判级 | #FFF4F3 | 1.035448 | 1.077670 | 19.486486 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.selection` L23 | 复用色；按承载面判级 | #E0ECFF | 1.068576 | 1.192393 | 17.611640 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.tintClarification` L25 | 复用色；按承载面判级 | #F3F2FF | 1.007248 | 1.107841 | 18.955790 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.page` L27 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFFB3001B)` L116 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L126,152,211,227,516 | 文字 | #004A94 | 7.818165 | 8.724063 | 2.407135 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.page` L183,185,242,853 | 面 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.divider` L188,484,789 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `Color(0x4D000000)` L191 | 装饰线/投影豁免 | #000000 / α=0.301961 | 2.101806 | 2.120350 | 1.000000 | 装饰线/投影豁免 |
| `CupertinoColors.systemGroupedBackground` L243 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.divider` L245 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.card` L248,300,477 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L251,303,559,618 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.textSecondary` L267,378,684,702,718,865,878,891 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L268,379,685,703,719,866,879,892 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.placeholder` L309 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L313 | 面 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondaryLabel` L314 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.userDetail` L400,432 | 图标/图形 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L409,441 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondarySystemGroupedBackground` L478 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `CupertinoColors.separator` L485,790 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.userDetail` L527 | 面 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.page` L556,615 | 面/复用 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey6` L557,616 | 面/复用 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey4` L560,619 | 装饰线/投影豁免 | #D1D1D6 | 1.363500 | 1.521490 | 13.802256 | 装饰线/投影豁免 |
| `LightSurfaces.textSecondary` L562,621 | 文字/复用 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L563,622 | 文字/复用 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `statusBlueText` L613 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.selection` L633,780 | 面 | #E0ECFF | 1.068576 | 1.192393 | 17.611640 | 装饰面豁免；分层强弱见三向值 |
| `activeColor @ 0.15` L634 | 面 | #005FB8 / α=0.150000 | 1.248206 | 1.258718 | 1.080556 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.textSecondary` L674,809,928 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF8E8E93)` L675,810 | 图标/图形 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 非文本：页面不达 / 白卡达；反色见局部组合 |
| `statusBlueText @ 0.1` L781 | 面 | #005FB8 / α=0.100000 | 1.157261 | 1.163506 | 1.050244 | 装饰面豁免；分层强弱见三向值 |
| `statusBlueText` L807 | 图标/图形 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey5` L854 | 暗色保留豁免 | #E5E5EA | 1.125061 | 1.255423 | 16.727430 | 暗色保留豁免 |
| `statusRedText` L904 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFFC7C7CC)` L929 | 图标/图形 | #C7C7CC | 1.509207 | 1.684080 | 12.469719 | 非文本：页面不达 / 白卡不达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/diagnostics/diagnostics_interceptor.dart`、`lib/features/diagnostics/diagnostics_providers.dart`、`lib/features/diagnostics/diagnostics_service.dart`。

### 后续 通知浮条与后台保活设置

应用内通知白卡、次级消息和关闭图标需迁移；系统通知平台外观不属于 lib 静态页面面色。保活说明/错误状态仍按正文核对。影响 in-app 通知及保活设置，系统通知发送不动。

#### `lib/features/notifications/background_keepalive_settings_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoListTile`、`CupertinoNavigationBar`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.page` L25,27 | 面 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.divider` L30 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `Color(0x4D000000)` L33 | 装饰线/投影豁免 | #000000 / α=0.301961 | 2.101806 | 2.120350 | 1.000000 | 装饰线/投影豁免 |
| `LightSurfaces.textSecondary` L55 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF8E8E93)` L56 | 复用色；按承载面判级 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.page` L65,147 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGroupedBackground` L66,148 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.card` L70,152 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L72,154 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.divider` L77,159 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L83,94,128,165,196 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L110 | 图标/图形 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L115,119 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusGreenText` L134 | 图标/图形 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF34C759)` L135 | 图标/图形 | #34C759 | 1.989440 | 2.219959 | 9.459636 | 非文本：页面不达 / 白卡不达；反色见局部组合 |
| `statusOrangeText` L183 | 图标/图形 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `statusOrangeText` L189 | 文字 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/notifications/notification_lifecycle_observer.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusGreenText` L154 | 复用色；按承载面判级 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemIndigo` L157 | 复用色；按承载面判级 | #5856D6 | 5.062968 | 5.649619 | 3.717065 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L160 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.card` L168 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemGroupedBackground` L169 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L173 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.systemGrey @ 0.25` L178 | 装饰线/投影豁免 | #8E8E93 / α=0.250000 | 1.260485 | 1.285296 | 1.345967 | 装饰线/投影豁免 |
| `CupertinoColors.label` L203 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L216 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L217 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L235 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF8E8E93)` L236 | 图标/图形 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 非文本：页面不达 / 白卡达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/notifications/background_keepalive_service.dart`、`lib/features/notifications/notification_providers.dart`、`lib/features/notifications/turn_notification_service.dart`。

### 共享组件

AppBackButton / app_navigation 无独立颜色常量；返回图标与 NarrowNavigationDropdownButton 的继承动作色已由 P1 widget 测试按实际背景验证，导航逻辑不改。

#### `lib/features/shared/app_back_button.dart`

默认控件：`CupertinoButton`。

无额外显式颜色，继承上表语义。

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/shared/app_navigation.dart`。

### 桌面能力

本目录是窗口、托盘、快捷键及启动服务，没有 Flutter 页面面色；桌面设置的 UI 在 settings 中审计，托盘操作系统主题不由这里的 Dart Color 控制。

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/desktop/desktop_lifecycle_observer.dart`、`lib/features/desktop/desktop_settings.dart`、`lib/features/desktop/desktop_shortcuts.dart`、`lib/features/desktop/startup_registrar.dart`、`lib/features/desktop/tray_manager_service.dart`、`lib/features/desktop/window_memory.dart`、`lib/features/desktop/window_title_service.dart`。

### 内置服务

配置、状态模型、Provider 与服务，无独立 Flutter 面色；可见设置区在 settings/webui_sidecar_section.dart，引导入口在 onboarding/widgets/builtin_tab.dart。

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/webui_sidecar/webui_sidecar_config.dart`、`lib/features/webui_sidecar/webui_sidecar_models.dart`、`lib/features/webui_sidecar/webui_sidecar_providers.dart`、`lib/features/webui_sidecar/webui_sidecar_service.dart`。

### 阶段一 会话列表

主列表、紧凑侧栏复用区、搜索框、菜单图标、副标题、选中/按下态、筛选弹层、批量栏和 FAB 工作区浮层按浅色令牌接入。session_list_header 不改源码，由页面局部 bar/page 主题消费；scheduled_session_disclosure 是弃用兼容组件，仍同步修正计数和标题。下面暗色原值/反色 tooltip 另有明确豁免，业务状态与分组逻辑不改。

#### `lib/features/session_list/scheduled_session_disclosure.dart`

默认控件：`CupertinoListSection`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L63 | 文字/复用 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L64 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.card` L98,149 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey5` L99 | 暗色保留豁免 | #E5E5EA | 1.125061 | 1.255423 | 16.727430 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L105,151 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.page` L143 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGroupedBackground` L144 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.divider` L146 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

#### `lib/features/session_list/session_list_header.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.label` L157 | 文字/复用 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/session_list/session_list_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoSearchTextField`、`CupertinoButton`、`CupertinoAlertDialog`、`CupertinoActionSheet`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.page` L131 | 面 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.page` L235,236 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.card` L276,394,540 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L278,547 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.placeholder` L282 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L286 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L287 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `CupertinoColors.systemBackground` L395 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `LightSurfaces.divider` L401 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L402,604 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `statusRedText` L450,673,1152,1299 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemRed` L451 | 暗色保留豁免 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 暗色保留豁免 |
| `CupertinoColors.secondarySystemGroupedBackground` L541 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `LightSurfaces.divider` L603 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.textSecondary` L631,726 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L632,727 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L656,706 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF8E8E93)` L659,709 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |

#### `lib/features/session_list/session_list_utility_rows.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.card` L138 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemGroupedBackground` L139 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L143 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.activeBlue` L181 | 图标/图形 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.label` L189 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/session_list/session_auto_refresh.dart`、`lib/features/session_list/session_entry_visibility.dart`、`lib/features/session_list/session_list_providers.dart`、`lib/features/session_list/session_row_subtitle_settings.dart`。

### 共用主题与语义令牌

全局主题保持原样，仅新建 LightSurfaces opt-in 层。旧 status_colors 注释不作数字来源：以源码 ARGB 实算。状态色在白卡达标不代表叠加任意彩色面也达标；secondaryText 的 alpha 必须先合成。

#### `lib/app/theme/cupertino_theme.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `Color(0xFF000000)` L14 | 暗色保留豁免 | #000000 | 18.819381 | 21.000000 | 1.000000 | 暗色保留豁免 |
| `CupertinoColors.systemGroupedBackground` L15 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFF007AFF)` L18 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.label` L31,61,69,76 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF007AFF)` L38,53 | 文字 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.inactiveGray` L46 | 文字 | #999999 | 2.553188 | 2.849028 | 7.370936 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

#### `lib/app/theme/light_surfaces.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `Color(0xFFF2F2F7)` L28 | 面/复用 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `Color(0xFFFFFFFF)` L31 | 面/复用 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `Color(0xFFCCD0DA)` L34 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `Color(0xFF6A6A6F)` L41 | 文字/复用 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFFE0ECFF)` L47 | 面/复用 | #E0ECFF | 1.068576 | 1.192393 | 17.611640 | 装饰面豁免；分层强弱见三向值 |
| `Color(0xFFF0FAF2)` L53 | 复用色；按承载面判级 | #F0FAF2 | 1.044745 | 1.068080 | 19.661457 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFFFFF4E8)` L56 | 复用色；按承载面判级 | #FFF4E8 | 1.028595 | 1.084850 | 19.357512 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFFFFF4F3)` L59 | 复用色；按承载面判级 | #FFF4F3 | 1.035448 | 1.077670 | 19.486486 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFFF3F2FF)` L62 | 复用色；按承载面判级 | #F3F2FF | 1.007248 | 1.107841 | 18.955790 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFF005FB8)` L66 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF004A94)` L70 | 复用色；按承载面判级 | #004A94 | 7.818165 | 8.724063 | 2.407135 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/app/theme/status_colors.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusGreenText` L16 | 复用色；按承载面判级 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF1E7A34)` L18 | 文字/复用 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF34C759)` L19 | 其他主题定义豁免 | #34C759 | 1.989440 | 2.219959 | 9.459636 | 其他主题定义豁免 |
| `Color(0xFF0E6B2C)` L20 | 其他主题定义豁免 | #0E6B2C | 5.959045 | 6.649525 | 3.158120 | 其他主题定义豁免 |
| `Color(0xFF40DD74)` L21 | 其他主题定义豁免 | #40DD74 | 1.593139 | 1.777737 | 11.812769 | 其他主题定义豁免 |
| `statusOrangeText` L25 | 复用色；按承载面判级 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFFB25000)` L27 | 文字/复用 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFFFF9500)` L28 | 其他主题定义豁免 | #FF9500 | 1.970414 | 2.198728 | 9.550978 | 其他主题定义豁免 |
| `Color(0xFF9A3F00)` L29 | 其他主题定义豁免 | #9A3F00 | 6.100271 | 6.807114 | 3.085008 | 其他主题定义豁免 |
| `Color(0xFFFFB340)` L30 | 其他主题定义豁免 | #FFB340 | 1.598375 | 1.783580 | 11.774073 | 其他主题定义豁免 |
| `statusBlueText` L34 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF005FB8)` L36 | 文字/复用 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF0A84FF)` L37 | 其他主题定义豁免 | #0A84FF | 3.268723 | 3.647472 | 5.757412 | 其他主题定义豁免 |
| `Color(0xFF004A94)` L38 | 其他主题定义豁免 | #004A94 | 7.818165 | 8.724063 | 2.407135 | 其他主题定义豁免 |
| `Color(0xFF45A3FF)` L39 | 其他主题定义豁免 | #45A3FF | 2.371418 | 2.646196 | 7.935919 | 其他主题定义豁免 |
| `statusGreyText` L43 | 复用色；按承载面判级 | #595959 | 6.277365 | 7.004729 | 2.997975 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF595959)` L45 | 文字/复用 | #595959 | 6.277365 | 7.004729 | 2.997975 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF8E8E93)` L46 | 其他主题定义豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 其他主题定义豁免 |
| `Color(0xFF3E3E44)` L47 | 其他主题定义豁免 | #3E3E44 | 9.517489 | 10.620289 | 1.977347 | 其他主题定义豁免 |
| `Color(0xFFAEAEB6)` L48 | 其他主题定义豁免 | #AEAEB6 | 1.974827 | 2.203652 | 9.529635 | 其他主题定义豁免 |
| `statusTealText` L52 | 复用色；按承载面判级 | #0E7C86 | 4.432283 | 4.945856 | 4.245979 | 正文 AA：页面不达 / 白卡达；反色见局部组合 |
| `Color(0xFF0E7C86)` L54 | 文字/复用 | #0E7C86 | 4.432283 | 4.945856 | 4.245979 | 正文 AA：页面不达 / 白卡达；反色见局部组合 |
| `Color(0xFF30B0C7)` L55 | 其他主题定义豁免 | #30B0C7 | 2.306152 | 2.573367 | 8.160514 | 其他主题定义豁免 |
| `Color(0xFF0A6169)` L56 | 其他主题定义豁免 | #0A6169 | 6.430090 | 7.175151 | 2.926768 | 其他主题定义豁免 |
| `Color(0xFF40C4D6)` L57 | 其他主题定义豁免 | #40C4D6 | 1.866081 | 2.082305 | 10.084977 | 其他主题定义豁免 |
| `statusRedText` L64 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFFB3001B)` L66 | 文字/复用 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFFFF453A)` L67 | 其他主题定义豁免 | #FF453A | 3.052940 | 3.406687 | 6.164346 | 其他主题定义豁免 |
| `Color(0xFF8F0018)` L68 | 其他主题定义豁免 | #8F0018 | 8.628321 | 9.628092 | 2.181118 | 其他主题定义豁免 |
| `Color(0xFFFF6961)` L69 | 其他主题定义豁免 | #FF6961 | 2.527705 | 2.820593 | 7.445244 | 其他主题定义豁免 |
| `secondaryText` L77 | 复用色；按承载面判级 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color.fromARGB(0x99,0x3C,0x3C,0x43)` L79 | 文字/复用 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color.fromARGB(0x99,0xEB,0xEB,0xF5)` L80 | 其他主题定义豁免 | #EBEBF5 / α=0.600000 | 1.036118 | 1.105316 | 6.363811 | 其他主题定义豁免 |
| `Color.fromARGB(0xAA,0x3C,0x3C,0x43)` L81 | 其他主题定义豁免 | #3C3C43 / α=0.666667 | 3.893599 | 4.096766 | 1.431121 | 其他主题定义豁免 |
| `Color.fromARGB(0xAD,0xEB,0xEB,0xF5)` L82 | 其他主题定义豁免 | #EBEBF5 / α=0.678431 | 1.040970 | 1.120194 | 8.024222 | 其他主题定义豁免 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/app/theme/theme_provider.dart`。

### 本地化

语言 Provider/Resolver，无颜色或可视页面；不改文案。

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/app/locale/locale_provider.dart`、`lib/app/locale/locale_resolver.dart`。

### 应用壳接线

CupertinoApp 使用 buildCupertinoTheme；Material 桥接在 main.dart，不是本轮功能页改造范围。这里只读审计，保留路由/本地化/启动逻辑。

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/app/app.dart`、`lib/app/deep_link.dart`、`lib/app/router.dart`。

### 启动与 Material 桥接

Material 桥接把 Cupertino 的面和语义色传给依赖组件；错误页/详情使用红色文字与反色按钮。属于允许的壳桥接例外，不据此向业务 UI 引入 Material。

#### `lib/main.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.secondarySystemGroupedBackground` L112 | 面/复用 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.tertiarySystemGroupedBackground` L114 | 面/复用 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.label` L115 | 文字/复用 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L117 | 文字/复用 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemRed` L118 | 复用色；按承载面判级 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.activeBlue` L119 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGreen` L120 | 复用色；按承载面判级 | #34C759 | 1.989440 | 2.219959 | 9.459636 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.separator` L121 | 装饰线/投影豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 装饰线/投影豁免 |
| `redColor @ 0.35` L133 | 装饰线/投影豁免 | #FF3B30 / α=0.350000 | 1.576119 | 1.616708 | 1.539928 | 装饰线/投影豁免 |
| `CupertinoColors.white` L211 | 文字 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `separatorColor @ 0.4` L226 | 装饰线/投影豁免 | #3C3C43 / α=0.400000 | 2.090916 | 2.139428 | 1.185133 | 装饰线/投影豁免 |

### 核心层

模型/API/缓存不渲染 UI。accessibility.dart 的 AccessibleButton 复用 CupertinoButton 颜色；数据解析中的整数不是颜色。

#### `lib/core/update/apk_installer.dart`

默认控件：`CupertinoAlertDialog`。

无额外显式颜色，继承上表语义。

#### `lib/core/update/update_providers.dart`

默认控件：`CupertinoAlertDialog`。

无额外显式颜色，继承上表语义。

#### `lib/core/utils/accessibility.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.quaternarySystemFill` L17,30 | 复用色；按承载面判级 | #747480 / α=0.078431 | 1.092772 | 1.098258 | 1.055643 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/core/api/api_client.dart`、`lib/core/api/api_client_chat.dart`、`lib/core/api/api_client_cron.dart`、`lib/core/api/api_client_extensions.dart`、`lib/core/api/api_client_git.dart`、`lib/core/api/api_client_kanban.dart`、`lib/core/api/api_client_mcp.dart`、`lib/core/api/api_client_memory_skills.dart`、`lib/core/api/api_client_prompts.dart`、`lib/core/api/api_client_server_panels.dart`、`lib/core/api/api_client_sessions.dart`、`lib/core/api/api_client_upload.dart`、`lib/core/api/api_client_workspace.dart`、`lib/core/api/api_exception.dart`、`lib/core/api/cookie_store.dart`、`lib/core/api/custom_header.dart`、`lib/core/api/endpoints.dart`、`lib/core/api/sse_client.dart`、`lib/core/api/ws_client.dart`、`lib/core/cache/app_database.dart`、`lib/core/cache/app_database.g.dart`、`lib/core/cache/app_database_connection.dart`、`lib/core/cache/app_database_connection_native.dart`、`lib/core/cache/app_database_connection_web.dart`、`lib/core/cache/cache_providers.dart`、`lib/core/cache/cache_service.dart`、`lib/core/cache/media_cache_service.dart`、`lib/core/connections/connection_providers.dart`、`lib/core/connections/connection_store.dart`、`lib/core/connections/server_connection.dart`、`lib/core/install/install_detector.dart`、`lib/core/install/llm_onboarding.dart`、`lib/core/install/powershell_installer.dart`、`lib/core/install/webui_bootstrap.dart`、`lib/core/models/approval.dart`、`lib/core/models/auxiliary_model.dart`、`lib/core/models/chat_message.dart`、`lib/core/models/clarification.dart`、`lib/core/models/context_window_snapshot.dart`、`lib/core/models/cron.dart`、`lib/core/models/extensions.dart`、`lib/core/models/git_workspace.dart`、`lib/core/models/goal.dart`、`lib/core/models/insights.dart`、`lib/core/models/json_value.dart`、`lib/core/models/kanban.dart`、`lib/core/models/mcp.dart`、`lib/core/models/memory.dart`、`lib/core/models/message_attachment.dart`、`lib/core/models/model_favorite.dart`、`lib/core/models/saved_prompt.dart`、`lib/core/models/server_account.dart`、`lib/core/models/server_catalog.dart`、`lib/core/models/server_info.dart`、`lib/core/models/session.dart`、`lib/core/models/skills.dart`、`lib/core/models/slash_skill_formatter.dart`、`lib/core/models/system_health.dart`、`lib/core/models/tool_call.dart`、`lib/core/models/transcribe_response.dart`、`lib/core/models/turn_file_change.dart`、`lib/core/models/upload_response.dart`、`lib/core/models/workspace.dart`、`lib/core/providers/clipboard_paste_provider.dart`、`lib/core/providers/file_picker_provider.dart`、`lib/core/update/github_release.dart`、`lib/core/update/update_checker_service.dart`、`lib/core/update/version_info.dart`、`lib/core/utils/attachment_audio_detection.dart`、`lib/core/utils/clipboard_paste.dart`、`lib/core/utils/context_window_formatter.dart`、`lib/core/utils/equality.dart`、`lib/core/utils/file_picker.dart`、`lib/core/utils/injected_message.dart`、`lib/core/utils/lossy_json.dart`、`lib/core/utils/safe_clipboard.dart`、`lib/core/utils/selected_context.dart`、`lib/core/utils/uuid.dart`、`lib/driver_main.dart`、`lib/l10n/app_localizations.dart`。

## 附录：脚本实算输出

以下表与上文逐页数字全部由同一脚本输出，正文不手填比值。执行默认命令输出本报告全文，`--check-report` 会进行全文比对。

### A. 浅色令牌三向矩阵

| token | 不透明 RGB | 对 page | 对 card | 对 textSecondary |
|---|---|---:|---:|---:|
| page | #F2F2F7 | 1.000000 | 1.115871 | 4.820554 |
| card | #FFFFFF | 1.115871 | 1.000000 | 5.379116 |
| cardBorder | #CCD0DA | 1.383553 | 1.543866 | 3.484185 |
| divider | #CCD0DA | 1.383553 | 1.543866 | 3.484185 |
| textSecondary | #6A6A6F | 4.820554 | 5.379116 | 1.000000 |
| selection | #E0ECFF | 1.068576 | 1.192393 | 4.511193 |
| pressed | #F2F2F7 | 1.000000 | 1.115871 | 4.820554 |
| placeholder | #6A6A6F | 4.820554 | 5.379116 | 1.000000 |
| tintGreen | #F0FAF2 | 1.044745 | 1.068080 | 5.036250 |
| tintWarning | #FFF4E8 | 1.028595 | 1.084850 | 4.958395 |
| tintError | #FFF4F3 | 1.035448 | 1.077670 | 4.991432 |
| tintClarification | #F3F2FF | 1.007248 | 1.107841 | 4.855495 |
| userDetail | #005FB8 | 5.653126 | 6.308159 | 1.172713 |

### B. 实际局部组合与通用语义色

“面/旧页面”用于看层级；“字/旧页面”用于复核上下文；AA 按“字/实际面”判级。RGB 展示为最接近整字节，计算仍使用未经取整的 alpha 合成结果。

| 组合 / 来源 | 前景 | 实际承载面 | 面/旧页面 | 字/旧页面 | 字/实际面 | 判级 |
|---|---|---|---:|---:|---:|---|
| 旧页面/label · `Flutter colors.dart + 默认控件` | #000000 | #F2F2F7 | 1.000000 | 18.819381 | 18.819381 | 正文 AA 达 |
| 旧页面/secondaryLabel · `Flutter colors.dart + 默认控件` | #3C3C43 / α=0.600000 | #F2F2F7 | 1.000000 | 3.295321 | 3.295321 | 正文 AA 不达标 |
| 旧页面/tertiaryLabel · `Flutter colors.dart + 默认控件` | #3C3C43 / α=0.298039 | #F2F2F7 | 1.000000 | 1.698832 | 1.698832 | 正文 AA 不达标 |
| 旧页面/placeholderText · `Flutter colors.dart + 默认控件` | #3C3C43 / α=0.298039 | #F2F2F7 | 1.000000 | 1.698832 | 1.698832 | 正文 AA 不达标 |
| 旧页面/systemGrey · `Flutter colors.dart + 默认控件` | #8E8E93 | #F2F2F7 | 1.000000 | 2.921958 | 2.921958 | 正文 AA 不达标 |
| 旧页面/activeBlue · `Flutter colors.dart + 默认控件` | #007AFF | #F2F2F7 | 1.000000 | 3.599857 | 3.599857 | 正文 AA 不达标 |
| 白卡/label · `Flutter colors.dart + 默认控件` | #000000 | #FFFFFF | 1.115871 | 18.819381 | 21.000000 | 正文 AA 达 |
| 白卡/secondaryLabel · `Flutter colors.dart + 默认控件` | #3C3C43 / α=0.600000 | #FFFFFF | 1.115871 | 3.295321 | 3.438200 | 正文 AA 不达标 |
| 白卡/tertiaryLabel · `Flutter colors.dart + 默认控件` | #3C3C43 / α=0.298039 | #FFFFFF | 1.115871 | 1.698832 | 1.725396 | 正文 AA 不达标 |
| 白卡/placeholderText · `Flutter colors.dart + 默认控件` | #3C3C43 / α=0.298039 | #FFFFFF | 1.115871 | 1.698832 | 1.725396 | 正文 AA 不达标 |
| 白卡/systemGrey · `Flutter colors.dart + 默认控件` | #8E8E93 | #FFFFFF | 1.115871 | 2.921958 | 3.260528 | 正文 AA 不达标 |
| 白卡/activeBlue · `Flutter colors.dart + 默认控件` | #007AFF | #FFFFFF | 1.115871 | 3.599857 | 4.016976 | 正文 AA 不达标 |
| 新页面/label · `Flutter colors.dart + 默认控件` | #000000 | #F2F2F7 | 1.000000 | 18.819381 | 18.819381 | 正文 AA 达 |
| 新页面/secondaryLabel · `Flutter colors.dart + 默认控件` | #3C3C43 / α=0.600000 | #F2F2F7 | 1.000000 | 3.295321 | 3.295321 | 正文 AA 不达标 |
| 新页面/tertiaryLabel · `Flutter colors.dart + 默认控件` | #3C3C43 / α=0.298039 | #F2F2F7 | 1.000000 | 1.698832 | 1.698832 | 正文 AA 不达标 |
| 新页面/placeholderText · `Flutter colors.dart + 默认控件` | #3C3C43 / α=0.298039 | #F2F2F7 | 1.000000 | 1.698832 | 1.698832 | 正文 AA 不达标 |
| 新页面/systemGrey · `Flutter colors.dart + 默认控件` | #8E8E93 | #F2F2F7 | 1.000000 | 2.921958 | 2.921958 | 正文 AA 不达标 |
| 新页面/activeBlue · `Flutter colors.dart + 默认控件` | #007AFF | #F2F2F7 | 1.000000 | 3.599857 | 3.599857 | 正文 AA 不达标 |
| statusGreenText/页面 · `status_colors.dart / diagnostics_models.dart` | #1E7A34 | #F2F2F7 | 1.000000 | 4.839624 | 4.839624 | 正文 AA 达 |
| statusGreenText/白卡 · `status_colors.dart / diagnostics_models.dart` | #1E7A34 | #FFFFFF | 1.115871 | 4.839624 | 5.400396 | 正文 AA 达 |
| statusOrangeText/页面 · `status_colors.dart / diagnostics_models.dart` | #B25000 | #F2F2F7 | 1.000000 | 4.657733 | 4.657733 | 正文 AA 达 |
| statusOrangeText/白卡 · `status_colors.dart / diagnostics_models.dart` | #B25000 | #FFFFFF | 1.115871 | 4.657733 | 5.197428 | 正文 AA 达 |
| statusBlueText/页面 · `status_colors.dart / diagnostics_models.dart` | #005FB8 | #F2F2F7 | 1.000000 | 5.653126 | 5.653126 | 正文 AA 达 |
| statusBlueText/白卡 · `status_colors.dart / diagnostics_models.dart` | #005FB8 | #FFFFFF | 1.115871 | 5.653126 | 6.308159 | 正文 AA 达 |
| statusGreyText/页面 · `status_colors.dart / diagnostics_models.dart` | #595959 | #F2F2F7 | 1.000000 | 6.277365 | 6.277365 | 正文 AA 达 |
| statusGreyText/白卡 · `status_colors.dart / diagnostics_models.dart` | #595959 | #FFFFFF | 1.115871 | 6.277365 | 7.004729 | 正文 AA 达 |
| statusTealText/页面 · `status_colors.dart / diagnostics_models.dart` | #0E7C86 | #F2F2F7 | 1.000000 | 4.432283 | 4.432283 | 正文 AA 不达标 |
| statusTealText/白卡 · `status_colors.dart / diagnostics_models.dart` | #0E7C86 | #FFFFFF | 1.115871 | 4.432283 | 4.945856 | 正文 AA 达 |
| statusRedText/页面 · `status_colors.dart / diagnostics_models.dart` | #B3001B | #F2F2F7 | 1.000000 | 6.417374 | 6.417374 | 正文 AA 达 |
| statusRedText/白卡 · `status_colors.dart / diagnostics_models.dart` | #B3001B | #FFFFFF | 1.115871 | 6.417374 | 7.160960 | 正文 AA 达 |
| secondaryText/页面 · `status_colors.dart / diagnostics_models.dart` | #3C3C43 / α=0.600000 | #F2F2F7 | 1.000000 | 3.295321 | 3.295321 | 正文 AA 不达标 |
| secondaryText/白卡 · `status_colors.dart / diagnostics_models.dart` | #3C3C43 / α=0.600000 | #FFFFFF | 1.115871 | 3.295321 | 3.438200 | 正文 AA 不达标 |
| _statusDebugText/页面 · `status_colors.dart / diagnostics_models.dart` | #4A6B82 | #F2F2F7 | 1.000000 | 5.063617 | 5.063617 | 正文 AA 达 |
| _statusDebugText/白卡 · `status_colors.dart / diagnostics_models.dart` | #4A6B82 | #FFFFFF | 1.115871 | 5.063617 | 5.650343 | 正文 AA 达 |
| 聊天用户气泡/正文 · `chat/widgets/message_bubble.dart + markdown_styles.dart` | #FFFFFF | #007AFF | 3.599857 | 1.115871 | 4.016976 | 正文 AA 不达标；Leader 指定保留主气泡 |
| 旧方案参考/用户白色代码或引用底 α=0.22 · `chat/widgets/markdown_styles.dart` | #FFFFFF | #3897FF | 2.667098 | 1.115871 | 2.976137 | 正文 AA 不达标 |
| 旧方案参考/用户白色代码或引用底 α=0.15 · `chat/widgets/markdown_styles.dart` | #FFFFFF | #268EFF | 2.943475 | 1.115871 | 3.284538 | 正文 AA 不达标 |
| 旧方案参考/用户白色代码或引用底 α=0.12 · `chat/widgets/markdown_styles.dart` | #FFFFFF | #1F8AFF | 3.067982 | 1.115871 | 3.423472 | 正文 AA 不达标 |
| 非聊天共享默认/assistant 代码引用 · `chat/widgets/markdown_styles.dart` | #000000 | #E5E5EA | 1.125061 | 18.819381 | 16.727430 | 正文 AA 达 |
| 绿色提示卡/正文 · `chat/chat_page.dart bgColor` | #000000 | #F0FAF2 | 1.044745 | 18.819381 | 19.661457 | 正文 AA 达 |
| 绿色提示卡/装饰勾 · `chat/chat_page.dart：已有文字重复语义` | #1E7A34 | #F0FAF2 | 1.044745 | 4.839624 | 5.056174 | 装饰豁免 |
| 绿色提示卡/灰色关闭图标 · `chat/chat_page.dart` | #6A6A6F | #F0FAF2 | 1.044745 | 4.820554 | 5.036250 | 非文本 达 |
| 旧方案参考/聊天提示条/systemBlue · `chat/chat_page.dart` | #007AFF | #DAE6F8 | 1.130522 | 3.599857 | 3.184243 | 正文 AA 不达标 |
| 旧方案参考/聊天提示条/systemRed · `chat/chat_page.dart` | #FF3B30 | #F3E0E3 | 1.136301 | 3.178807 | 2.797505 | 正文 AA 不达标 |
| 旧方案参考/聊天提示条/systemIndigo · `chat/chat_page.dart` | #5856D6 | #E0DFF3 | 1.173728 | 5.062968 | 4.313580 | 正文 AA 不达标 |
| P0/textSecondary/page · `chat_page + chat/widgets: metadata, fields, cards, menu selections` | #6A6A6F | #F2F2F7 | 1.000000 | 4.820554 | 4.820554 | 正文 AA 达 |
| P0/cardBorder/page · `chat cards/fields: 0.5-1 logical pixel hairline` | #CCD0DA | #F2F2F7 | 1.000000 | 1.383553 | 1.383553 | 装饰豁免 |
| P0/textSecondary/card · `chat_page + chat/widgets: metadata, fields, cards, menu selections` | #6A6A6F | #FFFFFF | 1.115871 | 4.820554 | 5.379116 | 正文 AA 达 |
| P0/cardBorder/card · `chat cards/fields: 0.5-1 logical pixel hairline` | #CCD0DA | #FFFFFF | 1.115871 | 1.383553 | 1.543866 | 装饰豁免 |
| P0/textSecondary/selection · `chat_page + chat/widgets: metadata, fields, cards, menu selections` | #6A6A6F | #E0ECFF | 1.068576 | 4.820554 | 4.511193 | 正文 AA 达 |
| P0/cardBorder/selection · `chat cards/fields: 0.5-1 logical pixel hairline` | #CCD0DA | #E0ECFF | 1.068576 | 1.383553 | 1.294763 | 装饰豁免 |
| P0/textSecondary/pressed · `chat_page + chat/widgets: metadata, fields, cards, menu selections` | #6A6A6F | #F2F2F7 | 1.000000 | 4.820554 | 4.820554 | 正文 AA 达 |
| P0/cardBorder/pressed · `chat cards/fields: 0.5-1 logical pixel hairline` | #CCD0DA | #F2F2F7 | 1.000000 | 1.383553 | 1.383553 | 装饰豁免 |
| P0/textSecondary/tintGreen · `chat_page + chat/widgets: metadata, fields, cards, menu selections` | #6A6A6F | #F0FAF2 | 1.044745 | 4.820554 | 5.036250 | 正文 AA 达 |
| P0/cardBorder/tintGreen · `chat cards/fields: 0.5-1 logical pixel hairline` | #CCD0DA | #F0FAF2 | 1.044745 | 1.383553 | 1.445460 | 装饰豁免 |
| P0/textSecondary/tintWarning · `chat_page + chat/widgets: metadata, fields, cards, menu selections` | #6A6A6F | #FFF4E8 | 1.028595 | 4.820554 | 4.958395 | 正文 AA 达 |
| P0/cardBorder/tintWarning · `chat cards/fields: 0.5-1 logical pixel hairline` | #CCD0DA | #FFF4E8 | 1.028595 | 1.383553 | 1.423115 | 装饰豁免 |
| P0/textSecondary/tintError · `chat_page + chat/widgets: metadata, fields, cards, menu selections` | #6A6A6F | #FFF4F3 | 1.035448 | 4.820554 | 4.991432 | 正文 AA 达 |
| P0/cardBorder/tintError · `chat cards/fields: 0.5-1 logical pixel hairline` | #CCD0DA | #FFF4F3 | 1.035448 | 1.383553 | 1.432597 | 装饰豁免 |
| P0/textSecondary/tintClarification · `chat_page + chat/widgets: metadata, fields, cards, menu selections` | #6A6A6F | #F3F2FF | 1.007248 | 4.820554 | 4.855495 | 正文 AA 达 |
| P0/cardBorder/tintClarification · `chat cards/fields: 0.5-1 logical pixel hairline` | #CCD0DA | #F3F2FF | 1.007248 | 1.383553 | 1.393581 | 装饰豁免 |
| P0/user detail/inline code · `chat/widgets/markdown_styles.dart + chat_media_view.dart` | #FFFFFF | #005FB8 | 5.653126 | 1.115871 | 6.308159 | 正文 AA 达 |
| P0/user detail/code block · `chat/widgets/markdown_styles.dart + chat_media_view.dart` | #FFFFFF | #005FB8 | 5.653126 | 1.115871 | 6.308159 | 正文 AA 达 |
| P0/user detail/link · `chat/widgets/markdown_styles.dart + chat_media_view.dart` | #FFFFFF | #005FB8 | 5.653126 | 1.115871 | 6.308159 | 正文 AA 达 |
| P0/user detail/attachment · `chat/widgets/markdown_styles.dart + chat_media_view.dart` | #FFFFFF | #005FB8 | 5.653126 | 1.115871 | 6.308159 | 正文 AA 达 |
| P0/user detail/blockquote · `chat/widgets/markdown_styles.dart + chat_media_view.dart` | #FFFFFF | #005FB8 | 5.653126 | 1.115871 | 6.308159 | 正文 AA 达 |
| P0/approval + queued warning · `chat_page + chat/widgets: light-only status colors` | #B25000 | #FFF4E8 | 1.028595 | 4.657733 | 4.790918 | 正文 AA 达 |
| P0/urgent clarification timer · `chat_page + chat/widgets: light-only status colors` | #B25000 | #F3F2FF | 1.007248 | 4.657733 | 4.691493 | 正文 AA 达 |
| P0/success tool/notice · `chat_page + chat/widgets: light-only status colors` | #1E7A34 | #F0FAF2 | 1.044745 | 4.839624 | 5.056174 | 正文 AA 达 |
| P0/failed tool/error banner · `chat_page + chat/widgets: light-only status colors` | #B3001B | #FFF4F3 | 1.035448 | 6.417374 | 6.644855 | 正文 AA 达 |
| P0/offline banner/selected menu · `chat_page + chat/widgets: light-only status colors` | #005FB8 | #E0ECFF | 1.068576 | 5.653126 | 5.290335 | 正文 AA 达 |
| P0/assistant link · `chat_page + chat/widgets: light-only status colors` | #005FB8 | #F2F2F7 | 1.000000 | 5.653126 | 5.653126 | 正文 AA 达 |
| P0/tool name + selected context title · `chat_page + chat/widgets: light-only status colors` | #005FB8 | #FFFFFF | 1.115871 | 5.653126 | 6.308159 | 正文 AA 达 |
| P0/dialog normal/statusBlueText · `SDK dialog surface over modal scrim + uniform chat page; arbitrary backdrop is not certified` | #005FB8 | #E8E8E9 | 1.094239 | 5.653126 | 5.166263 | 正文 AA 达 |
| P0/dialog normal/statusRedText · `SDK dialog surface over modal scrim + uniform chat page; arbitrary backdrop is not certified` | #B3001B | #E8E8E9 | 1.094239 | 6.417374 | 5.864691 | 正文 AA 达 |
| P0/dialog pressed/statusBlueText · `SDK dialog surface over modal scrim + uniform chat page; arbitrary backdrop is not certified` | #005FB8 | #E1E1E1 | 1.171901 | 5.653126 | 4.823893 | 正文 AA 达 |
| P0/dialog pressed/statusRedText · `SDK dialog surface over modal scrim + uniform chat page; arbitrary backdrop is not certified` | #B3001B | #E1E1E1 | 1.171901 | 6.417374 | 5.476036 | 正文 AA 达 |
| P0/clarification title · `chat/chat_page.dart` | #5856D6 | #F3F2FF | 1.007248 | 5.062968 | 5.099666 | 正文 AA 达 |
| P0/context warning ring · `chat/widgets/context_window_indicator.dart` | #B25000 | #F2F2F7 | 1.000000 | 4.657733 | 4.657733 | 非文本 达 |
| P0/media inverse secondary · `chat/widgets/chat_media_view.dart: fixed black lightbox, unchanged` | #8E8E93 | #000000 | 18.819381 | 2.921958 | 6.440674 | 正文 AA 达 |
| P0/green notice layering · `chat/chat_page.dart: paired with the explicit hairline` | #F0FAF2 | #F2F2F7 | 1.000000 | 1.044745 | 1.044745 | 装饰豁免 |
| P1/readable secondary/page · `sidebar toolbar, empty detail, menu title and disabled-message menu` | #6A6A6F | #F2F2F7 | 1.000000 | 4.820554 | 4.820554 | 正文 AA 达 |
| P1/structural divider/page · `sidebar resize handle and toolbar/menu separator; cursor and semantics unchanged` | #CCD0DA | #F2F2F7 | 1.000000 | 1.383553 | 1.383553 | 装饰豁免 |
| P1/popover hairline/page · `adaptive_popover + popover_dropdown: explicit 1px card boundary` | #CCD0DA | #F2F2F7 | 1.000000 | 1.383553 | 1.383553 | 装饰豁免 |
| P1/readable secondary/card · `sidebar toolbar, empty detail, menu title and disabled-message menu` | #6A6A6F | #FFFFFF | 1.115871 | 4.820554 | 5.379116 | 正文 AA 达 |
| P1/structural divider/card · `sidebar resize handle and toolbar/menu separator; cursor and semantics unchanged` | #CCD0DA | #FFFFFF | 1.115871 | 1.383553 | 1.543866 | 装饰豁免 |
| P1/popover hairline/card · `adaptive_popover + popover_dropdown: explicit 1px card boundary` | #CCD0DA | #FFFFFF | 1.115871 | 1.383553 | 1.543866 | 装饰豁免 |
| P1/readable secondary/selection · `sidebar toolbar, empty detail, menu title and disabled-message menu` | #6A6A6F | #E0ECFF | 1.068576 | 4.820554 | 4.511193 | 正文 AA 达 |
| P1/structural divider/selection · `sidebar resize handle and toolbar/menu separator; cursor and semantics unchanged` | #CCD0DA | #E0ECFF | 1.068576 | 1.383553 | 1.294763 | 装饰豁免 |
| P1/popover hairline/selection · `adaptive_popover + popover_dropdown: explicit 1px card boundary` | #CCD0DA | #E0ECFF | 1.068576 | 1.383553 | 1.294763 | 装饰豁免 |
| P1/readable secondary/pressed · `sidebar toolbar, empty detail, menu title and disabled-message menu` | #6A6A6F | #F2F2F7 | 1.000000 | 4.820554 | 4.820554 | 正文 AA 达 |
| P1/structural divider/pressed · `sidebar resize handle and toolbar/menu separator; cursor and semantics unchanged` | #CCD0DA | #F2F2F7 | 1.000000 | 1.383553 | 1.383553 | 装饰豁免 |
| P1/popover hairline/pressed · `adaptive_popover + popover_dropdown: explicit 1px card boundary` | #CCD0DA | #F2F2F7 | 1.000000 | 1.383553 | 1.383553 | 装饰豁免 |
| P1/selected toolbar icon · `sidebar_utility_toolbar.dart` | #005FB8 | #E0ECFF | 1.068576 | 5.653126 | 5.290335 | 非文本 达 |
| P1/empty detail filled action · `empty_detail_pane.dart: local button fill only` | #FFFFFF | #005FB8 | 5.653126 | 1.115871 | 6.308159 | 正文 AA 达 |
| P1/popover action/statusBlueText/card · `adaptive_action_menu.dart: default/destructive rows` | #005FB8 | #FFFFFF | 1.115871 | 5.653126 | 6.308159 | 正文 AA 达 |
| P1/popover action/statusRedText/card · `adaptive_action_menu.dart: default/destructive rows` | #B3001B | #FFFFFF | 1.115871 | 6.417374 | 7.160960 | 正文 AA 达 |
| P1/popover action/statusBlueText/pressed · `adaptive_action_menu.dart: default/destructive rows` | #005FB8 | #F2F2F7 | 1.000000 | 5.653126 | 5.653126 | 正文 AA 达 |
| P1/popover action/statusRedText/pressed · `adaptive_action_menu.dart: default/destructive rows` | #B3001B | #F2F2F7 | 1.000000 | 6.417374 | 6.417374 | 正文 AA 达 |
| P1/native sheet/normal/LightSurfaces.menuAction/page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #004A94 | #EFEFF0 | 1.026161 | 7.818165 | 7.618851 | 正文 AA 达 |
| P1/native sheet/normal/statusRedText/page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #B3001B | #EFEFF0 | 1.026161 | 6.417374 | 6.253771 | 正文 AA 达 |
| P1/native sheet title + disabled message/page · `menu title and P0 empty-message labels, evaluated on the normal sheet surface` | #6A6A6F | #EFEFF0 | 1.026161 | 4.820554 | 4.697660 | 正文 AA 达 |
| P1/native sheet/pressed/LightSurfaces.menuAction/page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #004A94 | #DADADB | 1.255914 | 7.818165 | 6.225079 | 正文 AA 达 |
| P1/native sheet/pressed/statusRedText/page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #B3001B | #DADADB | 1.255914 | 6.417374 | 5.109723 | 正文 AA 达 |
| P1/native sheet/cancel/LightSurfaces.menuAction/page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #004A94 | #FFFFFF | 1.115871 | 7.818165 | 8.724063 | 正文 AA 达 |
| P1/native sheet/cancel/statusRedText/page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #B3001B | #FFFFFF | 1.115871 | 6.417374 | 7.160960 | 正文 AA 达 |
| P1/native sheet/cancel pressed/LightSurfaces.menuAction/page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #004A94 | #ECECEC | 1.058697 | 7.818165 | 7.384703 | 正文 AA 达 |
| P1/native sheet/cancel pressed/statusRedText/page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #B3001B | #ECECEC | 1.058697 | 6.417374 | 6.061576 | 正文 AA 达 |
| P1/inherited navigation icons/page · `AppBackButton + NarrowNavigationDropdownButton: icon-only, original primary retained` | #007AFF | #F2F2F7 | 1.000000 | 3.599857 | 3.599857 | 非文本 达 |
| P1/inverse exit toast/page · `adaptive_shell.dart: retained fixed inverse content` | #FFFFFF | #2C2C2C | 12.580032 | 1.115871 | 14.037691 | 正文 AA 达 |
| P1/native sheet/normal/LightSurfaces.menuAction/global page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #004A94 | #EFEFF0 | 1.026161 | 7.818165 | 7.618851 | 正文 AA 达 |
| P1/native sheet/normal/statusRedText/global page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #B3001B | #EFEFF0 | 1.026161 | 6.417374 | 6.253771 | 正文 AA 达 |
| P1/native sheet title + disabled message/global page · `menu title and P0 empty-message labels, evaluated on the normal sheet surface` | #6A6A6F | #EFEFF0 | 1.026161 | 4.820554 | 4.697660 | 正文 AA 达 |
| P1/native sheet/pressed/LightSurfaces.menuAction/global page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #004A94 | #DADADB | 1.255914 | 7.818165 | 6.225079 | 正文 AA 达 |
| P1/native sheet/pressed/statusRedText/global page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #B3001B | #DADADB | 1.255914 | 6.417374 | 5.109723 | 正文 AA 达 |
| P1/native sheet/cancel/LightSurfaces.menuAction/global page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #004A94 | #FFFFFF | 1.115871 | 7.818165 | 8.724063 | 正文 AA 达 |
| P1/native sheet/cancel/statusRedText/global page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #B3001B | #FFFFFF | 1.115871 | 6.417374 | 7.160960 | 正文 AA 达 |
| P1/native sheet/cancel pressed/LightSurfaces.menuAction/global page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #004A94 | #ECECEC | 1.058697 | 7.818165 | 7.384703 | 正文 AA 达 |
| P1/native sheet/cancel pressed/statusRedText/global page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #B3001B | #ECECEC | 1.058697 | 6.417374 | 6.061576 | 正文 AA 达 |
| P1/inherited navigation icons/global page · `AppBackButton + NarrowNavigationDropdownButton: icon-only, original primary retained` | #007AFF | #F2F2F7 | 1.000000 | 3.599857 | 3.599857 | 非文本 达 |
| P1/inverse exit toast/global page · `adaptive_shell.dart: retained fixed inverse content` | #FFFFFF | #2C2C2C | 12.580032 | 1.115871 | 14.037691 | 正文 AA 达 |
| P1/native sheet/normal/LightSurfaces.menuAction/card · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #004A94 | #F2F2F2 | 1.006397 | 7.818165 | 7.768472 | 正文 AA 达 |
| P1/native sheet/normal/statusRedText/card · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #B3001B | #F2F2F2 | 1.006397 | 6.417374 | 6.376585 | 正文 AA 达 |
| P1/native sheet title + disabled message/card · `menu title and P0 empty-message labels, evaluated on the normal sheet surface` | #6A6A6F | #F2F2F2 | 1.006397 | 4.820554 | 4.789914 | 正文 AA 达 |
| P1/native sheet/pressed/LightSurfaces.menuAction/card · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #004A94 | #DCDCDC | 1.230761 | 7.818165 | 6.352303 | 正文 AA 达 |
| P1/native sheet/pressed/statusRedText/card · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #B3001B | #DCDCDC | 1.230761 | 6.417374 | 5.214153 | 正文 AA 达 |
| P1/native sheet/cancel/LightSurfaces.menuAction/card · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #004A94 | #FFFFFF | 1.115871 | 7.818165 | 8.724063 | 正文 AA 达 |
| P1/native sheet/cancel/statusRedText/card · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #B3001B | #FFFFFF | 1.115871 | 6.417374 | 7.160960 | 正文 AA 达 |
| P1/native sheet/cancel pressed/LightSurfaces.menuAction/card · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #004A94 | #ECECEC | 1.058697 | 7.818165 | 7.384703 | 正文 AA 达 |
| P1/native sheet/cancel pressed/statusRedText/card · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #B3001B | #ECECEC | 1.058697 | 6.417374 | 6.061576 | 正文 AA 达 |
| P1/inherited navigation icons/card · `AppBackButton + NarrowNavigationDropdownButton: icon-only, original primary retained` | #007AFF | #FFFFFF | 1.115871 | 3.599857 | 4.016976 | 非文本 达 |
| P1/inverse exit toast/card · `adaptive_shell.dart: retained fixed inverse content` | #FFFFFF | #2E2E2E | 12.186859 | 1.115871 | 13.598961 | 正文 AA 达 |
| P1/popover shadow alpha=0.35 · `popover_dropdown/adaptive_popover: decorative elevation shadow retained` | #C7C7CC / α=0.350000 | #F2F2F7 | 1.000000 | 1.146727 | 1.146727 | 装饰豁免 |
| P1/popover shadow alpha=0.5 · `popover_dropdown/adaptive_popover: decorative elevation shadow retained` | #C7C7CC / α=0.500000 | #F2F2F7 | 1.000000 | 1.218767 | 1.218767 | 装饰豁免 |
| 看板选中标签/白字 · `kanban/kanban_page.dart` | #FFFFFF | #007AFF | 3.599857 | 1.115871 | 4.016976 | 正文 AA 不达标 |
| 看板卡片/secondaryText · `kanban/kanban_page.dart` | #3C3C43 / α=0.600000 | #F2F2F7 | 1.000000 | 3.295321 | 3.295321 | 正文 AA 不达标 |
| 看板黄色提醒/正文 · `kanban/kanban_page.dart` | #000000 | #F5EAC6 | 1.075725 | 18.819381 | 17.494610 | 正文 AA 达 |
| 诊断日志级别标签/statusGreyText · `diagnostics/diagnostics_detail_sheet.dart + diagnostics_models.dart` | #595959 | #E6E6E6 | 1.117439 | 6.277365 | 5.617635 | 正文 AA 达 |
| 诊断日志级别标签/_statusDebugText · `diagnostics/diagnostics_detail_sheet.dart + diagnostics_models.dart` | #4A6B82 | #E4E9EC | 1.097919 | 5.063617 | 4.612014 | 正文 AA 达 |
| 诊断日志级别标签/statusBlueText · `diagnostics/diagnostics_detail_sheet.dart + diagnostics_models.dart` | #005FB8 | #D9E7F4 | 1.128014 | 5.653126 | 5.011574 | 正文 AA 达 |
| 诊断日志级别标签/statusOrangeText · `diagnostics/diagnostics_detail_sheet.dart + diagnostics_models.dart` | #B25000 | #F3E5D9 | 1.106606 | 4.657733 | 4.209025 | 正文 AA 不达标 |
| 诊断日志级别标签/statusRedText · `diagnostics/diagnostics_detail_sheet.dart + diagnostics_models.dart` | #B3001B | #F4D9DD | 1.193088 | 6.417374 | 5.378791 | 正文 AA 达 |
| 默认搜索框/页面 · `SDK/search_field.dart` | #3C3C43 / α=0.600000 | #E3E3E9 | 1.141332 | 3.295321 | 3.124865 | 正文 AA 不达标 |
| 默认搜索框/白卡 · `SDK/search_field.dart` | #3C3C43 / α=0.600000 | #EFEFF0 | 1.030757 | 3.295321 | 3.256252 | 正文 AA 不达标 |
| 默认列表按下行/secondaryLabel · `SDK/list_tile.dart` | #3C3C43 / α=0.600000 | #D1D1D6 | 1.363500 | 3.295321 | 2.899310 | 正文 AA 不达标 |
| 框架弹层/label · SDK/dialog.dart#_kDialogColor · `SDK/dialog.dart；以均匀旧页面作模糊下层参考` | #000000 | #F2F2F3 | 1.002603 | 18.819381 | 18.770514 | 正文 AA 达 |
| 框架弹层/label · SDK/dialog.dart#_kDialogPressedColor · `SDK/dialog.dart；以均匀旧页面作模糊下层参考` | #000000 | #E1E1E1 | 1.171901 | 18.819381 | 16.058844 | 正文 AA 达 |
| 框架弹层/label · SDK/dialog.dart#_kActionSheetPressedColor · `SDK/dialog.dart；以均匀旧页面作模糊下层参考` | #000000 | #E4E4E5 | 1.141384 | 18.819381 | 16.488212 | 正文 AA 达 |
| 框架弹层/label · SDK/dialog.dart#_kActionSheetCancelColor · `SDK/dialog.dart；以均匀旧页面作模糊下层参考` | #000000 | #FFFFFF | 1.115871 | 18.819381 | 21.000000 | 正文 AA 达 |
| 框架弹层/label · SDK/dialog.dart#_kActionSheetCancelPressedColor · `SDK/dialog.dart；以均匀旧页面作模糊下层参考` | #000000 | #ECECEC | 1.058697 | 18.819381 | 17.775980 | 正文 AA 达 |
| 框架弹层/label · SDK/dialog.dart#_kActionSheetBackgroundColor · `SDK/dialog.dart；以均匀旧页面作模糊下层参考` | #000000 | #FAFAFB | 1.068355 | 18.819381 | 20.105776 | 正文 AA 达 |
| 默认 ActionSheet 内容灰字 · `SDK/dialog.dart；以均匀旧页面作模糊下层参考` | #1D1D1D / α=0.521569 | #FAFAFB | 1.068355 | 3.393715 | 3.453471 | 正文 AA 不达标 |
| 用量柱形/默认蓝 · `insights/insights_page.dart` | #007AFF | #FFFFFF | 1.115871 | 3.599857 | 4.016976 | 非文本 达 |
| 用量柱形/触摸深蓝 · `insights/insights_page.dart` | #004999 | #FFFFFF | 1.115871 | 7.799167 | 8.702863 | 非文本 达 |
| 品牌图标承载面/黑色图标 · `onboarding/widgets/onboarding_hero_motion.dart` | #000000 | #E5E5EA | 1.125061 | 18.819381 | 16.727430 | 非文本 达 |
| Mermaid 深色节点/白字 · `chat/widgets/mermaid_block.dart：非浅色 UI 面` | #FFFFFF | #2C2C2E | 12.489479 | 1.115871 | 13.936646 | 深色图表配置豁免 |
| Mermaid 深色 cluster/白字 · `chat/widgets/mermaid_block.dart：非浅色 UI 面` | #FFFFFF | #1C1C1E | 15.247942 | 1.115871 | 17.014735 | 深色图表配置豁免 |
| 会话列表反色 tooltip/新页面 · `session_list/session_list_page.dart` | #FFFFFF | #0E0E0F | 17.269103 | 1.115871 | 19.270090 | 正文 AA 达 |
| 外壳反色 toast/新页面 · `app/shell/adaptive_shell.dart` | #FFFFFF | #2C2C2C | 12.580032 | 1.115871 | 14.037691 | 正文 AA 达 |
| 会话列表反色 tooltip/白卡 · `session_list/session_list_page.dart` | #FFFFFF | #0F0F0F | 17.178193 | 1.115871 | 19.168645 | 正文 AA 达 |
| 外壳反色 toast/白卡 · `app/shell/adaptive_shell.dart` | #FFFFFF | #2E2E2E | 12.186859 | 1.115871 | 13.598961 | 正文 AA 达 |

### C. SDK 默认面、控件文字与装饰实算

私有默认常量从上述同一 SDK 自动读取；动态背景按页面/白卡/黑色三个均匀下层分别合成。渐变/模糊上叠加任意内容时，仍需实际画面复核。

| SDK 来源 | RGB / alpha | 对页面 | 对白卡 | 对黑色 | 用途 |
|---|---|---:|---:|---:|---|
| `SDK/dialog.dart#_kActionSheetBackgroundColor` | #FCFCFC / α=0.784314 | 1.068355 | 1.020272 | 12.249161 | 装饰面/边框/状态背景豁免 |
| `SDK/dialog.dart#_kActionSheetButtonDividerColor` | #C9C9C9 / α=0.831373 | 1.382589 | 1.510333 | 8.739442 | 装饰面/边框/状态背景豁免 |
| `SDK/dialog.dart#_kActionSheetCancelColor` | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面/边框/状态背景豁免 |
| `SDK/dialog.dart#_kActionSheetCancelPressedColor` | #ECECEC | 1.058697 | 1.181369 | 17.775980 | 装饰面/边框/状态背景豁免 |
| `SDK/dialog.dart#_kActionSheetContentTextColor` | #1D1D1D / α=0.521569 | 3.393715 | 3.492347 | 1.096533 | 文字：按实际面 AA |
| `SDK/dialog.dart#_kActionSheetPressedColor` | #E0E0E0 / α=0.792157 | 1.141384 | 1.242970 | 9.842179 | 装饰面/边框/状态背景豁免 |
| `SDK/dialog.dart#_kDialogColor` | #F2F2F2 / α=0.800000 | 1.002603 | 1.094071 | 11.739865 | 装饰面/边框/状态背景豁免 |
| `SDK/dialog.dart#_kDialogPressedColor` | #E1E1E1 | 1.171901 | 1.307691 | 16.058844 | 装饰面/边框/状态背景豁免 |
| `SDK/list_section.dart#_kHeaderFooterColor` | #6C6C6C | 4.705791 | 5.251056 | 3.999196 | 文字：按实际面 AA |
| `SDK/nav_bar.dart#_kDefaultNavBarBorderColor` | #000000 / α=0.301961 | 2.101806 | 2.120350 | 1.000000 | 装饰面/边框/状态背景豁免 |
| `SDK/nav_bar.dart#_kTransparentNavBarBorder` | #000000 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 装饰面/边框/状态背景豁免 |
| `SDK/route.dart#_kCupertinoPageTransitionBarrierColor` | #000000 / α=0.094118 | 1.234172 | 1.236599 | 1.000000 | 装饰面/边框/状态背景豁免 |
| `SDK/route.dart#kCupertinoModalBarrierColor` | #000000 / α=0.200000 | 1.598086 | 1.605929 | 1.000000 | 装饰面/边框/状态背景豁免 |
| `SDK/sliding_segmented_control.dart#_kDisabledContentColor` | #7A7A7A / α=0.450980 | 1.700408 | 1.762196 | 1.764608 | 装饰面/边框/状态背景豁免 |
| `SDK/sliding_segmented_control.dart#_kSeparatorColor` | #8E8E93 / α=0.301961 | 1.326122 | 1.358404 | 1.482935 | 装饰面/边框/状态背景豁免 |
| `SDK/sliding_segmented_control.dart#_kThumbColor` | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面/边框/状态背景豁免 |
| `SDK/text_field.dart#_kClearButtonColor` | #000000 / α=0.200000 | 1.598086 | 1.605929 | 1.000000 | 功能图标：3:1 |
| `SDK/text_field.dart#_kDefaultRoundedBorderDecoration` | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面/边框/状态背景豁免 |
| `SDK/text_field.dart#_kDefaultRoundedBorderSide` | #000000 / α=0.200000 | 1.598086 | 1.605929 | 1.000000 | 装饰面/边框/状态背景豁免 |
| `SDK/text_field.dart#_kDisabledBackground` | #FAFAFA | 1.069082 | 1.043765 | 20.119467 | 装饰面/边框/状态背景豁免 |
| `SDK/text_field.dart#kMisspelledSelectionColor` | #FF9699 / α=0.384314 | 1.272901 | 1.318618 | 2.180202 | 装饰面/边框/状态背景豁免 |

### D. 复验边界

AA 数字评估的是指定颜色组合，不能代替字体大小/字重、模糊下层、动态透明度、照片内容或系统级通知的视觉验证。阶段一的截图和暗色比对证据在任务临时目录；全仓其余页本轮只读，下一阶段按优先级迁移并补对应状态截图。
