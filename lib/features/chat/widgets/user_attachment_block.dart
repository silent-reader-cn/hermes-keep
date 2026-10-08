import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../../app/theme/typography_tokens.dart';
import '../../../core/models/message_attachment.dart';
import '../../../l10n/app_localizations.dart';
import 'chat_media_parser.dart';
import 'chat_media_view.dart';

/// 用户气泡附件区（**主人 2026-10-07 定稿；2026-10-08 多图档 4 定稿**）。
///
/// - **图片（多张）**：单行等高（justified gallery）—— 行内每张等高、宽按各自
///   宽高比分配、**不裁切**、**不留白**，整行填满气泡可用宽。分行规则、行高上下限
///   与「未解码时的稳定占位」见 [justifiedRows]、[kJustifiedMinRowHeight]、
///   [kJustifiedMaxRowHeight]。
/// - **图片（单张）**：contain 大图（≤ [singleImageMaxWidth] ×
///   [singleImageMaxHeight]），维持原行为不动。
/// - **非图片**（pdf / zip / 其它）：整行条 —— 类型图标 + 文件名 + 大小，
///   半透明白底（圆角 10），**不带**页面发丝描边（旧实现把 `cardBorder` 画进
///   蓝气泡里，是「脏」的主因之一）。
/// - **气泡贴合**：带图消息的气泡宽度收到「附件区宽 + 内边距」，并夹在
///   [minBubbleWidth] 与 `[bubbleMaxWidthRatio] × 槽宽` 之间，见
///   [preferredBubbleWidth]（其下限永不超过上限）。
///
/// 为什么不再用 96×96 方瓦片：非方图被 `cover` 裁成正方形后，同一行的瓦片
/// 尺寸一致但内容被切掉，不同比例的消息观感「参差不齐」（主人 2026-10-07 报告）。
/// justified 版本按真实宽高比分宽：一行内高度相同、宽度按比例分，既不裁切也不
/// 留白，整行严丝合缝填满气泡可用宽；只在「行高超过上限」时收高并整行居中。
class UserAttachmentBlock extends StatefulWidget {
  const UserAttachmentBlock({
    super.key,
    required this.attachments,
    this.baseUrl,
    this.sessionId,
  });

  final List<MessageAttachment> attachments;
  final String? baseUrl;
  final String? sessionId;

  /// 宫格瓦片边长（定稿 96）。仅用于「可用宽不可用」的兜底方阵与
  /// [preferredBubbleWidth] 的宽度算式；justified 行内瓦片按比例算宽。
  static const double tileSize = 96.0;

  /// 瓦片间距（同行内 / 行与行之间同值）。
  static const double tileGap = 4.0;

  /// 单图的 contain 上限（不裁切，按原比例）。
  static const double singleImageMaxWidth = 200.0;
  static const double singleImageMaxHeight = 150.0;

  /// 气泡左右内边距合计（贴合算式用；= 气泡 padding 12×2）。
  static const double bubbleHorizontalPadding = 24.0;

  /// 带图气泡的最小宽度：避免「附件少 ⇒ 气泡被收得太窄、正文一字一行」。
  static const double minBubbleWidth = 300.0;

  /// 气泡宽度占可用槽宽的比例上限（与纯文本气泡同一口径）。
  static const double bubbleMaxWidthRatio = 0.78;

  /// justified 行高**下限（贪心分行的触发阈值）**。
  ///
  /// 口径：往当前行再加一张会让「行高 = 可用宽 / 该行 Σ比例」掉到本值以下时，
  /// 就把这一张**收进当前行**再封行（相册的常见做法：越线的那张留在行里，
  /// 而不是丢给下一行单独成行 —— 后者会多出一条只有一张的矮行）。
  ///
  /// 取值依据（截图工装实测，[tileGap] 4、多图气泡可用宽 296）：
  /// - 6 张 4:3 若全挤一行，行高只有 ≈34.5 —— 本阈值把它切成两行 ×3 张、行高 72；
  /// - 3 张混比例（竖 3:4 + 横 4:3 + 超宽 16:9）整行自然行高 ≈74.6 —— 必须**小于**
  ///   本值才会与主人拍板的档 4 参考图一致（保持单行）。故取 80 是「够高到拦住
  ///   塌陷、又低到不拆散正常混排」的档位；要更紧凑/更宽松直接调这里。
  static const double kJustifiedMinRowHeight = 80.0;

