import 'package:flutter/cupertino.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/widgets/hermes_dialog.dart';
import '../../l10n/app_localizations.dart';
import 'download_models.dart';
import 'download_page.dart';

/// 弹出下载确认对话框（**批 5A 样板**：D1 四档宽的「确认框 380」）。
///
/// 展示：文件名、文件分类、文件大小（或未知大小）、修改时间（若有）。
/// 返回 true 表示用户确认开始下载，返回 false 或 null 表示取消。
///
/// 形态：
/// - **窄屏（<900）逐像素不变** —— 仍走系统 `CupertinoAlertDialog`（宽度由系统
///   定），内容与动作与批 5A 之前逐字段相同；
/// - **宽屏（>=900）** —— 380 宽居中卡片（`HermesDialogKind.confirm`）+ 背景压暗，
///   不再出现「宽屏下 270 窄条弹窗」。
///
/// 两种形态共用同一份 title/content/actions（见 [showHermesDialog]），
/// 因此不存在「两套内容漂移」的可能。
Future<bool?> showDownloadConfirmationDialog(
  BuildContext context, {
  required String fileName,
  String? mimeType,
  int? expectedBytes,
  String? sessionId,
  double? modifiedAtSeconds,
}) {
  final l10n = AppLocalizations.of(context);
  final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
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

  // 浅色下动作文字取高对比度深蓝（`LightSurfaces.menuAction`），深色沿用原生。
  final TextStyle? actionStyle = isLight
      ? const TextStyle(color: LightSurfaces.menuAction)
      : null;

  return showHermesDialog<bool>(
    context,
    kind: HermesDialogKind.confirm,
    title: (_) => Text(l10n.downloadConfirmTitle),
    content: (_) => Padding(
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
      HermesDialogAction(
        builder: (_) => Text(l10n.downloadConfirmCancel, style: actionStyle),
        onPressed: (dialogContext) => Navigator.of(dialogContext).pop(false),
      ),
      HermesDialogAction(
        isDefaultAction: true,
        builder: (_) => Text(l10n.downloadConfirmStart, style: actionStyle),
        onPressed: (dialogContext) => Navigator.of(dialogContext).pop(true),
      ),
    ],
  );
}
