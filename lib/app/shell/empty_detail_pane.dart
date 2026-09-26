import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/session_list/session_list_providers.dart';
import '../../l10n/app_localizations.dart';
import '../theme/light_surfaces.dart';
import '../theme/status_colors.dart';

/// 宽屏双栏模式下的空态详情占位页（蓝本 SessionListView.swift §regularWidthDetail）。
///
/// 当桌面/平板宽屏处于根路径 `/` 且未选中任何具体会话或功能页时展示。
class EmptyDetailPane extends ConsumerWidget {
  const EmptyDetailPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = CupertinoTheme.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;

    return CupertinoPageScaffold(
      backgroundColor: isLight
          ? LightSurfaces.card
          : theme.scaffoldBackgroundColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.chat_bubble_2,
                // #163 方案 B：图标 64 → 52（宽屏右侧比侧栏大一档即可，
                // 不做大体量插画式留白）。
                size: 52.0,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: CupertinoColors.tertiaryLabel,
                ),
              ),
              const SizedBox(height: 14.0),
              Text(
                l10n.isEnglish ? 'Select a Chat' : '选择会话',
                style: TextStyle(
                  // #163 方案 B：20 → 17（＝导航栏标题同号）。
                  fontSize: 17.0,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.label.resolveFrom(context),
                ),
              ),
              const SizedBox(height: 6.0),
              Text(
                l10n.isEnglish
                    ? 'Choose a session from the sidebar or start a new chat.'
                    : '从左侧选择会话或新建聊天',
                textAlign: TextAlign.center,
                style: TextStyle(
                  // #163 方案 B：14 → 13（＝侧栏元数据同号）。
                  fontSize: 13.0,
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.textSecondary,
                    dark: CupertinoColors.secondaryLabel,
                  ),
                ),
              ),
              const SizedBox(height: 20.0),
              CupertinoButton.filled(
                color: isLight ? statusBlueText.resolveFrom(context) : null,
                key: const ValueKey('empty-detail-new-chat-button'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18.0,
                  vertical: 9.0,
                ),
                borderRadius: BorderRadius.circular(10.0),
                onPressed: () async {
                  final controller = ref.read(
                    sessionListControllerProvider.notifier,
                  );
                  final id = await controller.createSession();
                  if (!context.mounted) return;
                  if (id != null) {
                    context.go('/chat/$id');
                  } else {
                    context.go('/chat');
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(CupertinoIcons.plus, size: 17.0),
                    const SizedBox(width: 6.0),
                    Text(
                      l10n.newSession,
                      // #163 方案 B：按钮文字 15（＝工具行与正文同族的层级）。
                      style: const TextStyle(fontSize: 15.0),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
