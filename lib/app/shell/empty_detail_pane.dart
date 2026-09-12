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
                size: 64.0,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: CupertinoColors.tertiaryLabel,
                ),
              ),
              const SizedBox(height: 16.0),
              Text(
                l10n.isEnglish ? 'Select a Chat' : '选择会话',
                style: TextStyle(
                  fontSize: 20.0,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.label.resolveFrom(context),
                ),
              ),
              const SizedBox(height: 8.0),
              Text(
                l10n.isEnglish
                    ? 'Choose a session from the sidebar or start a new chat.'
                    : '从左侧选择会话或新建聊天',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.0,
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.textSecondary,
                    dark: CupertinoColors.secondaryLabel,
                  ),
                ),
              ),
              const SizedBox(height: 24.0),
              CupertinoButton.filled(
                color: isLight ? statusBlueText.resolveFrom(context) : null,
                key: const ValueKey('empty-detail-new-chat-button'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20.0,
                  vertical: 10.0,
                ),
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
                    const Icon(CupertinoIcons.plus, size: 18.0),
                    const SizedBox(width: 6.0),
                    Text(l10n.newSession),
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
