import 'package:flutter/cupertino.dart';

import '../../../app/theme/typography_tokens.dart';
import '../../../core/models/message_attachment.dart';
import '../../../l10n/app_localizations.dart';
import 'chat_media_parser.dart';
import 'chat_media_view.dart';

/// 用户气泡内附件区的排布档位。
///
/// **临时开关（设计稿对比用）**：由 `--dart-define=ATTACH_LAYOUT=<n>` 选择，
/// 定稿后删掉开关与本注释，只留胜出档。
///
/// - 0 = 旧观感：逐条「内联预览 + 深蓝文件名芯片」堆叠（对照用）；
/// - 1 = 图片宫格贴右（固定 108 瓦片 + 文件行条）；
/// - 2 = 图片宫格铺满气泡宽（瓦片按可用宽反算，clamp 84–240）；
/// - 3 = 紧凑行条（40 方图 + 文件名 + 大小，每项一行）。
const int kUserAttachmentLayout = int.fromEnvironment(
  'ATTACH_LAYOUT',
  defaultValue: 1,
);

/// 宫格瓦片间距。
const double _kGridGap = 4.0;

/// 宫格瓦片圆角（气泡圆角 16 内缩一档）。
const double _kTileRadius = 12.0;

/// 贴右档固定瓦片边长；铺满档的上下限。
const double _kTileFixed = 108.0;
const double _kTileFillMin = 84.0;
const double _kTileFillMax = 240.0;

/// 单图档的 contain 上限（不裁切，按原比例）。
const double _kSingleMaxWidth = 200.0;
const double _kSingleMaxHeight = 150.0;

/// 行条档的方形缩略图边长。
const double _kRowThumb = 40.0;

/// 文件行条的圆角。
const double _kRowRadius = 10.0;

/// 用户消息附件区（图片宫格 + 文件行条）。
///
/// 取代原先「每个附件一条 `ChatAttachmentChipView`」的竖排堆叠：文件名芯片
/// 既占高度、又把图片压在下面看不见，深蓝内嵌块叠在蓝气泡上还留 0.5px
/// 页面描边（`LightSurfaces.cardBorder`），是「气泡又空又脏」的主因。
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

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    switch (kUserAttachmentLayout) {
      case 0:
        return _legacyStack(context);
      case 3:
        return _compactRows(context);
      case 2:
        return _grid(context, fill: true);
      case 1:
      default:
        return _grid(context, fill: false);
    }
  }

  // ── 档 0：旧观感（对照用，定稿后连同 ChatAttachmentChipView 的用户态一起删） ──
  Widget _legacyStack(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final attachment in attachments)
          ChatAttachmentChipView(
            attachment: attachment,
            baseUrl: baseUrl,
            sessionId: sessionId,
            isUserMessage: true,
          ),
      ],
    );
  }

  // ── 档 1 / 档 2：图片宫格 + 文件行条 ──
  Widget _grid(BuildContext context, {required bool fill}) {
    final images = [
      for (final attachment in attachments)
        if (_isImage(attachment)) attachment,
    ];
    final files = [
      for (final attachment in attachments)
        if (!_isImage(attachment)) attachment,
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
                child: _imageGrid(
                  context,
                  images,
                  available: available,
                  fill: fill,
                ),
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
    required double available,
    required bool fill,
  }) {
    if (images.length == 1) {
      return _imageTile(
        context,
        images.single,
        width: _kSingleMaxWidth,
        height: _kSingleMaxHeight,
        fit: BoxFit.contain,
      );
    }
    final columns = _columnsFor(images.length);
    var tile = _kTileFixed;
    if (fill && available.isFinite && available > 0) {
      final raw = (available - _kGridGap * (columns - 1)) / columns;
      tile = raw.clamp(_kTileFillMin, _kTileFillMax);
    }
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: _kGridGap,
      runSpacing: _kGridGap,
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

  /// 一张图占几列：2 张两列、4 张 2×2，其余按 3 列（3 / 5 / 6…）。
  int _columnsFor(int count) {
    if (count <= 2) return count;
    if (count == 4) return 2;
    return 3;
  }

  Widget _imageTile(
    BuildContext context,
    MessageAttachment attachment, {
    required double width,
    required double height,
    required BoxFit fit,
  }) {
    return SizedBox(
      // 稳定测试锚点（与排布档位无关）：点它 = 打开大图预览。
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
        borderRadius: BorderRadius.circular(_kTileRadius),
      ),
    );
  }

  // ── 文件行条：图标 + 文件名 + 大小（整行铺满，避免气泡留一片空蓝） ──
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
          borderRadius: BorderRadius.circular(_kRowRadius),
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

  // ── 档 3：紧凑行条（图片也走方形缩略图 + 文件名，信息最全、最省高度） ──
  Widget _compactRows(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < attachments.length; index++) ...[
          if (index > 0) const SizedBox(height: 4),
          _compactRow(context, attachments[index]),
        ],
      ],
    );
  }

  Widget _compactRow(BuildContext context, MessageAttachment attachment) {
    final name = _displayName(context, attachment);
    final size = _sizeLabel(attachment.size);
    final isImage = _isImage(attachment);
    final identity = _identityOf(attachment);
    return GestureDetector(
      key: ValueKey(
        isImage
            ? 'user-attachment-image-$identity'
            : 'user-attachment-file-$identity',
      ),
      behavior: HitTestBehavior.opaque,
      onTap: () => _openPreview(context, attachment),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: _surfaceFill,
          borderRadius: BorderRadius.circular(_kRowRadius),
        ),
        child: Row(
          children: [
            SizedBox(
              width: _kRowThumb,
              height: _kRowThumb,
              child: isImage
                  ? ChatInlineMediaWidget(
                      rawUri: _reference(attachment),
                      title: name,
                      alt: name,
                      baseUrl: baseUrl,
                      sessionId: sessionId,
                      maxWidth: _kRowThumb,
                      maxHeight: _kRowThumb,
                      fit: BoxFit.cover,
                      padding: EdgeInsets.zero,
                      borderRadius: BorderRadius.circular(8),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: CupertinoColors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _iconFor(attachment),
                        size: 16,
                        color: CupertinoColors.white,
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: kFontCaption,
                      color: CupertinoColors.white,
                    ),
                  ),
                  if (size != null) ...[
                    const SizedBox(height: 1),
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
          ],
        ),
      ),
    );
  }

  // ── 共用 ──

  /// 气泡内附件底：半透明白（明暗两态同款，取代浅色下那个深蓝内嵌块 + 发丝描边）。
  Color get _surfaceFill => CupertinoColors.white.withValues(alpha: 0.18);

  bool _isImage(MessageAttachment attachment) {
    if (attachment.isImage == true) return true;
    final reference = _reference(attachment);
    if (reference.isEmpty) return false;
    return MessageAttachment.mediaKindForName(reference) ==
        MessageMediaKind.image;
  }

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
      isImage: _isImage(attachment),
      sessionId: sessionId,
      expectedBytes: attachment.size,
      mimeType: attachment.mime,
    );
  }
}