  /// justified 行高**上限**：超过则收到本值，整行按比例缩到小于可用宽并**居中**
  /// （宁可两边留一点，也绝不把宽图拉变形）。单张竖图/超宽图单独成行时常见。
  static const double kJustifiedMaxRowHeight = 200.0;

  /// 带图消息的气泡宽度；没有图片附件 → null（交给原逻辑）。
  ///
  /// 不变量：`min(floor, cap) ≤ 结果 ≤ cap`，其中
  /// `cap = availableWidth × [bubbleMaxWidthRatio]`、
  /// `floor = min([minBubbleWidth], cap)` —— 即**下限永不超过上限**
  /// （窄屏槽宽不足时，下限自动退到上限，不会撑出可用宽）。
  static double? preferredBubbleWidth(
    List<MessageAttachment>? attachments,
    double availableWidth,
  ) {
    final gridWidth = _gridWidth(attachments);
    if (gridWidth == null) return null;
    if (!availableWidth.isFinite || availableWidth <= 0) return null;
    final cap = availableWidth * bubbleMaxWidthRatio;
    final floor = math.min(minBubbleWidth, cap);
    final preferred = gridWidth + bubbleHorizontalPadding;
    if (preferred >= cap) return cap;
    if (preferred <= floor) return floor;
    return preferred;
  }

  /// 附件区（图片宫格）需要的宽度；无图片 → null。
  ///
  /// 注意：这是**气泡贴合**用的宽度，与 justified 行内瓦片宽无关 ——
  /// 保持原算式不动，`user_attachment_bubble_width_test.dart` /
  /// `chat_bubble_overflow_test.dart` 钉的就是它。
  static double? _gridWidth(List<MessageAttachment>? attachments) {
    if (attachments == null || attachments.isEmpty) return null;
    final images = [
      for (final attachment in attachments)
        if (_isImageAttachment(attachment)) attachment,
    ];
    if (images.isEmpty) return null;
    if (images.length == 1) return singleImageMaxWidth;
    final columns = _columnsFor(images.length);
    return columns * tileSize + tileGap * (columns - 1);
  }

  /// 一张图占几列（**只服务于气泡贴合宽度算式**，不再决定宫格排布）。
  static int _columnsFor(int count) {
    if (count <= 2) return count;
    if (count == 4) return 2;
    return 3;
  }

  static bool _isImageAttachment(MessageAttachment attachment) {
    if (attachment.isImage == true) return true;
    final reference = (attachment.path ?? attachment.name ?? '').trim();
    if (reference.isEmpty) return false;
    return MessageAttachment.mediaKindForName(reference) ==
        MessageMediaKind.image;
  }

