import 'package:flutter/cupertino.dart';

import '../../app/theme/light_surfaces.dart';
import '../../l10n/app_localizations.dart';
import 'download_models.dart';
import 'download_page.dart';

/// 弹出 Cupertino 下载确认对话框。
///
/// 展示：文件名、文件分类、文件大小（或未知大小）、修改时间（若有）。
/// 返回 true 表示用户确认开始下载，返回 false 或 null 表示取消。
Future<bool?> showDownloadConfirmationDialog(
  BuildContext context, {
  required String fileName,
  String? mimeType,
  int? expectedBytes,
  String? sessionId,
  double? modifiedAtSeconds,
}) {
  final l10n = AppLocalizations.of(context);
  final fileType = getDownloadFileType(fileName: fileName, mimeType: mimeType);
  final typeName = localizeDownloadFileType(fileType, l10n);
  final sizeText = expectedBytes != null && expectedBytes > 0
      ? formatDownloadByteSize(expectedBytes)
      : l10n.downloadUnknownSize;
  String? modifiedTimeText;
  if (modifiedAtSeconds != null) {
    final dt = DateTime.fromMillisecondsSinceEpoch(
      (modifiedAtSeconds * 1000).round(),
    );
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    modifiedTimeText = '$y-$m-$d $hh:$mm';
  }

  return showCupertinoDialog<bool>(
    context: context,
    builder: (dialogCtx) => CupertinoAlertDialog(
      title: Text(l10n.downloadConfirmTitle),
      content: Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${l10n.name}：$fileName'),
            const SizedBox(height: 4),
            Text('${l10n.info}：$typeName'),
            const SizedBox(height: 4),
            Text('${l10n.value}：$sizeText'),
            if (modifiedTimeText != null) ...[
              const SizedBox(height: 4),
              Text('${l10n.downloadModifiedTime}：$modifiedTimeText'),
            ],
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          child: Text(
            l10n.downloadConfirmCancel,
            style: CupertinoTheme.brightnessOf(dialogCtx) == Brightness.light
                ? const TextStyle(color: LightSurfaces.menuAction)
                : null,
          ),
          onPressed: () => Navigator.of(dialogCtx).pop(false),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          child: Text(
            l10n.downloadConfirmStart,
            style: CupertinoTheme.brightnessOf(dialogCtx) == Brightness.light
                ? const TextStyle(color: LightSurfaces.menuAction)
                : null,
          ),
          onPressed: () => Navigator.of(dialogCtx).pop(true),
        ),
      ],
    ),
  );
}
