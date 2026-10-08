import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 界面缩放档位（HiDPI / UI Scale）：100% / 125% / 150% / 200%。
///
/// **语义**：把「逻辑视口」按档位缩小（见 `lib/app/app.dart` 的 `builder`），于是
/// Cupertino 组件、字号、间距**全部等比放大** —— 效果即「UI 缩放」。覆写的是
/// **应用层** MediaQuery，不动平台真实 `devicePixelRatio`（渲染精度不变）。
///
/// **与宽窄屏分流的关系（主人 2026-09-27 拍板 A 方案）**：缩放后的逻辑宽**参与**判定 ——
/// 150% 下 1280 窗口 = 853 逻辑宽 < 900 ⇒ 转窄屏单栏。这符合「缩放」本意（空间确实
/// 不够了），而且窄屏分支本就是为空间不足设计的形态。实现上无需逐处改造：各页的
/// `isWideLayout` 走的都是 `MediaQuery.sizeOf`，覆写点在最外层即自动生效。
enum AppUiScale {
  x1(1.0, '100%'),
  x125(1.25, '125%'),
  x150(1.5, '150%'),
  x2(2.0, '200%');

  const AppUiScale(this.factor, this.label);

  /// 缩放系数（> 1 = 界面变大）。
  final double factor;

  /// 档位文案（设置页用）。纯数字百分比，中英一致，无需进 l10n。
  final String label;
}

/// 界面缩放 Provider（持久化到 shared_preferences，模式同 [themeModeProvider]）。
final uiScaleProvider = NotifierProvider<UiScaleController, AppUiScale>(
  UiScaleController.new,
);

class UiScaleController extends Notifier<AppUiScale> {
  static const String prefsKey = 'app_ui_scale';

  @override
  AppUiScale build() {
    unawaited(_load());
    // 默认 100%：与改造前逐像素一致。
    return AppUiScale.x1;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null) return;
    for (final scale in AppUiScale.values) {
      if (scale.name == raw) {
        state = scale;
        return;
      }
    }
  }

  /// 切换缩放档位并持久化。
  Future<void> setScale(AppUiScale scale) async {
    state = scale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, scale.name);
  }
}

/// 把 [child] 按 [scale] 缩放到真实视口 —— 这是界面缩放的**唯一落点**，
/// 抽成独立件以便 `app.dart` 与守卫测试共用同一份逻辑（测试不必复刻 builder）。
///
/// **两段式，缺一不可**（第一版只做了 ①，实测字体/尺寸一个像素都没动）：
/// ① `MediaQuery` 覆写：`size / factor` ⇒ 内层按「缩小后的逻辑视口」布局
///    （各页 `MediaQuery.sizeOf` 判定随之生效 = A 方案），`devicePixelRatio * factor`
///    使 `1 / dpr` 之类「物理像素换算」（如会话列表发丝线）仍然精确等于 1 物理像素。
/// ② `Transform.scale` 真放大绘制：把内层布局好的画面放大 `factor` 倍画回真实逻辑
///    视口。**这一步才是「看得见」的缩放** —— 渲染用的逻辑像素坐标系由引擎真实
///    dpr 决定，只改 MediaQuery 数据不会改变任何绘制尺寸（字体、间距、图标全不变）。
///
/// `OverflowBox` 是必需的：真实视口给下来的是紧约束，直接放子件会被撑满，
/// 内层就再也拿不到 `size / factor` 那片小视口（① 于是形同虚设）。
/// 它也保证了 `Transform` 自身尺寸 = 真实视口 ⇒ 放大后的整屏都能响应命中测试。
///
/// - **100% 档原样返回**（不新建任何 Widget）：与改造前逐像素一致。
/// - 真实 dpr 不动（引擎侧渲染精度不变），改的只是应用层语义。
Widget applyUiScale(BuildContext context, Widget child, AppUiScale scale) {
  if (scale == AppUiScale.x1) return child;
  final media = MediaQuery.of(context);
  final logical = media.size / scale.factor;
  return MediaQuery(
    data: media.copyWith(
      size: logical,
      devicePixelRatio: media.devicePixelRatio * scale.factor,
    ),
    child: Transform.scale(
      scale: scale.factor,
      alignment: Alignment.topLeft,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: logical.width,
        maxWidth: logical.width,
        minHeight: logical.height,
        maxHeight: logical.height,
        child: child,
      ),
    ),
  );
}