  /// 纯函数：把一行行「填满」[available]，返回**每行、从左到右**的瓦片宽度。
  ///
  /// 算法（justified gallery）：
  /// 1. 贪心累积同行的比例和 `Σr`，候选行高 `h = (available − gap×(n−1)) / Σr`；
  /// 2. 若把下一张收进来会让 `h` 掉到 [minRowHeight] 以下 —— **收进来并就此封行**
  ///    （越线那张留在行里，避免多出一条单张矮行）；另有一行最多张数上限
  ///    `⌊available / gap⌋ + 1`（保证 `gap×(n−1) ≤ available`，行高不会算成负的）；
  ///    **末行孤张规避**：若按此封行会让下一行只剩一张，就退掉刚收进来的那张
  ///    （把两张留给下一行）—— 否则那张会独占一行、行高被顶到 [maxRowHeight]，
  ///    块高反而比旧宫格还高，观感又回到「一大一小、参差」（实测 4 张混比例：
  ///    不退 ⇒ 3 张 74.6 + 孤张 200、块高 279；退一张 ⇒ 2+2、行高 140/105、
  ///    两行都填满、块高 249）。
  /// 3. 封行时 `h = min(自然行高, maxRowHeight)`；每张宽 = `h × 该张比例`；
  /// 4. 防溢出兜底：浮点误差或病态比例导致行宽 > available 时，按比例压回
  ///    `available − gap×(n−1)` 以内（**任何输入都不产生溢出/NaN/负宽**）。
  ///
  /// 不裁切、不留白的原理：行内所有瓦片共用行高 `h`，每张宽恰好 `h × (w/h)源`
  /// ⇒ 瓦片盒子的宽高比 == 源图宽高比 ⇒ `BoxFit.cover` 与 `contain` 等价，
  /// 既不裁掉像素，也不留背景边。行宽（含间距）恰等于 `available`（未收高时）
  /// ⇒ 整行填满气泡，不留白。
  ///
  /// 未就绪占位：调用方在「固有尺寸还没解码出来」时传 1.0（比例未知），
  /// 得到的是**整行铺满、行高稳定**的方阵排布 —— 首帧不会塌成 0 宽再弹开。
  static List<List<double>> justifiedRows(
    List<double> ratios, {
    required double available,
    double gap = tileGap,
    double minRowHeight = kJustifiedMinRowHeight,
    double maxRowHeight = kJustifiedMaxRowHeight,
  }) {
    if (ratios.isEmpty) return const <List<double>>[];
    assert(
      available.isFinite && available > 0,
      'justifiedRows 需要有限且为正的可用宽（调用方负责兜底）',
    );
    if (available <= 0 || !available.isFinite) return const <List<double>>[];

    // 病态比例（非有限 / ≤0）退回 1.0：宁可当方形，也不产生 NaN 宽。
    final safe = <double>[
      for (final ratio in ratios) (ratio.isFinite && ratio > 0) ? ratio : 1.0,
    ];

    final rows = <List<double>>[];
    // 一行最多放几张：`gap×(n−1) ≤ available` 是「行高非负」的必要条件
    // （可用宽比间距还小时，只能一张一行 —— 否则算出的行高为负）。
    final maxPerRow = gap > 0 ? (available / gap).floor() + 1 : safe.length;
    var start = 0;
    while (start < safe.length) {
      var end = start;
      var sum = safe[start];
      while (end + 1 < safe.length && (end + 1 - start + 1) <= maxPerRow) {
        final nextSum = sum + safe[end + 1];
        final count = end + 1 - start + 1;
        final candidateHeight = (available - gap * (count - 1)) / nextSum;
        end += 1;
        sum = nextSum;
        // 越过下限：收进当前行并封行。
        if (candidateHeight < minRowHeight) {
          // 末行孤张规避（见 docstep 2）：退掉刚收进来的这张，把两张留给下一行。
          if (safe.length - (end + 1) == 1 && end - 1 >= start) {
            sum -= safe[end];
            end -= 1;
          }
          break;
        }
      }
      final count = end - start + 1;
      final gaps = gap * (count - 1);
      var height = (available - gaps) / sum;
      if (height > maxRowHeight) height = maxRowHeight;
      if (height < 0) height = 0;

      final widths = <double>[
        for (var i = start; i <= end; i++) height * safe[i],
      ];

      // 防溢出：浮点误差 / 收高后仍越界时按比例压回可用宽内。
      final used =
          widths.fold<double>(0, (total, width) => total + width) + gaps;
      if (used > available && used - gaps > 0) {
        final scale = (available - gaps) / (used - gaps);
        for (var i = 0; i < widths.length; i++) {
          widths[i] *= scale;
        }
      }
      rows.add(widths);
      start = end + 1;
    }
    return rows;
  }

  @override
  State<UserAttachmentBlock> createState() => _UserAttachmentBlockState();
}

class _UserAttachmentBlockState extends State<UserAttachmentBlock> {
  /// 每张图的真实宽高比（key = 附件身份串，见 [_identityOf]）。
  ///
  /// **重排时机**：首帧这里通常是空的 —— `Image` 没解码完拿不到固有尺寸，
  /// 于是 [_ratioOf] 回落到 1.0 的**稳定占位比例**（整行照铺满，尺寸非 0，
  /// 不会「塌一下再弹开」）。等到 `ImageStream` 出帧，[ChatInlineMediaWidget]
  /// 通过 `onIntrinsicSize` 回调把「宽×高（像素）」报上来，本 State `setState`
  /// 重排一次 —— 此时行内宽高比才切到真值（相册里的最终形态）。
  final Map<String, double> _ratios = <String, double>{};

  void _onIntrinsicSize(String identity, Size size) {
    if (!mounted) return;
    if (!size.width.isFinite || !size.height.isFinite) return;
    if (size.width <= 0 || size.height <= 0) return;
    final ratio = size.width / size.height;
    if (_ratios[identity] == ratio) return;
    setState(() => _ratios[identity] = ratio);
  }

