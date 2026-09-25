/// 服务端注入标记的统一剥离。
///
/// 同一份实现供两处复用，避免正则漂移：
/// 1. `chat_diff_merge` 的用户消息归一化比对（去重）；
/// 2. 会话标题显示净化（服务端标题可能把 `[Attached files: …]` 也算进标题词）。
library;

/// 剥离服务端注入标记并归一化文本。
///
/// 处理四类：
/// - `[Workspace::v1: …]` 首行（宽容转义反斜杠路径与任意后缀）
/// - `[Attached files: …]` 段
/// - 行级占位符 `[screenshot]` / `[image]` / `[attachment]`（整行精确匹配才删，防误伤正文）
/// - Hermes 结构化内容前缀 `\x00json:`（仅剥前缀标记，负载由调用方解码）
String stripInjectionMarkers(String raw) {
  var text = raw;

  // 0. 结构化前缀标记（若上游未解码，至少不把 NUL 前缀显示给用户）
  const structuredPrefix = '\u0000json:';
  if (text.startsWith(structuredPrefix)) {
    text = text.substring(structuredPrefix.length);
  }

  // 1. 剥离 ^[Workspace::v1: ...] 行（可能带前导换行；容忍转义反斜杠路径与任意后缀）
  text = text.replaceAll(
    RegExp(
      r'^[^\S\r\n]*\[Workspace::v1:[ \t]*[^\]]*\][^\S\r\n]*(?:\r?\n|$)',
      multiLine: true,
      caseSensitive: false,
    ),
    '',
  );

  // 2. 剥离 [Attached files: ...] 段
  text = text.replaceAll(
    RegExp(r'\[Attached files:[ \t]*[^\]]*\]', caseSensitive: false),
    '',
  );

  // 3. 剥离行级占位符 [screenshot]、[image]、[attachment]（整行精确匹配才删）
  text = text.replaceAll(
    RegExp(
      r'^[^\S\r\n]*\[(screenshot|image|attachment)\][^\S\r\n]*(?:\r?\n|$)',
      multiLine: true,
      caseSensitive: false,
    ),
    '',
  );

  return text.trim();
}

/// 会话标题净化：剥离注入标记后压平空白，超长截断。
///
/// 服务端标题取自首条消息文本，因此可能带 `[Attached files: …]` 之类的标记
/// （实测出现「bug 1000 Attached files」这种标题）。显示前必须净化。
String sanitizeSessionTitle(String raw, {int maxLength = 120}) {
  final stripped = stripInjectionMarkers(raw);
  if (stripped.isEmpty) return '';
  // 标题是单行展示：把换行压成空格，合并连续空白
  var flat = stripped.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.length > maxLength) {
    flat = '${flat.substring(0, maxLength).trimRight()}…';
  }
  return flat;
}
