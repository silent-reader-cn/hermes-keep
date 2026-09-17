import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../l10n/app_localizations.dart';
import '../settings/settings_surfaces.dart';
import 'workspace_manager_providers.dart';

/// 新建工作区表单（iOS form sheet 风格，键盘可避让）。
///
/// 视觉规范对齐 Apple HIG presentation 模式：
/// - 不透明 `systemBackground` 面板 + 顶部圆角，遮罩加深（见调用方 barrierColor），
///   内容绝不与背景列表互相穿插；
/// - 标准导航头：拖拽指示条 + 左「取消」/ 居中标题 / 右「添加」（禁用态变灰）；
/// - 表单为 inset-grouped 圆角卡片：路径、名称、自动创建开关各占一行，行间细分割线，
///   开关遵循 iOS「标题左、控件右」惯例。
///
/// 行为对齐 Hermes WebUI `openWorkspaceCreate`（panels.js:6149-6183）：名称可选 +
/// 路径必填 + 路径输入 250ms 防抖请求 `/api/workspaces/suggest` 内联补全 +
/// 「目录不存在时自动创建」开关；提交错误以 statusRedText 内联展示（不弹窗
/// 打断）；path 空白/提交中禁用「添加」按钮。
class AddWorkspaceSheet extends ConsumerStatefulWidget {
  const AddWorkspaceSheet({super.key});

  @override
  ConsumerState<AddWorkspaceSheet> createState() => _AddWorkspaceSheetState();
}

