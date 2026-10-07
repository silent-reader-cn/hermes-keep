import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../../app/theme/typography_tokens.dart';
import '../../../core/models/message_attachment.dart';
import '../../../l10n/app_localizations.dart';
import 'chat_media_parser.dart';
import 'chat_media_view.dart';

/// 用户气泡附件区（**主人 2026-10-07 定稿**）。
///
/// - **图片**：宫格瓦片 —— 边长 [tileSize]（96）、圆角 12、间距 4、cover 裁切、
///   无描边；单图例外，走 contain 大图（≤ [singleImageMaxWidth] ×
///   [singleImageMaxHeight]）。
/// - **非图片**（pdf / zip / 其它）：整行条 —— 类型图标 + 文件名 + 大小，
///   半透明白底（圆角 10），**不带**页面发丝描边（旧实现把 `cardBorder` 画进
///   蓝气泡里，是「脏」的主因之一）。
/// - **气泡贴合**：带图消息的气泡宽度收到「附件区宽 + 内边距」，并夹在
///   [minBubbleWidth] 与 `[bubbleMaxWidthRatio] × 槽宽` 之间，见
///   [preferredBubbleWidth]（其下限永不超过上限）。
///
/// 取代原先「每个附件一条文件名芯片」的竖排堆叠：芯片既占高度、又把图片压在
/// 下面看不见，气泡宽时左侧还留一大片空蓝。
class UserAttachmentBlock extends StatelessWidget {
  const UserAttachmentBlock({
    super.key,
    required this.attachments,
    this.baseUrl,
    this.sessionId,
  });

  final List<MessageAttachment> attachments;
  final String? baseUrl;
  final String? sessionId;

  /// 宫格瓦片边长（定稿 96；窄屏/窄槽会自动缩小以免溢出）。
  static const double tileSize = 96.0;

  /// 瓦片间距。
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

  /// 一张图占几列：2 张两列、4 张 2×2，其余按 3 列（3 / 5 / 6…）。
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

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final images = [
      for (final attachment in attachments)
        if (_isImageAttachment(attachment)) attachment,
    ];
    final files = [
      for (final attachment in attachments)
        if (!_isImageAttachment(attachment)) attachment,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        // 瓦片定宽 96，但必须塞进当前可用宽（窄屏 / 窄槽不溢出）。
        final columns = images.length > 1 ? _columnsFor(images.length) : 1;
        final rawTile = available.isFinite && available > 0
            ? (available - tileGap * (columns - 1)) / columns
            : tileSize;
        final tile = rawTile < tileSize ? rawTile : tileSize;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (images.isNotEmpty)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _imageGrid(context, images, tile: tile),
              ),
            if (images.isNotEmpty && files.isNotEmpty) const SizedBox(height: 6),
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
    required double tile,
  }) {
    if (images.length == 1) {
      return _imageTile(
        context,
        images.single,
        width: singleImageMaxWidth,
        height: singleImageMaxHeight,
        fit: BoxFit.contain,
      );
    }
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: tileGap,
      runSpacing: tileGap,
      children: [
        for (final attachment in images)
          _imageTile(
            context,
            attachment,
            width: tile,
            height: tile,
            fit: BoxFit.cover,
          ),
      ],
    );
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
    return SizedBox(
      // 稳定测试锚点：点它 = 打开大图预览。
      key: ValueKey('user-attachment-image-${_identityOf(attachment)}'),
      width: width,
      height: height,
      child: ChatInlineMediaWidget(
        rawUri: _reference(attachment),
        title: attachment.name,
        alt: attachment.name,
        baseUrl: baseUrl,
        sessionId: sessionId,
        maxWidth: width,
        maxHeight: height,
        fit: fit,
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(_tileRadius),
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
            baseUrl: baseUrl,
            sessionId: sessionId,
          );
    showAttachmentPreview(
      context,
      resolvedUrl: resolvedUrl.isNotEmpty ? resolvedUrl : null,
      name: name,
      altText: name,
      isImage: _isImageAttachment(attachment),
      sessionId: sessionId,
      expectedBytes: attachment.size,
      mimeType: attachment.mime,
    );
  }
}
