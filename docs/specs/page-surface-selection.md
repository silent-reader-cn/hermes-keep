# 页面底色可选（设置 → 外观）

主人 2026-10-06 拍板：把 App 的页面底色从固定值改为**用户可选**——预设若干档 +
允许自定义，**默认「中性同深」**。

## 1. 背景

改造前页底色固定为 iOS 分组灰 `#F2F2F7`（`LightSurfaces.page`）。它 RGB(242,242,247)
的蓝通道比红绿高 5（色相 290°，蓝紫灰），主人实机反馈「灰蓝灰蓝」。

真渲染实测：该色占**设置页 78.3%**、**会话列表 23.9%** 的画面 —— 是绝对主色调，
所以「底色的色相」直接决定整体观感，不是细节。

设计选型对比（六档真渲染图，见 `.shots/pagebg-compare-light.png` /
`pagebg-compare-sessions.png` / `pagebg-stitch-light.png`）的客观判据：

| 档 | 色值 | 对白卡对比度 | ΔE vs 原值 | 说明 |
|---|---|---|---|---|
| iOS 分组灰 | `#F2F2F7` | 1.116 | — | 原值，冷（色相 290°） |
| **中性同深（默认）** | `#F2F2F2` | 1.120 | 2.6 | 只去蓝，明度不变 |
| 中性加深 | `#EDEDED` | 1.171 | 3.2 | 白卡浮起更明显 |
| 中性提白 | `#F8F8F8` | 1.096 | — | 最干净通透（卡片边界变弱） |
| 暖中性 | `#F1EFEA` | 1.149 | 5.3 | 色相 94°，暖得克制 |
| 暖米白 | `#F6F3EE` | 1.117 | 5.7 | 纸感更强 |

## 2. 用户可见行为

| 项 | 行为 |
|---|---|
| 入口 | 设置 → 外观 → **页面底色**（trailing 显示当前色块 + 档名） |
| 承载 | 宽屏（≥ [kAdaptiveBreakpoint]=900）居中卡片（宽 420）；窄屏贴底 sheet |
| 浅色预设 | iOS 分组灰 / **中性同深（默认）** / 中性加深 / 中性提白 / 暖中性 / 暖米白 |
| 深色预设 | **跟随系统（默认）** / 中性 / 更深 / 暖 |
| 自定义 | 每态末尾「+」入口；选中后出现 `#RRGGBB` 输入框；非法输入就地提示并回落默认档 |
| 提交 | 选择器内是**草稿态**（带实时预览条），点「应用」才一次性生效 |
| 恢复默认 | 选择器内按钮，同样走草稿 |

**深浅两态各自独立**：选浅色不影响深色；深色「跟随系统」= 不覆盖（沿用 Cupertino
原生分组背景，保留其高对比度动态色语义）。

## 3. 令牌架构（为什么改动面只有 6 个文件）

三个令牌从 `static const` 改为 **getter**，值读 `LightSurfaces` 内的全局可变态：

```
PageSurfaceController（Riverpod Notifier，持久化 shared_preferences）
   └─ 写 → LightSurfaces.applyUserSurface({light, dark})
              ├─ page        （浅色页底色）
              ├─ darkPage    （浅色以外；null = 不覆盖）
              └─ cardBorder / divider（按 page 派生，二者同值）
   └─ app.dart: ref.watch(pageSurfaceProvider) → ValueKey 换 key ⇒ 整棵树重建
```

- **不改 250 处调用点**：全仓引用 `LightSurfaces.page` / `cardBorder` / `divider`
  共 250 次（57 个文件），其中处于 `const` 上下文仅十余处。getter 化后调用侧写法
  一字不动，只需给那些 const 表达式摘掉关键字。
- **重建 vs 精确刷新**：颜色是 widget 属性，属性变化必须 rebuild 对应 widget；
  令牌是静态的、widget 不 watch 任何 provider，所以只能靠换 key 重建整棵树
  （`CupertinoApp.router` 的 key）。`routerConfig` 是同一个 GoRouter 实例，
  **路由位置不受影响**；代价是页面内状态（滚动位置、输入框内容）重置。
- **因此选择器必须是草稿态**：若边选边提交，弹层自身挂在被重建的 Navigator 上，
  点一下色块弹层就会被销毁。草稿态让用户能连续试色，最后一次性应用。

## 4. 描边派生规则

`cardBorder` 与 `divider`（v3 起同值）**跟随页底色派生**，否则暖底配冷灰紫描边会
色相分家：

1. 取页底色的 HSL 色相；饱和度降到 60%（上限 0.20）—— 描边不该比底色更「彩」；
2. 明度二分搜索，使**对白卡对比度 = 1.543866:1**（= 原 `#CCD0DA` 的实测值），
   只换色相、不换可见度；
3. **特例**：页底色为 `#F2F2F7`（iOS 分组灰档）时直接返回原设计值 `#CCD0DA`，
   保证该档能逐像素还原改造前。

## 5. 影响面与落码清单

| 位置 | 改动 |
|---|---|
| `lib/app/theme/page_surface.dart` | **新增**：预设枚举、状态、controller、hex 解析 |
| `lib/app/theme/light_surfaces.dart` | page/cardBorder/divider 改 getter；新增 darkPage、applyUserSurface、borderFor、描边派生 |
| `lib/app/theme/cupertino_theme.dart` | 浅色 scaffold 跟随令牌（深色保持纯黑最底层） |
| `lib/app/app.dart` | watch provider + `key: ValueKey<PageSurfaceState>` |
| `lib/features/settings/settings_page.dart` | 外观组新增一行 |
| `lib/features/settings/widgets/page_surface_picker.dart` | **新增**：选择器（草稿态 + 预览） |
| `lib/l10n/app_localizations.dart` | 新增 18 个键（中英进表） |
| 15 个页面的 `dark: CupertinoColors.systemGroupedBackground` | 统一为 `LightSurfaces.darkPage` |

## 6. 已知取舍

- **默认档可变 ⇒ 浅色金照基线需重拍**（默认视觉从 `#F2F2F7` 变为 `#F2F2F2`，
  这是本次需求的目的，不是回归）。
- **整树重建**会重置页面内状态。改色是低频操作且发生在设置页，代价可接受；
  若要消除，需把 250 处引用改成 context-aware 读取（大改造，不做）。
- 高对比度模式下浅色 scaffold 不再走 `CupertinoColors.systemGroupedBackground`
  的动态变体 —— 令牌本就是「固定不透明 sRGB」语义，且默认档已非系统色。

## 7. 待办

- [ ] 深色档位的真渲染对比图（本轮只出了浅色六档对比）。
- [ ] 若主人要求，选择器可加色相/明度滑杆作为「自定义」的易用入口。
