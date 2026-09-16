/// 应用版本的**兜底**常量（仅保留 X.Y.Z，不含 +buildNumber）。
///
/// **运行时的真实版本来自 `package_info_plus`**（由 `UpdateCheckerService`
/// 解析系统安装信息，与设置页展示的版本同源）；本常量只在平台通道不可用时兜底。
///
/// 历史教训（#122）：它曾作为更新检查的主数据源，而每次 `pubspec` 升版都容易
/// 忘记同步（实测从 `0.1.31` 起漂了 18 个版本），导致「当前版本」永远落后 →
/// 装了最新版仍反复提示有更新。故降级为兜底，并由 `version_info_test` 强制它与
/// `pubspec.yaml` 的 X.Y.Z 一致，杜绝再次漂移。
const String appVersion = '0.1.52';

/// 比较版本号 [remote] 是否比 [current] 新。
///
/// 语义约定：
/// - 支持 tag 带前导 `v` / `V` 容错（如 `v0.1.31`）；
/// - 支持带 `+buildNumber` 容错（如 `0.1.30+33`）；
/// - 纯数字主版本/次版本/修订号比较：
///   - 1.2.3 > 1.2.2 (true)
///   - 1.10.0 > 1.9.9 (true)
///   - 相等 = false (无更新)
///   - 远端低于本地 = false
/// - 畸形字符串返回 false，保证安全容错。
bool newer(String remote, String current) {
  final cleanRemote = cleanVersionParts(remote);
  final cleanCurrent = cleanVersionParts(current);
  if (cleanRemote == null || cleanCurrent == null) {
    return false;
  }

  final maxLen = cleanRemote.length > cleanCurrent.length
      ? cleanRemote.length
      : cleanCurrent.length;

  for (var i = 0; i < maxLen; i++) {
    final r = i < cleanRemote.length ? cleanRemote[i] : 0;
    final c = i < cleanCurrent.length ? cleanCurrent[i] : 0;
    if (r > c) return true;
    if (r < c) return false;
  }
  return false;
}

/// 解析版本号字符串为整型列表（例如 `v1.2.3` -> `[1, 2, 3]`）。
List<int>? cleanVersionParts(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('v') || s.startsWith('V')) {
    s = s.substring(1).trim();
  }
  if (s.contains('+')) {
    s = s.split('+').first.trim();
  }
  if (s.contains('-')) {
    s = s.split('-').first.trim();
  }
  if (s.isEmpty) return null;

  final parts = s.split('.');
  if (parts.isEmpty) return null;

  final nums = <int>[];
  for (final part in parts) {
    final n = int.tryParse(part.trim());
    if (n == null) return null;
    nums.add(n);
  }
  while (nums.length < 3) {
    nums.add(0);
  }
  return nums;
}
