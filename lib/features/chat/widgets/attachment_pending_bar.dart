import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/light_surfaces.dart';
import '../../../core/models/upload_response.dart';
import '../../../l10n/app_localizations.dart';
import '../pending_attachments_provider.dart';
import 'chat_media_view.dart';

/// 待发附件横条面板（需求：粘贴/上传不进流、不直接发送）。
///
/// 消费 [pendingAttachmentsProvider(sessionId)]，横向排布缩略图，
/// 空时隐藏；支持单项删除与全部清空，点发送才随消息一并提交。
class AttachmentPendingBar extends ConsumerWidget {
  const AttachmentPendingBar({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final attachments = ref.watch(pendingAttachmentsProvider(sessionId));
    if (attachments.isEmpty) return const SizedBox.shrink();

    final secondary = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (attachments.length > 1)
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                key: const ValueKey('attachment-clear-all'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                minimumSize: Size.zero,
                onPressed: () => ref
                    .read(pendingAttachmentsProvider(sessionId).notifier)
                    .clear(),
                child: Text(
                  l10n.clear,
                  style: TextStyle(fontSize: 12, color: secondary),
                ),
              ),
            ),
          SizedBox(
            height: 62,
            child: ListView.separated(
              key: const ValueKey('attachment-pending-list'),
              scrollDirection: Axis.horizontal,
              itemCount: attachments.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => _AttachmentThumb(
                attachment: attachments[index],
                onRemove: () => ref
                    .read(pendingAttachmentsProvider(sessionId).notifier)
                    .remove(attachments[index].id),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentThumb extends StatelessWidget {
  const _AttachmentThumb({required this.attachment, required this.onRemove});

  final PendingAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final secondary = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: CupertinoColors.secondaryLabel,
    );
    final separator = LightSurfaces.resolve(
      context,
      LightSurfaces.cardBorder,
      dark: CupertinoColors.separator,
    );
    final bg = LightSurfaces.resolve(
      context,
      LightSurfaces.card,
      dark: CupertinoColors.secondarySystemBackground,
    );
    final preview = attachment.thumbnailData;

    return Container(
      width: 132,
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: separator),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: 'Preview ${attachment.name}',
              child: GestureDetector(
                key: ValueKey('attachment-preview-${attachment.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => showAttachmentPreview(
                  context,
                  bytes: attachment.thumbnailData,
                  name: attachment.name,
                  isImage:
                      attachment.isImage && attachment.thumbnailData != null,
                  resolvedUrl: attachment.path.isNotEmpty
                      ? attachment.path
                      : null,
                ),
                child: Row(
                  children: [
                    if (attachment.isImage && preview != null)
                      Padding(
                        padding: const EdgeInsets.all(5),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(
                            preview,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            cacheWidth: 132,
                            gaplessPlayback: true,
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(left: 10, right: 6),
                        child: Icon(
                          CupertinoIcons.doc,
                          size: 22,
                          color: LightSurfaces.resolve(
                            context,
                            LightSurfaces.textSecondary,
                            dark: CupertinoColors.systemGrey,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          attachment.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, height: 1.3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Remove attachment: ${attachment.name}',
            child: CupertinoButton(
              key: ValueKey('attachment-remove-${attachment.id}'),
              padding: const EdgeInsets.all(6),
              minimumSize: const Size(28, 28),
              onPressed: onRemove,
              child: Icon(CupertinoIcons.xmark, size: 11, color: secondary),
            ),
          ),
        ],
      ),
    );
  }
}