class _AddWorkspaceSheetState extends ConsumerState<AddWorkspaceSheet> {
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  bool _create = false;
  bool _submitting = false;
  String? _inlineError;
  List<String> _suggestions = const [];
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _pathController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _onPathChanged(String value) {
    _debounce?.cancel();
    setState(() => _inlineError = null);
    if (value.trim().isEmpty) {
      setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_loadSuggestions(value.trim()));
    });
  }

  Future<void> _loadSuggestions(String prefix) async {
    final suggestions = await ref
        .read(workspaceManagerControllerProvider.notifier)
        .loadSuggestions(prefix);
    if (!mounted) return;
    setState(() => _suggestions = suggestions);
  }

  Future<void> _submit() async {
    final path = _pathController.text.trim();
    if (path.isEmpty || _submitting) return;
    setState(() {
      _submitting = true;
      _inlineError = null;
    });
    final name = _nameController.text.trim();
    final error = await ref
        .read(workspaceManagerControllerProvider.notifier)
        .addWorkspace(
          path: path,
          name: name.isEmpty ? null : name,
          create: _create,
        );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _submitting = false;
      _inlineError = error;
    });
  }

  void _dismiss() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final canSubmit = _pathController.text.trim().isNotEmpty && !_submitting;
    final accent = canSubmit
        ? (isDark
              ? CupertinoColors.systemBlue.resolveFrom(context)
              : statusBlueText.resolveFrom(context))
        : (isDark
              ? CupertinoColors.inactiveGray.resolveFrom(context)
              : LightSurfaces.placeholder);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      child: Container(
        // 不透明面板：浅色使用 page，深色使用 systemBackground 隔离背景列表
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.page,
          dark: CupertinoColors.systemBackground,
        ),
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: viewInsets.bottom),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildGrabber(context),
                _buildHeader(context, l10n, accent, canSubmit, isDark),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildGroupedCard(context, l10n),
                        if (_inlineError != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _inlineError!,
                            key: const ValueKey('workspace-add-error'),
                            style: TextStyle(
                              fontSize: 13,
                              color: statusRedText.resolveFrom(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 顶部拖拽指示条（36×4，iOS sheet 惯例）。
  Widget _buildGrabber(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            // grabber 是非交互装饰，保留系统 tertiaryLabel 且深浅色保留（无拖动手势）
            color: CupertinoColors.tertiaryLabel.resolveFrom(context),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  /// 导航头：左「取消」/ 居中标题 / 右「添加」。
  Widget _buildHeader(
    BuildContext context,
    AppLocalizations l10n,
    Color accent,
    bool canSubmit,
    bool isDark,
  ) {
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            CupertinoButton(
              key: const ValueKey('workspace-add-cancel'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              onPressed: _dismiss,
              child: Text(
                l10n.cancel,
                style: TextStyle(
                  fontSize: 17,
                  color: isDark
                      ? CupertinoColors.systemBlue.resolveFrom(context)
                      : statusBlueText.resolveFrom(context),
                ),
              ),
            ),
            Expanded(
              child: Text(
                l10n.addWorkspace,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            CupertinoButton(
              key: const ValueKey('workspace-add-submit'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              onPressed: canSubmit ? () => unawaited(_submit()) : null,
              child: Text(
                l10n.addWorkspaceButton,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// inset-grouped 圆角卡片：路径行 + 补全列表 + 名称行 + 开关行。
  Widget _buildGroupedCard(BuildContext context, AppLocalizations l10n) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? CupertinoColors.secondarySystemBackground.resolveFrom(context)
            : LightSurfaces.card,
        borderRadius: BorderRadius.circular(10),
        border: isDark
            ? null
            : Border.all(color: LightSurfaces.cardBorder, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LabeledFieldRow(
            label: l10n.workspacePathLabel,
            child: CupertinoTextField(
              key: const ValueKey('workspace-add-path'),
              controller: _pathController,
              placeholder: l10n.workspacePathHint,
              placeholderStyle: TextStyle(
                fontSize: 17,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.placeholder,
                  dark: CupertinoColors.placeholderText,
                ),
              ),
              style: const TextStyle(fontSize: 17),
              autocorrect: false,
              decoration: const BoxDecoration(
                color: CupertinoColors.transparent,
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              onChanged: _onPathChanged,
            ),
          ),
          if (_suggestions.isNotEmpty) ...[
            const _RowSeparator(),
            _SuggestionList(
              suggestions: _suggestions,
              onPick: (value) {
                _pathController.text = value;
                setState(() {
                  _suggestions = const [];
                  _inlineError = null;
                });
              },
            ),
          ],
          const _RowSeparator(),
          _LabeledFieldRow(
            label: l10n.workspaceNameOptionalLabel,
            child: CupertinoTextField(
              key: const ValueKey('workspace-add-name'),
              controller: _nameController,
              placeholder: l10n.workspaceNamePlaceholder,
              placeholderStyle: TextStyle(
                fontSize: 17,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.placeholder,
                  dark: CupertinoColors.placeholderText,
                ),
              ),
              style: const TextStyle(fontSize: 17),
              autocorrect: false,
              decoration: const BoxDecoration(
                color: CupertinoColors.transparent,
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const _RowSeparator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.createDirectoryIfMissing,
                    style: const TextStyle(fontSize: 17),
                  ),
                ),
                SettingsSurfaces.toggle(
                  context,
                  CupertinoSwitch(
                    key: const ValueKey('workspace-add-create'),
                    value: _create,
                    onChanged: (value) => setState(() => _create = value),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡片内一行：左侧字段标签 + 右侧无边框输入控件。
class _LabeledFieldRow extends StatelessWidget {
  const _LabeledFieldRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: CupertinoColors.secondaryLabel,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 卡片行内细分割线（左缩进 16，iOS grouped list 惯例）。
class _RowSeparator extends StatelessWidget {
  const _RowSeparator();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: 16),
      color: LightSurfaces.resolve(
        context,
        LightSurfaces.divider,
        dark: CupertinoColors.separator,
      ),
    );
  }
}

/// 路径补全建议列表（卡片内嵌，点击填入路径）。
class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.suggestions, required this.onPick});

  final List<String> suggestions;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      color: LightSurfaces.resolve(
        context,
        LightSurfaces.pressed,
        dark: CupertinoColors.tertiarySystemFill,
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: suggestions.length,
        separatorBuilder: (context, index) => Container(
          height: 0.5,
          margin: const EdgeInsets.only(left: 16),
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.divider,
            dark: CupertinoColors.separator,
          ),
        ),
        itemBuilder: (context, index) {
          final suggestion = suggestions[index];
          return CupertinoButton(
            key: ValueKey('workspace-add-suggestion-$index'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            borderRadius: BorderRadius.circular(0),
            onPressed: () => onPick(suggestion),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                suggestion,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  color:
                      CupertinoTheme.brightnessOf(context) == Brightness.light
                      ? LightSurfaces.userDetail
                      : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
