import '../models/context_window_snapshot.dart';

/// 上下文窗口格式化（Swift `ContextWindowFormatter`）。纯客户端逻辑，无 JSON。
///
/// **无数据一律返回 `null`**（不再返回界面文案）：文案由调用方（UI 层）兜底
/// `l10n.unavailable`。历史缺陷：原先五处硬编码 `'Unavailable'` 英文，会直接漏进
/// 中文界面（主人真机截图「阈值 Unavailable」「费用 Unavailable」）；本类不收文案
/// 参数、也不产出任何自然语言，本地化责任完全在 UI 层。
class ContextWindowFormatter {
  const ContextWindowFormatter._();

  /// 紧凑指示：`27% context`；无数据 → null。
  static String? compactIndicator(ContextWindowSnapshot snapshot) {
    final used = snapshot.tokensUsed;
    final total = snapshot.contextLength;
    if (used == null || total == null || total <= 0) return null;
    final pct = (used / total * 100).truncate();
    return '$pct% context';
  }

  /// `formatTokens(used) / formatTokens(total)`；无数据 → null。
  static String? tokensLabel(ContextWindowSnapshot snapshot) {
    final used = snapshot.tokensUsed;
    final total = snapshot.contextLength;
    if (used == null || total == null) return null;
    return '${formatTokens(used)} / ${formatTokens(total)}';
  }

  /// 上下文窗口上限（宽屏头部「大数字」）；无数据 → null。
  static String? windowLabel(ContextWindowSnapshot snapshot) {
    final total = snapshot.contextLength;
    if (total == null) return null;
    return formatTokens(total);
  }

  /// 本轮输入 token；无数据 → null。
  static String? inputTokensLabel(ContextWindowSnapshot snapshot) {
    final tokens = snapshot.inputTokens;
    if (tokens == null) return null;
    return formatTokens(tokens);
  }

  /// 本轮输出 token；无数据 → null。
  static String? outputTokensLabel(ContextWindowSnapshot snapshot) {
    final tokens = snapshot.outputTokens;
    if (tokens == null) return null;
    return formatTokens(tokens);
  }

  /// 阈值：对齐 WebUI `Auto-compress at ${_fmtTokens(threshold)} (${pct}%)`
  /// 有 threshold + contextLength 时展示 `64.0K (50%)`，否则仅 token；无数据 → null。
  static String? thresholdLabel(ContextWindowSnapshot snapshot) {
    final threshold = snapshot.thresholdTokens;
    if (threshold == null || threshold <= 0) return null;
    final total = snapshot.contextLength;
    if (total == null || total <= 0) return formatTokens(threshold);
    final pct = (threshold / total * 100).round().clamp(0, 100);
    return '${formatTokens(threshold)} ($pct%)';
  }

  /// 估算费用；无数据 → null。
  static String? costLabel(ContextWindowSnapshot snapshot) {
    final cost = snapshot.estimatedCost;
    if (cost == null) return null;
    return formattedCost(cost);
  }

  /// 1_000_000 → `%.1fM`、1_000 → `%.1fK`，否则原数字。
  static String formatTokens(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return '$count';
  }

  /// `$%.4f`（对应 Swift `formattedCost`）。
  static String formattedCost(double cost) {
    return '\$${cost.toStringAsFixed(4)}';
  }
}
