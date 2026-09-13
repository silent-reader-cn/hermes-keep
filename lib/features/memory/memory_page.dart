import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../app/widgets/adaptive_sliver_navigation_bar.dart';
import '../../core/api/api_exception.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/models/memory.dart';
import '../../core/utils/accessibility.dart';
import '../../l10n/app_localizations.dart';
import '../chat/widgets/markdown_styles.dart';
import '../shared/app_back_button.dart';
import 'memory_api.dart';
import 'memory_providers.dart';

enum _MemoryTab { memory, user, soul, projectContext }

/// 记忆查看页（对齐 Hermex MemoryView 的只读浏览形态）。
///
/// Cupertino 风格：大标题 + 刷新按钮 + 下拉刷新；顶部 4 段切换器
/// （我的笔记 / 用户画像 / 智能体灵魂 / 项目上下文）切换各分区；
/// 智能体灵魂与项目上下文支持 Markdown 渲染；
/// 卡片内容高度自适应视口且支持内部滚动；宽屏限制 maxWidth: 720 居中；
/// 含加载 / 错误 / 空态。
class MemoryPage extends ConsumerStatefulWidget {
  const MemoryPage({super.key});

  @override
  ConsumerState<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends ConsumerState<MemoryPage> {
  _MemoryTab _selectedTab = _MemoryTab.projectContext;
  bool _isEditing = false;
  late final TextEditingController _editController = TextEditingController();
  bool _isSaving = false;
  String? _saveError;

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  void _startEditing(String content) {
    setState(() {
      _isEditing = true;
      _saveError = null;
      _editController.text = content.trim();
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _saveError = null;
    });
  }

  Future<void> _save(MemorySection section) async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    try {
      final api = ref.read(memoryApiFactoryProvider)(
        ref.read(apiClientProvider),
      );
      final text = _editController.text;
      final response = await api.writeMemory(
        section: section.name,
        content: text,
      );
      if (response.ok == false &&
          response.error != null &&
          response.error!.isNotEmpty) {
        if (mounted) {
          setState(() {
            _saveError = response.error;
            _isSaving = false;
          });
        }
        return;
      }
      await ref.read(memoryControllerProvider.notifier).refresh();
      if (mounted) {
        setState(() {
          _isEditing = false;
          _isSaving = false;
        });
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _saveError = error.message;
          _isSaving = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saveError = error.toString();
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(memoryControllerProvider);
    final response = async.valueOrNull;

    return CupertinoPageScaffold(
      child: CustomScrollView(
        key: const ValueKey('memory-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          AdaptiveSliverNavigationBar(
            title: l10n.memoryTitle,
            leading: const AppBackButton(),
            trailing: AccessibleButton(
              key: const ValueKey('memory-refresh'),
              label: l10n.refreshMemory,
              padding: EdgeInsets.zero,
              onPressed: () => unawaited(
                ref.read(memoryControllerProvider.notifier).refresh(),
              ),
              child: const Icon(CupertinoIcons.arrow_clockwise),
            ),
          ),
          CupertinoSliverRefreshControl(
            onRefresh: () =>
                ref.read(memoryControllerProvider.notifier).refresh(),
          ),
          ..._buildContentSlivers(context, async, response),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 内容 slivers：加载 / 错误 / 空态 / 单卡片 Tab 视图
  // -------------------------------------------------------------------------

  List<Widget> _buildContentSlivers(
    BuildContext context,
    AsyncValue<MemoryResponse> async,
    MemoryResponse? response,
  ) {
    if (response == null) {
      if (async.isLoading) {
        return const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CupertinoActivityIndicator(radius: 14)),
          ),
        ];
      }
      return [_buildErrorSliver(context, async.error)];
    }

    if (!memoryHasContent(response)) {
      return [_buildEmptySliver(context)];
    }

    final hasProject = showsProjectContext(response);
    final activeTab = (_selectedTab == _MemoryTab.projectContext && !hasProject)
        ? _MemoryTab.memory
        : _selectedTab;
    final l10n = AppLocalizations.of(context);

    return [
      SliverToBoxAdapter(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: CupertinoSlidingSegmentedControl<_MemoryTab>(
                      groupValue: activeTab,
                      onValueChanged: (tab) {
                        if (tab != null && tab != activeTab) {
                          setState(() {
                            _selectedTab = tab;
                            _isEditing = false;
                            _saveError = null;
                          });
                        }
                      },
                      children: {
                        _MemoryTab.memory: Padding(
                          key: const ValueKey('memory-tab-memory'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Text(
                            l10n.memoryNotesTitle,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        _MemoryTab.user: Padding(
                          key: const ValueKey('memory-tab-user'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Text(
                            l10n.memoryUserTitle,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        _MemoryTab.soul: Padding(
                          key: const ValueKey('memory-tab-soul'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Text(
                            l10n.memorySoulTitle,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        if (hasProject)
                          _MemoryTab.projectContext: Padding(
                            key: const ValueKey('memory-tab-project'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Text(
                              l10n.projectContextTitle,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                      },
                    ),
                  ),
                ),
                _buildActiveCard(context, response, activeTab),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildActiveCard(
    BuildContext context,
    MemoryResponse response,
    _MemoryTab tab,
  ) {
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final sectionBg = LightSurfaces.resolve(
      context,
      LightSurfaces.page,
      dark: CupertinoColors.systemGroupedBackground,
    );
    final sectionDecoration = isLight
        ? BoxDecoration(
            color: LightSurfaces.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: LightSurfaces.cardBorder, width: 0.5),
          )
        : null;
    final sectionSeparator = isLight ? LightSurfaces.divider : null;

    switch (tab) {
      case _MemoryTab.memory:
        final content = response.memory ?? '';
        return CupertinoListSection.insetGrouped(
          backgroundColor: sectionBg,
          separatorColor: sectionSeparator,
          decoration: sectionDecoration,
          dividerMargin: 0,
          additionalDividerMargin: 0,

          header: _MemorySectionHeader(
            section: MemorySection.memory,
            mtime: response.memoryMtime,
            charCount: content.trim().length,
            isEditing: _isEditing,
            onEdit: () => _startEditing(content),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: _isEditing
                  ? _MemorySectionEditBody(
                      controller: _editController,
                      isSaving: _isSaving,
                      error: _saveError,
                      section: MemorySection.memory,
                      onSave: () => unawaited(_save(MemorySection.memory)),
                      onCancel: _cancelEditing,
                    )
                  : _MemorySectionBody(
                      section: MemorySection.memory,
                      content: content,
                    ),
            ),
          ],
        );
      case _MemoryTab.user:
        final content = response.user ?? '';
        return CupertinoListSection.insetGrouped(
          backgroundColor: sectionBg,
          separatorColor: sectionSeparator,
          decoration: sectionDecoration,
          dividerMargin: 0,
          additionalDividerMargin: 0,

          header: _MemorySectionHeader(
            section: MemorySection.user,
            mtime: response.userMtime,
            charCount: content.trim().length,
            isEditing: _isEditing,
            onEdit: () => _startEditing(content),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: _isEditing
                  ? _MemorySectionEditBody(
                      controller: _editController,
                      isSaving: _isSaving,
                      error: _saveError,
                      section: MemorySection.user,
                      onSave: () => unawaited(_save(MemorySection.user)),
                      onCancel: _cancelEditing,
                    )
                  : _MemorySectionBody(
                      section: MemorySection.user,
                      content: content,
                    ),
            ),
          ],
        );
      case _MemoryTab.soul:
        final content = response.soul ?? '';
        return CupertinoListSection.insetGrouped(
          backgroundColor: sectionBg,
          separatorColor: sectionSeparator,
          decoration: sectionDecoration,
          dividerMargin: 0,
          additionalDividerMargin: 0,

          header: _MemorySectionHeader(
            section: MemorySection.soul,
            mtime: response.soulMtime,
            charCount: content.trim().length,
            isEditing: _isEditing,
            onEdit: () => _startEditing(content),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: _isEditing
                  ? _MemorySectionEditBody(
                      controller: _editController,
                      isSaving: _isSaving,
                      error: _saveError,
                      section: MemorySection.soul,
                      onSave: () => unawaited(_save(MemorySection.soul)),
                      onCancel: _cancelEditing,
                    )
                  : _MemorySectionMarkdownBody(
                      section: MemorySection.soul,
                      content: content,
                    ),
            ),
          ],
        );
      case _MemoryTab.projectContext:
        final content = response.projectContext ?? '';
        return CupertinoListSection.insetGrouped(
          backgroundColor: sectionBg,
          separatorColor: sectionSeparator,
          decoration: sectionDecoration,
          dividerMargin: 0,
          additionalDividerMargin: 0,

          header: _ProjectContextHeader(
            mtime: response.projectContextMtime,
            charCount: content.trim().length,
          ),
          footer: _ProjectContextFooter(
            detail: memoryProjectContextDetail(response),
            shadowed: response.projectContextShadowed == true,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: _AdaptiveViewportScrollable(
                child: MarkdownBody(
                  data: content.trim(),
                  styleSheet: _buildMarkdownStyleSheet(context),
                  builders: createAssistantMarkdownBuilders(context),
                ),
              ),
            ),
          ],
        );
    }
  }

  Widget _buildErrorSliver(BuildContext context, Object? error) {
    final l10n = AppLocalizations.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 48,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                // 保留原未经解析的 systemGrey 绘制值（#8E8E93），防止高对比暗色下 resolve 变色
                dark: Color(CupertinoColors.systemGrey.toARGB32()),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.loadFailed,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage(context, error),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: statusRedText.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 20),
            CupertinoButton.filled(
              key: const ValueKey('memory-retry'),
              color: isLight ? LightSurfaces.userDetail : null,
              onPressed: () => unawaited(
                ref.read(memoryControllerProvider.notifier).refresh(),
              ),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySliver(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.doc_text,
              size: 48,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                // 保留原未经解析的 systemGrey 绘制值（#8E8E93），防止高对比暗色下 resolve 变色
                dark: Color(CupertinoColors.systemGrey.toARGB32()),
              ),
            ),
            const SizedBox(height: 12),
            Text(l10n.noMemory, style: const TextStyle(fontSize: 17)),
            const SizedBox(height: 6),
            Text(
              l10n.noMemoryContentYet,
              style: TextStyle(
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: secondaryText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _errorMessage(BuildContext context, Object? error) {
    if (error is ApiException) return error.message;
    return error?.toString() ?? AppLocalizations.of(context).unknownError;
  }
}

String _memorySectionTitle(BuildContext context, MemorySection section) {
  final l10n = AppLocalizations.of(context);
  switch (section) {
    case MemorySection.memory:
      return l10n.memoryNotesTitle;
    case MemorySection.user:
      return l10n.memoryUserTitle;
    case MemorySection.soul:
      return l10n.memorySoulTitle;
  }
}

String _memorySectionEmptyMessage(BuildContext context, MemorySection section) {
  final l10n = AppLocalizations.of(context);
  switch (section) {
    case MemorySection.memory:
      return l10n.memoryNotesEmpty;
    case MemorySection.user:
      return l10n.memoryUserEmpty;
    case MemorySection.soul:
      return l10n.memorySoulEmpty;
  }
}

const TextStyle _metaStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w400,
);

/// 记忆分区头：图标 + 标题 + 字数 + 相对修改时间 + 编辑按钮。
class _MemorySectionHeader extends StatelessWidget {
  const _MemorySectionHeader({
    required this.section,
    required this.mtime,
    required this.charCount,
    this.isEditing = false,
    this.onEdit,
  });

  final MemorySection section;
  final double? mtime;
  final int charCount;
  final bool isEditing;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final modified = formatMemoryMtime(mtime);
    final metaColor = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: secondaryText,
    );
    final metaStyle = _metaStyle.copyWith(color: metaColor);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          // 左簇：图标 + 标题，占满剩余空间（Expanded），保证右簇贴右缘。
          Expanded(
            child: Row(
              children: [
                Icon(
                  _memorySectionIcon(section),
                  size: 15,
                  color: CupertinoColors.label.resolveFrom(context),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _memorySectionTitle(context, section),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 右簇：字数统计 + 相对修改时间 + 编辑按钮，自然宽度贴右（float right）。
          if (charCount > 0)
            Text(
              '$charCount ${l10n.memoryCharUnit}',
              overflow: TextOverflow.ellipsis,
              style: metaStyle,
            ),
          if (modified != null) ...[
            if (charCount > 0) const SizedBox(width: 8),
            Text(modified, overflow: TextOverflow.ellipsis, style: metaStyle),
          ],
          if (onEdit != null && !isEditing) ...[
            const SizedBox(width: 8),
            AccessibleButton(
              key: ValueKey('memory-edit-${section.name}'),
              label: l10n.edit,
              padding: EdgeInsets.zero,
              minimumSize: const Size(28, 28),
              onPressed: onEdit,
              child: const Icon(CupertinoIcons.pencil, size: 16),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _memorySectionIcon(MemorySection section) {
    switch (section) {
      case MemorySection.memory:
        return CupertinoIcons.doc_text;
      case MemorySection.user:
        return CupertinoIcons.person;
      case MemorySection.soul:
        return CupertinoIcons.sparkles;
    }
  }
}

/// 分区编辑表单：CupertinoTextField + 错误提示 + 保存/取消按钮。
class _MemorySectionEditBody extends StatelessWidget {
  const _MemorySectionEditBody({
    required this.controller,
    required this.isSaving,
    required this.error,
    required this.section,
    required this.onSave,
    required this.onCancel,
  });

  final TextEditingController controller;
  final bool isSaving;
  final String? error;
  final MemorySection section;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    return _AdaptiveViewportScrollable(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          CupertinoTextField(
            key: ValueKey('memory-edit-input-${section.name}'),
            controller: controller,
            minLines: 6,
            maxLines: 14,
            placeholder: _memorySectionEmptyMessage(context, section),
            autofocus: true,
            enabled: !isSaving,
            style: const TextStyle(fontSize: 15, height: 1.4),
            padding: const EdgeInsets.all(12),
            decoration: isLight
                ? BoxDecoration(
                    color: LightSurfaces.card,
                    border: Border.all(
                      color: LightSurfaces.cardBorder,
                      width: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(5),
                  )
                : const CupertinoTextField().decoration,
            placeholderStyle: isLight
                ? const TextStyle(
                    fontWeight: FontWeight.w400,
                    color: LightSurfaces.placeholder,
                  )
                : const CupertinoTextField().placeholderStyle,
          ),
          if (error != null && error!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              style: TextStyle(
                fontSize: 13,
                color: statusRedText.resolveFrom(context),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              CupertinoButton(
                key: const ValueKey('memory-edit-cancel'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                onPressed: isSaving ? null : onCancel,
                child: Text(
                  l10n.cancel,
                  style: (isLight && !isSaving)
                      ? const TextStyle(color: LightSurfaces.userDetail)
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              CupertinoButton.filled(
                key: const ValueKey('memory-edit-save'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: isLight ? LightSurfaces.userDetail : null,
                onPressed: isSaving ? null : onSave,
                child: isSaving
                    ? const CupertinoActivityIndicator(radius: 8)
                    : Text(l10n.save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 分区内容（纯文本）：非空 → 正文（视口自适应内部滚动）；空 → 斜体占位文案。
class _MemorySectionBody extends StatelessWidget {
  const _MemorySectionBody({required this.section, required this.content});

  final MemorySection section;
  final String content;

  @override
  Widget build(BuildContext context) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return Text(
        _memorySectionEmptyMessage(context, section),
        style: TextStyle(
          fontSize: 15,
          fontStyle: FontStyle.italic,
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.textSecondary,
            dark: secondaryText,
          ),
        ),
      );
    }
    return _AdaptiveViewportScrollable(
      child: Text(trimmed, style: const TextStyle(fontSize: 15, height: 1.4)),
    );
  }
}

/// 分区内容（Markdown）：非空 → Markdown 渲染（视口自适应内部滚动）；空 → 斜体占位文案。
class _MemorySectionMarkdownBody extends StatelessWidget {
  const _MemorySectionMarkdownBody({
    required this.section,
    required this.content,
  });

  final MemorySection section;
  final String content;

  @override
  Widget build(BuildContext context) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return Text(
        _memorySectionEmptyMessage(context, section),
        style: TextStyle(
          fontSize: 15,
          fontStyle: FontStyle.italic,
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.textSecondary,
            dark: secondaryText,
          ),
        ),
      );
    }
    return _AdaptiveViewportScrollable(
      child: MarkdownBody(
        data: trimmed,
        styleSheet: _buildMarkdownStyleSheet(context),
        builders: createAssistantMarkdownBuilders(context),
      ),
    );
  }
}

/// 自适应视口高度滚动容器：
/// 卡片正文区高度按视口可用高度（视口高度 − 安全区 − 导航/Tab/卡片等 chrome 占用）自适应上限，
/// 内容较少时自然紧凑贴合，超出可用高度上限时卡片内部滚动，避免内容折叠与视口溢出。
class _AdaptiveViewportScrollable extends StatelessWidget {
  const _AdaptiveViewportScrollable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final available =
        mediaQuery.size.height -
        mediaQuery.padding.top -
        mediaQuery.padding.bottom -
        220;
    final maxHeight = available < 160.0 ? 160.0 : available;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(child: child),
    );
  }
}

/// Markdown 样式：以 Cupertino 主题为基底，显式配置正文语义色 label。
/// 灰底 code/blockquote 承载面上 label 黑字已达标，装饰面不改。
MarkdownStyleSheet _buildMarkdownStyleSheet(BuildContext context) {
  final theme = CupertinoTheme.of(context);
  final label = CupertinoColors.label.resolveFrom(context);
  final grey5 = CupertinoColors.systemGrey5.resolveFrom(context);
  // 以主题 textStyle（继承全局 MiSans 字体）为基底，正文显式语义色。
  return MarkdownStyleSheet.fromCupertinoTheme(theme).copyWith(
    p: theme.textTheme.textStyle.copyWith(
      fontSize: 15,
      height: 1.4,
      color: label,
    ),
    listBullet: theme.textTheme.textStyle.copyWith(fontSize: 15, color: label),
    code: TextStyle(
      fontSize: 13,
      height: 1.4,
      fontFamily: 'monospace',
      color: label,
      backgroundColor: grey5,
    ),
    codeblockDecoration: BoxDecoration(
      color: grey5,
      borderRadius: BorderRadius.circular(6),
    ),
    blockquoteDecoration: BoxDecoration(
      color: grey5,
      borderRadius: BorderRadius.circular(6),
    ),
    blockquotePadding: const EdgeInsets.all(8),
  );
}

/// 项目上下文分区头：图标 + 标题 + 字数 + 修改时间 + 只读锁。
class _ProjectContextHeader extends StatelessWidget {
  const _ProjectContextHeader({required this.mtime, required this.charCount});

  final double? mtime;
  final int charCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final modified = formatMemoryMtime(mtime);
    final metaColor = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: secondaryText,
    );
    final metaStyle = _metaStyle.copyWith(color: metaColor);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          // 左簇：图标 + 标题，占满剩余空间（Expanded），保证右簇贴右缘。
          Expanded(
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.folder,
                  size: 15,
                  color: CupertinoColors.label.resolveFrom(context),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    l10n.projectContextTitle,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 右簇：字数统计 + 相对修改时间 + 只读锁，自然宽度贴右（float right）。
          if (charCount > 0)
            Text(
              '$charCount ${l10n.memoryCharUnit}',
              overflow: TextOverflow.ellipsis,
              style: metaStyle,
            ),
          if (modified != null) ...[
            if (charCount > 0) const SizedBox(width: 8),
            Text(modified, overflow: TextOverflow.ellipsis, style: metaStyle),
          ],
          if (charCount > 0 || modified != null) const SizedBox(width: 8),
          Icon(
            CupertinoIcons.lock_fill,
            size: 13,
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.textSecondary,
              dark: CupertinoColors.secondaryLabel,
            ),
          ),
        ],
      ),
    );
  }
}

/// 项目上下文分区尾：明细行「名称 — 工作区」+ 覆盖警告
/// （对齐 Hermex ProjectContextSectionFooter）。
class _ProjectContextFooter extends StatelessWidget {
  const _ProjectContextFooter({required this.detail, required this.shadowed});

  final String? detail;
  final bool shadowed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final footerColor = LightSurfaces.resolve(
      context,
      LightSurfaces.textSecondary,
      dark: secondaryText,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (detail != null)
          Text(
            detail!,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: footerColor,
            ),
          ),
        if (shadowed) ...[
          const SizedBox(height: 4),
          Text(
            l10n.projectContextShadowedWarning,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: footerColor,
            ),
          ),
        ],
      ],
    );
  }
}