  double _ratioOf(MessageAttachment attachment) =>
      _ratios[_identityOf(attachment)] ?? 1.0;

  @override
  Widget build(BuildContext context) {
    final attachments = widget.attachments;
    if (attachments.isEmpty) return const SizedBox.shrink();
    final images = [
      for (final attachment in attachments)
        if (UserAttachmentBlock._isImageAttachment(attachment)) attachment,
    ];
    final files = [
      for (final attachment in attachments)
        if (!UserAttachmentBlock._isImageAttachment(attachment)) attachment,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (images.isNotEmpty)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _imageGrid(context, images, available: available),
              ),
            if (images.isNotEmpty && files.isNotEmpty)
              const SizedBox(height: 6),
            for (var index = 0; index < files.length; index++) ...[
              if (index > 0) const SizedBox(height: 4),
              _fileRow(context, files[index]),
            ],
          ],
        );
      },
    );
  }

  Widget _imageGrid(
    BuildContext context,
    List<MessageAttachment> images, {
    required double available,
  }) {
    // 单图例外：contain 大图（原行为，不动）。
    if (images.length == 1) {
      return _imageTile(
        context,
        images.single,
        width: UserAttachmentBlock.singleImageMaxWidth,
        height: UserAttachmentBlock.singleImageMaxHeight,
        fit: BoxFit.contain,
      );
    }

    // 可用宽不可用（无界/为 0）：退回定宽方阵 —— 只在病态约束下触发，保证不崩。
    if (!available.isFinite || available <= 0) {
      return Wrap(
        alignment: WrapAlignment.end,
        spacing: UserAttachmentBlock.tileGap,
        runSpacing: UserAttachmentBlock.tileGap,
        children: [
          for (final attachment in images)
            _imageTile(
              context,
              attachment,
              width: UserAttachmentBlock.tileSize,
              height: UserAttachmentBlock.tileSize,
              fit: BoxFit.cover,
            ),
        ],
      );
    }

    final ratios = [for (final attachment in images) _ratioOf(attachment)];
    final rows = UserAttachmentBlock.justifiedRows(
      ratios,
      available: available,
    );

    final rowWidgets = <Widget>[];
    var index = 0;
    for (var r = 0; r < rows.length; r++) {
      final widths = rows[r];
      final rowImages = images.sublist(index, index + widths.length);
      final rowRatios = ratios.sublist(index, index + widths.length);
      index += widths.length;
      if (r > 0) {
        rowWidgets.add(const SizedBox(height: UserAttachmentBlock.tileGap));
      }
      rowWidgets.add(
        _justifiedRow(
          context,
          rowImages,
          widths: widths,
          ratios: rowRatios,
          available: available,
        ),
      );
    }

    // 固定钉成「气泡可用宽」：整行铺满时对齐无差别；被上限收高的窄行在
    // crossAxisAlignment.center 下整行居中（宁可两边各留一点）。
    return SizedBox(
      width: available,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: rowWidgets,
      ),
    );
  }

  /// 一行 justified 瓦片：行高 = 宽 / 比例（行内各张同高），宽度已由
  /// [UserAttachmentBlock.justifiedRows] 按比例算好。
  Widget _justifiedRow(
    BuildContext context,
    List<MessageAttachment> rowImages, {
    required List<double> widths,
    required List<double> ratios,
    required double available,
  }) {
    final height = widths.first / ratios.first;
    final children = <Widget>[];
    for (var i = 0; i < rowImages.length; i++) {
      if (i > 0) {
        children.add(const SizedBox(width: UserAttachmentBlock.tileGap));
      }
      children.add(
        _imageTile(
          context,
          rowImages[i],
          width: widths[i],
          height: height,
          fit: BoxFit.cover,
        ),
      );
    }
    // mainAxisSize.min + 外层 center：铺满时宽度 == available（看不出对齐），
    // 收高变窄时整行居中。
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  /// 宫格瓦片圆角（气泡圆角 16 内缩一档）。
  static const double _tileRadius = 12.0;

  /// 文件行条圆角。
  static const double _fileRadius = 10.0;

  Widget _imageTile(
    BuildContext context,
    MessageAttachment attachment, {
    required double width,
    required double height,
    required BoxFit fit,
  }) {
    final identity = _identityOf(attachment);
    return SizedBox(
      // 稳定测试锚点：点它 = 打开大图预览。
      key: ValueKey('user-attachment-image-$identity'),
      width: width,
      height: height,
      child: ChatInlineMediaWidget(
        rawUri: _reference(attachment),
        title: attachment.name,
        alt: attachment.name,
        baseUrl: widget.baseUrl,
        sessionId: widget.sessionId,
        maxWidth: width,
        maxHeight: height,
        fit: fit,
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(_tileRadius),
        // 固有尺寸就绪 → 回报真实宽高比 → 本 State 重排一次。
        onIntrinsicSize: (size) => _onIntrinsicSize(identity, size),
      ),
    );
  }

  /// 文件行条：图标 + 文件名 + 大小（整行铺满，避免气泡再留一条空蓝）。
  Widget _fileRow(BuildContext context, MessageAttachment attachment) {
    final name = _displayName(context, attachment);
    final size = _sizeLabel(attachment.size);
    return GestureDetector(
      // 稳定测试锚点：点它 = 打开附件预览页（含下载入口）。
      key: ValueKey('user-attachment-file-${_identityOf(attachment)}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _openPreview(context, attachment),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _surfaceFill,
          borderRadius: BorderRadius.circular(_fileRadius),
        ),
        child: Row(
          children: [
            Icon(_iconFor(attachment), size: 14, color: CupertinoColors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: kFontCaption,
                  color: CupertinoColors.white,
                ),
              ),
            ),
            if (size != null) ...[
              const SizedBox(width: 8),
              Text(
                size,
                style: TextStyle(
                  fontSize: kFontMicro,
                  color: CupertinoColors.white.withValues(alpha: 0.72),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 气泡内附件底：半透明白（明暗两态同款，取代浅色下那个深蓝内嵌块）。
  Color get _surfaceFill => CupertinoColors.white.withValues(alpha: 0.18);

  String _reference(MessageAttachment attachment) =>
      (attachment.path ?? attachment.name ?? '').trim();

  /// 稳定身份串（basename 小写），用于测试锚点与跨表示匹配。
  String _identityOf(MessageAttachment attachment) =>
      attachment.identityKey ??
      _reference(attachment).replaceAll('\\', '/').split('/').last;

  String _displayName(BuildContext context, MessageAttachment attachment) {
    final name = attachment.name?.trim();
    if (name != null && name.isNotEmpty) return name;
    final reference = _reference(attachment);
    if (reference.isEmpty) {
      return AppLocalizations.of(context).attachmentFallback;
    }
    final parts = reference.split(RegExp(r'[/\\]'));
    return parts.isEmpty || parts.last.isEmpty ? reference : parts.last;
  }

  IconData _iconFor(MessageAttachment attachment) {
    switch (MessageAttachment.mediaKindForName(_reference(attachment))) {
      case MessageMediaKind.image:
        return CupertinoIcons.photo;
      case MessageMediaKind.audio:
        return CupertinoIcons.music_note;
      case MessageMediaKind.video:
        return CupertinoIcons.film;
      case MessageMediaKind.document:
        return CupertinoIcons.doc_text;
      case MessageMediaKind.file:
        return CupertinoIcons.paperclip;
    }
  }

  /// 大小标签（无 size 数据 → null，不占位）。
  String? _sizeLabel(int? bytes) {
    if (bytes == null || bytes <= 0) return null;
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final text = unit == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$text ${units[unit]}';
  }

  void _openPreview(BuildContext context, MessageAttachment attachment) {
    final name = _displayName(context, attachment);
    final reference = _reference(attachment);
    final resolvedUrl = reference.isEmpty
        ? ''
        : ChatMediaResolver.resolveMediaUrl(
            reference,
            baseUrl: widget.baseUrl,
            sessionId: widget.sessionId,
          );
    showAttachmentPreview(
      context,
      resolvedUrl: resolvedUrl.isNotEmpty ? resolvedUrl : null,
      name: name,
      altText: name,
      isImage: UserAttachmentBlock._isImageAttachment(attachment),
      sessionId: widget.sessionId,
      expectedBytes: attachment.size,
      mimeType: attachment.mime,
    );
  }
}
