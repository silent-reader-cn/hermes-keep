import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'light_surfaces.dart';

/// 页面底色预设（**浅色模式**）。
///
/// 主人 2026-10-06 拍板：把页面底色开放给用户选，预设由设计选型对比确定
/// （六档真渲染对比见 `.shots/pagebg-compare-light.png`），默认「中性同深」。
///
/// 各档取值与设计依据：
/// - [iosGrouped] `#F2F2F7` —— 改造前的 iOS 分组灰（色相 290°，蓝通道比红绿
///   高 5），即主人反馈的「灰蓝灰蓝」。保留为预设以便随时回退。
/// - [neutral] `#F2F2F2` —— **默认档**。去蓝、明度不变（ΔE 2.6 vs 原值）。
/// - [neutralDeep] `#EDEDED` —— 中性再深一档，白卡浮起更明显（对白卡 1.171:1）。
/// - [neutralBright] `#F8F8F8` —— 中性提白，最干净通透（代价：卡片边界变弱）。
/// - [warmNeutral] `#F1EFEA` —— 暖中性，色相 94°（ΔE 5.3，冷暖差肉眼可辨）。
/// - [warmPaper] `#F6F3EE` —— 暖米白，纸感更强。
/// - [custom] —— 用户自定，值取 [PageSurfaceState.lightCustomHex]。
enum PageSurfacePreset {
  iosGrouped(0xFFF2F2F7),
  neutral(0xFFF2F2F2),
  neutralDeep(0xFFEDEDED),
  neutralBright(0xFFF8F8F8),
  warmNeutral(0xFFF1EFEA),
  warmPaper(0xFFF6F3EE),
  custom(null);

  const PageSurfacePreset(this.argb);

  /// 预设的 ARGB 值；[custom] 为 null（值来自用户输入）。
  final int? argb;

  /// 预设色；[custom] 返回 null。
  Color? get color => argb == null ? null : Color(argb!);

  /// 是否为「跟随用户自定义」档。
  bool get isCustom => this == PageSurfacePreset.custom;
}

/// 页面底色预设（**深色模式**）。
///
/// 深色的可选空间比浅色小得多（底子接近黑，色相差异要靠 B 通道几档区分），
/// 因此档位更少；[system] 表示**不覆盖**，沿用 Cupertino 原生分组背景
/// （`#1C1C1E`，即改造前行为）。
enum DarkSurfacePreset {
  system(null),
  neutral(0xFF1C1C1C),
  deeper(0xFF141414),
  warm(0xFF1E1C1A),
  custom(null);

  const DarkSurfacePreset(this.argb);

  final int? argb;

  Color? get color => argb == null ? null : Color(argb!);

  bool get isCustom => this == DarkSurfacePreset.custom;

  /// [system] 与 [custom] 的 argb 都是 null，靠此区分。
  bool get followsSystem => this == DarkSurfacePreset.system;
}

/// 页面底色的完整用户选择（明暗两态各自独立）。
@immutable
class PageSurfaceState {
  const PageSurfaceState({
    this.lightPreset = PageSurfacePreset.neutral,
    this.lightCustomHex = defaultLightCustomHex,
    this.darkPreset = DarkSurfacePreset.system,
    this.darkCustomHex = defaultDarkCustomHex,
  });

  /// 默认自定值（用户切到「自定义」但还没输入时的初值）。取默认档色，
  /// 使「切到自定义」这一步本身不改变任何像素。
  static const String defaultLightCustomHex = '#F2F2F2';
  static const String defaultDarkCustomHex = '#1C1C1E';

  final PageSurfacePreset lightPreset;
  final String lightCustomHex;
  final DarkSurfacePreset darkPreset;
  final String darkCustomHex;

  /// 浅色模式生效的页底色（[lightPreset] 为 custom 时取输入值；
  /// 输入非法则回落到 [PageSurfacePreset.neutral]）。
  Color get lightPage =>
      lightPreset.isCustom
          ? (parseHexColor(lightCustomHex) ?? PageSurfacePreset.neutral.color!)
          : lightPreset.color!;

  /// 深色模式生效的页底色；`null` = 不覆盖（跟随系统）。
  ///
  /// [DarkSurfacePreset.custom] 且输入非法时回落到「不覆盖」，避免把非法值
  /// 灌进全局令牌。
  Color? get darkPage {
    if (darkPreset.followsSystem) return null;
    if (darkPreset.isCustom) return parseHexColor(darkCustomHex);
    return darkPreset.color;
  }

  /// 浅色自定义输入是否非法（供设置页就地提示，不阻断其它档位）。
  bool get hasInvalidLightHex =>
      lightPreset.isCustom && parseHexColor(lightCustomHex) == null;

  bool get hasInvalidDarkHex =>
      darkPreset.isCustom && parseHexColor(darkCustomHex) == null;

  PageSurfaceState copyWith({
    PageSurfacePreset? lightPreset,
    String? lightCustomHex,
    DarkSurfacePreset? darkPreset,
    String? darkCustomHex,
  }) => PageSurfaceState(
    lightPreset: lightPreset ?? this.lightPreset,
    lightCustomHex: lightCustomHex ?? this.lightCustomHex,
    darkPreset: darkPreset ?? this.darkPreset,
    darkCustomHex: darkCustomHex ?? this.darkCustomHex,
  );

  @override
  bool operator ==(Object other) =>
      other is PageSurfaceState &&
      other.lightPreset == lightPreset &&
      other.lightCustomHex == lightCustomHex &&
      other.darkPreset == darkPreset &&
      other.darkCustomHex == darkCustomHex;

