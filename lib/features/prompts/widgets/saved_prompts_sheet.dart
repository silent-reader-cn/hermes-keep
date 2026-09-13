import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/light_surfaces.dart';
import '../../../app/theme/status_colors.dart';
import '../../../core/models/saved_prompt.dart';
import '../../../l10n/app_localizations.dart';
import '../prompts_providers.dart';

/// 收藏提示词列表面板（内容层，供底部 Sheet 与桌面 Popover 两种容器复用）。
///
/// - 列表由 [savedPromptsControllerProvider] 驱动；
/// - 行点击回调 [onInsert] 并关闭浮层（由调用方负责）；
/// - 底部「收藏当前输入」按钮需外部传入当前输入（[currentInput] 或 [getCurrentInput]）。
class SavedPromptsPanel extends ConsumerStatefulWidget {
  const SavedPromptsPanel({
    super.key,
    required this.onInsert,
    this.currentInput,
    this.getCurrentInput,
    this.onInserted,
  });

  /// 选中某条收藏后的插入回调（由调用方负责写入输入框并关闭浮层）。
  final ValueChanged<String> onInsert;

  /// 当前输入快照（静态值）。
  final String? currentInput;

  /// 当前输入回调（动态读取，优先于 [currentInput]）。
  final String Function()? getCurrentInput;

  /// 行插入成功后回调（用于让调用方关闭容器）。
  final VoidCallback? onInserted;

  @override
  ConsumerState<SavedPromptsPanel> createState() => _SavedPromptsPanelState();
}

class _SavedPromptsPanelState extends ConsumerState<SavedPromptsPanel> {
  bool _saving = false;
  final Set<String> _deletingIds = <String>{};

  String _resolveCurrentInput() {
    if (widget.getCurrentInput != null) return widget.getCurrentInput!.call();
    return widget.currentInput ?? '';
  }

