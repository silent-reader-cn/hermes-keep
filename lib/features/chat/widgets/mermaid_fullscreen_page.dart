library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
// ignore: depend_on_referenced_packages
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';

import '../../../app/theme/light_surfaces.dart';
import '../../../l10n/app_localizations.dart';

/// 全屏查看 Mermaid 图表页面。
class MermaidFullscreenPage extends StatelessWidget {
  const MermaidFullscreenPage({
    super.key,
    required this.source,
    required this.theme,
  });

  /// Mermaid 图表源码。
  final String source;

  /// 图表主题。
  final core.MermaidTheme theme;

  @override
  Widget build(BuildContext context) {
    final title = AppLocalizations.of(context).mermaidDiagramTitle;
    // 亮色走浅色面令牌页底（#F2F2F7，与全仓其余页面一致）；深色保留原
    // iOS 系统灰 #1C1C1E，逐字节不变。导航栏沿用同一底色的 80% 不透明版。
    final background = LightSurfaces.resolve(
      context,
      LightSurfaces.page,
      dark: const Color(0xFF1C1C1E),
    );

    return CupertinoPageScaffold(
      backgroundColor: background,
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
        backgroundColor: background.withAlpha(0xCC),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(CupertinoIcons.xmark),
        ),
      ),
      child: SafeArea(
        child: MermaidView(
          key: const ValueKey('mermaid-fullscreen-view'),
          source: source,
          theme: theme,
          showControls: true,
          allowFullscreen: false,
          backgroundColor: Colors.transparent,
        ),
      ),
    );
  }
}