  @override
  int get hashCode =>
      Object.hash(lightPreset, lightCustomHex, darkPreset, darkCustomHex);
}

/// 解析 `#RRGGBB` / `RRGGBB` / `#RGB` / `RGB` 形式的十六进制颜色。
///
/// 容错优先：大小写不敏感、允许缺 `#`、忽略首尾空白；任何非法输入返回 null
/// （调用方负责回落），**不抛异常**——它直接接在用户输入框上。
Color? parseHexColor(String raw) {
  var s = raw.trim();
  if (s.startsWith('#')) s = s.substring(1);
  s = s.toUpperCase();
  if (s.length == 3) {
    // #RGB → #RRGGBB（每字符重复一次）
    s = s.split('').map((c) => '$c$c').join();
  }
  if (s.length != 6) return null;
  final value = int.tryParse(s, radix: 16);
  if (value == null) return null;
  return Color(0xFF000000 | value);
}

/// 把 [Color] 序列化成 `#RRGGBB`（供输入框回显）。
String hexFromColor(Color color) {
  final argb = color.toARGB32() & 0xFFFFFF;
  return '#${argb.toRadixString(16).toUpperCase().padLeft(6, '0')}';
}

/// 页面底色 Provider（持久化到 shared_preferences，模式同 [themeModeProvider]）。
///
/// 写状态的**唯一出口**是 [PageSurfaceController] 的 setter：它们在改状态的同时
/// 把值灌进 [LightSurfaces] 的全局令牌（全 App 250 处引用因此无需改动），
/// 由 `app.dart` 依 [state] 变化重建整棵树使新底色生效。
final pageSurfaceProvider =
    NotifierProvider<PageSurfaceController, PageSurfaceState>(
      PageSurfaceController.new,
    );

class PageSurfaceController extends Notifier<PageSurfaceState> {
  static const String lightKey = 'app_page_surface_light';
  static const String lightCustomKey = 'app_page_surface_light_custom';
  static const String darkKey = 'app_page_surface_dark';
  static const String darkCustomKey = 'app_page_surface_dark_custom';

  /// 用户是否已在本进程内主动改过选择。
  ///
  /// [_load] 是 unawaited 的：若它在用户改色**之后**才完成，用磁盘旧值覆盖会把
  /// 改动冲掉（真机冷启动后立刻改色即可复现，测试里表现为改完仍读到默认值）。
  /// 因此 load 落盘值时只在用户尚未改动过的情况下生效。
  bool _userModified = false;

  @override
  PageSurfaceState build() {
    const initial = PageSurfaceState();
    // 首帧即生效：默认档（中性同深）在读取磁盘前就已写进令牌，
    // 避免「先用旧色渲染再闪一下」。
    _apply(initial);
    unawaited(_load());
    return initial;
  }

  void _apply(PageSurfaceState state) {
    LightSurfaces.applyUserSurface(
      light: state.lightPage,
      dark: state.darkPage,
    );
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    // 磁盘值只在用户尚未改动过时生效，避免把刚写入的选择冲掉。
    if (_userModified) return;
    final lightRaw = prefs.getString(lightKey);
    final darkRaw = prefs.getString(darkKey);
    final next = PageSurfaceState(
      lightPreset: PageSurfacePreset.values.firstWhere(
        (p) => p.name == lightRaw,
        orElse: () => PageSurfacePreset.neutral,
      ),
      lightCustomHex:
          prefs.getString(lightCustomKey) ??
          PageSurfaceState.defaultLightCustomHex,
      darkPreset: DarkSurfacePreset.values.firstWhere(
        (p) => p.name == darkRaw,
        orElse: () => DarkSurfacePreset.system,
      ),
      darkCustomHex:
          prefs.getString(darkCustomKey) ??
          PageSurfaceState.defaultDarkCustomHex,
    );
    state = next;
    _apply(next);
  }

  Future<void> setLightPreset(PageSurfacePreset preset) =>
      _commit(state.copyWith(lightPreset: preset));

  /// 一次性应用选择器里的全部改动。
  ///
  /// 逐项调 setter 会触发多次状态变更 ⇒ 多次整树重建；选择器「应用」走这里。
  Future<void> applySelection({
    required PageSurfacePreset lightPreset,
    required String lightCustomHex,
    required DarkSurfacePreset darkPreset,
    required String darkCustomHex,
  }) => _commit(
    PageSurfaceState(
      lightPreset: lightPreset,
      lightCustomHex: lightCustomHex,
      darkPreset: darkPreset,
      darkCustomHex: darkCustomHex,
    ),
  );

  Future<void> setLightCustomHex(String hex) =>
      _commit(state.copyWith(lightCustomHex: hex));

  Future<void> setDarkPreset(DarkSurfacePreset preset) =>
      _commit(state.copyWith(darkPreset: preset));

  Future<void> setDarkCustomHex(String hex) =>
      _commit(state.copyWith(darkCustomHex: hex));

  /// 恢复默认（浅色 = 中性同深；深色 = 跟随系统）。
  Future<void> resetToDefaults() => _commit(const PageSurfaceState());

  Future<void> _commit(PageSurfaceState next) async {
    _userModified = true;
    state = next;
    _apply(next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(lightKey, next.lightPreset.name);
    await prefs.setString(lightCustomKey, next.lightCustomHex);
    await prefs.setString(darkKey, next.darkPreset.name);
    await prefs.setString(darkCustomKey, next.darkCustomHex);
  }
}