  Future<void> _handleSaveCurrent() async {
    final l10n = AppLocalizations.of(context);
    final raw = _resolveCurrentInput();
    final text = raw.trim();
    if (text.isEmpty) {
      await _showAlert(l10n.notice, l10n.savedPromptsEmptyInput);
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final prompt = await ref
          .read(savedPromptsControllerProvider.notifier)
          .create(text: text);
      if (!mounted) return;
      if (prompt != null) {
        await _showAlert(l10n.promptSaved, l10n.promptSaved);
      } else {
        await _showAlert(
          l10n.savePromptFailed,
          l10n.savePromptFailed,
          isError: true,
        );
      }
    } catch (error) {
      if (!mounted) return;
      await _showAlert(l10n.savePromptFailed, error.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleDelete(String id) async {
    if (id.isEmpty || _deletingIds.contains(id)) return;
    setState(() => _deletingIds.add(id));
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(savedPromptsControllerProvider.notifier).remove(id);
    } catch (error) {
      if (!mounted) return;
      await _showAlert(
        l10n.deletePromptFailed,
        error.toString(),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _deletingIds.remove(id));
    }
  }

  Future<void> _showAlert(
    String title,
    String message, {
    bool isError = false,
  }) {
    final l10n = AppLocalizations.of(context);
    return showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) {
        final isLight =
            CupertinoTheme.brightnessOf(dialogContext) == Brightness.light;
        return CupertinoAlertDialog(
          title: Text(title),
          content: Text(
            message,
            style: isError
                ? TextStyle(color: statusRedText.resolveFrom(dialogContext))
                : null,
          ),
          actions: [
            CupertinoDialogAction(
              textStyle: isLight
                  ? const TextStyle(color: LightSurfaces.userDetail)
                  : null,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.ok),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(savedPromptsControllerProvider);

    // 覆盖式小 indicator：有数据时不替换整板，仅叠加顶部细线 loading
    final hasData = async.valueOrNull != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (async.isLoading && hasData)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: CupertinoActivityIndicator(radius: 10),
          ),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: _buildBody(context, async),
          ),
        ),
        Container(
          height: 0.5,
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.divider,
            dark: CupertinoColors.separator,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: CupertinoButton.filled(
              key: const ValueKey('saved-prompts-save-current'),
              color: CupertinoTheme.brightnessOf(context) == Brightness.light
                  ? LightSurfaces.userDetail
                  : null,
              onPressed: _saving ? null : _handleSaveCurrent,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: _saving
                  ? const CupertinoActivityIndicator(
                      color: CupertinoColors.white,
                    )
                  : Text(l10n.saveCurrentInput),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, AsyncValue<List<SavedPrompt>> async) {
    final l10n = AppLocalizations.of(context);
    return async.when(
      data: (prompts) {
        if (prompts.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Text(
                l10n.savedPromptsEmpty,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.textSecondary,
                    dark: CupertinoColors.secondaryLabel,
                  ),
                ),
              ),
            ),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: prompts.length,
          separatorBuilder: (_, _) => Container(
            height: 0.5,
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.divider,
              dark: CupertinoColors.separator,
            ),
            margin: const EdgeInsets.only(left: 16),
          ),
          itemBuilder: (context, index) {
            final prompt = prompts[index];
            final id = prompt.id;
            final displayLabel = savedPromptDisplayLabel(prompt);
            final rawLabel = prompt.label?.trim();
            final title = (rawLabel != null && rawLabel.isNotEmpty)
                ? rawLabel
                : (displayLabel.isEmpty ? (prompt.text ?? '') : displayLabel);
            final subtitleText = prompt.text ?? '';
            final isDeleting = id != null && _deletingIds.contains(id);
            final isLight =
                CupertinoTheme.brightnessOf(context) == Brightness.light;
            return CupertinoListTile(
              key: ValueKey('saved-prompt-$id-$index'),
              backgroundColor: isLight ? LightSurfaces.card : null,
              backgroundColorActivated: isLight ? LightSurfaces.pressed : null,
              title: Text(
                title.isEmpty ? l10n.unnamed : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                subtitleText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.textSecondary,
                    dark: CupertinoColors.secondaryLabel,
                  ),
                  fontSize: 13,
                ),
              ),
              trailing: CupertinoButton(
                key: ValueKey('saved-prompt-delete-$id'),
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                onPressed: (id == null || id.isEmpty || isDeleting)
                    ? null
                    : () => _handleDelete(id),
                child: isDeleting
                    ? const CupertinoActivityIndicator(radius: 10)
                    : Icon(
                        CupertinoIcons.delete,
                        size: 20,
                        color: statusRedText.resolveFrom(context),
                      ),
              ),
              onTap: () {
                widget.onInsert(prompt.text ?? '');
                widget.onInserted?.call();
              },
            );
          },
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: CupertinoActivityIndicator(),
        ),
      ),
      error: (error, _) {
        // 有缓存数据时错误不替换整板，仅显示重试行（由上层覆盖式 indicator 处理）
        // 无缓存才展示全板错误
        final isLight =
            CupertinoTheme.brightnessOf(context) == Brightness.light;
        if (async.valueOrNull != null && async.valueOrNull!.isNotEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: CupertinoButton(
                key: const ValueKey('saved-prompts-retry'),
                onPressed: () =>
                    ref.read(savedPromptsControllerProvider.notifier).refresh(),
                child: Text(
                  l10n.retry,
                  style: isLight
                      ? const TextStyle(color: LightSurfaces.userDetail)
                      : null,
                ),
              ),
            ),
          );
        }
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: statusRedText.resolveFrom(context)),
                ),
                const SizedBox(height: 12),
                CupertinoButton(
                  key: const ValueKey('saved-prompts-retry'),
                  onPressed: () => ref
                      .read(savedPromptsControllerProvider.notifier)
                      .refresh(),
                  child: Text(
                    l10n.retry,
                    style: isLight
                        ? const TextStyle(color: LightSurfaces.userDetail)
                        : null,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 收藏提示词底部 Sheet（移动端窄屏容器：占底部的全宽弹层）。
///
/// 内容委托给 [SavedPromptsPanel]；桌面/平板宽屏请改用 popover 容器
/// （见 `lib/app/widgets/cupertino_popover.dart`）。
class SavedPromptsSheet extends StatelessWidget {
  const SavedPromptsSheet({
    super.key,
    required this.onInsert,
    this.currentInput,
    this.getCurrentInput,
  });

  /// 选中某条收藏后的插入回调（由调用方负责写入输入框）。
  final ValueChanged<String> onInsert;

  /// 当前输入快照（静态值）。
  final String? currentInput;

  /// 当前输入回调（动态读取，优先于 [currentInput]）。
  final String Function()? getCurrentInput;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final bg = LightSurfaces.resolve(
      context,
      LightSurfaces.card,
      dark: CupertinoColors.systemGrey6,
    );

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: isLight
            ? Border.all(color: LightSurfaces.cardBorder, width: 0.5)
            : null,
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            // 拖拽手柄保持 systemGrey3 装饰填充（非文字信息层，豁免正文 AA）。
            Container(
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey3.resolveFrom(context),
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.savedPromptsTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Container(
              height: 0.5,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.divider,
                dark: CupertinoColors.separator,
              ),
            ),
            SavedPromptsPanel(
              onInsert: onInsert,
              currentInput: currentInput,
              getCurrentInput: getCurrentInput,
              onInserted: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }
}
