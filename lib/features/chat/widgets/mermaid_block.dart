library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Scrollbar, SelectableText;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as md;
// ignore: depend_on_referenced_packages
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';

import '../../../app/theme/light_surfaces.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/settings_providers.dart';
import 'mermaid_fullscreen_page.dart';

/// 匹配 Mermaid 图表类型起始关键字的正则表达式（大小写敏感，照 mermaid 惯例）。
final RegExp _mermaidHeaderPattern = RegExp(
  r'^\s*(graph|flowchart|sequenceDiagram|classDiagram|stateDiagram(-v2)?|erDiagram|gantt|pie|journey|mindmap|timeline|quadrantChart|gitGraph|C4Context|requirementDiagram|sankey-beta|xychart-beta|block-beta|packet-beta|architecture-beta)\b',
);

/// 判断 `<pre>` AST 元素是否符合 Mermaid 代码块接管条件。
///
/// 仅当 pre 内唯一 code 子元素 class 含 `language-mermaid`，
/// 或（无 class / 空 class 时）trim 后内容以已知 Mermaid 图表语法关键字开头。
bool isMermaidCodeElement(md.Element element) {
  if (element.children == null || element.children!.length != 1) {
    return false;
  }
  final child = element.children!.first;
  if (child is! md.Element || child.tag != 'code') {
    return false;
  }
  final className = child.attributes['class'] ?? '';
  if (className.split(RegExp(r'\s+')).contains('language-mermaid')) {
    return true;
  }
  if (className.isEmpty) {
    final text = child.textContent.trimLeft();
    return _mermaidHeaderPattern.hasMatch(text);
  }
  return false;
}

/// 从 `<pre>` 元素提取纯文本代码。
String extractCodeText(md.Element element) {
  if (element.children != null && element.children!.isNotEmpty) {
    return element.children!.first.textContent;
  }
  return element.textContent;
}

/// 暗色模式下的 Mermaid 主题：背景透明、节点深灰 #2C2C2E、描边 #48484A、文字白、边线灰。
const core.MermaidTheme kMermaidDarkTheme = core.MermaidTheme(
  background: core.Color(0x00000000),
  primaryColor: core.Color(0xff2c2c2e),
  primaryTextColor: core.Color(0xffffffff),
  primaryBorderColor: core.Color(0xff48484a),
  secondaryColor: core.Color(0xff3a3a3c),
  lineColor: core.Color(0xff8e8e93),
  arrowheadColor: core.Color(0xff8e8e93),
  textColor: core.Color(0xffffffff),
  nodeBorder: core.Color(0xff48484a),
  mainBkg: core.Color(0xff2c2c2e),
  clusterBkg: core.Color(0xff1c1c1e),
  clusterBorder: core.Color(0xff48484a),
  titleColor: core.Color(0xffffffff),
  edgeLabelBackground: core.Color(0xff2c2c2e),
  fontFamily: '"trebuchet ms", verdana, arial, sans-serif',
  fontSize: 16,
);

/// 根据当前上下文解析 Mermaid 主题。
core.MermaidTheme resolveMermaidTheme(BuildContext context) {
  final brightness = CupertinoTheme.of(context).brightness ?? Brightness.light;
  return brightness == Brightness.dark
      ? kMermaidDarkTheme
      : core.MermaidTheme.defaultTheme;
}

/// 普通代码块与语法错误时的兜底渲染组件。
///
/// 复刻 flutter_markdown 默认代码块视觉：
/// Container + Scrollbar + SingleChildScrollView + SelectableText。
/// 携带 [ValueKey('code-block-fallback')] 便于测试断言与状态识别。
class CodeBlockFallback extends StatefulWidget {
  const CodeBlockFallback({super.key, required this.text, this.styleSheet});

  final String text;
  final MarkdownStyleSheet? styleSheet;

  @override
  State<CodeBlockFallback> createState() => _CodeBlockFallbackState();
}

class _CodeBlockFallbackState extends State<CodeBlockFallback> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final styleSheet = widget.styleSheet;
    final padding = styleSheet?.codeblockPadding ?? const EdgeInsets.all(12);
    final textStyle =
        styleSheet?.code ??
        TextStyle(
          fontSize: 13,
          height: 1.4,
          fontFamily: 'monospace',
          color: CupertinoColors.label.resolveFrom(context),
        );

    // 对齐 flutter_markdown 原生处理：剥除末尾单一换行符，避免额外空行
    final cleanText = widget.text.replaceAll(RegExp(r'\n$'), '');

    return Container(
      key: const ValueKey('code-block-fallback'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Scrollbar(
            controller: _scrollController,
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: padding,
              child: SelectableText.rich(
                TextSpan(text: cleanText, style: textStyle),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 聊天气泡内渲染 Mermaid 图表的组件。
///
/// 具备能力：
/// 1. 响应 [chatRenderMermaidProvider] 开关状态，关闭时直接走兜底渲染；
/// 2. 流式防闪烁与半截语法容错：语法错误通过 [MermaidDiagram.errorBuilder] 兜底，
///    配合 [keepLastGoodSceneOnError: false] 干净回退源码；
/// 3. 约束尺寸（maxHeight: 420，超出由 FittedBox 自适应收敛）；
/// 4. 底部右侧「全屏」查看角标交互，点击打开 [MermaidFullscreenPage]。
class MermaidCodeBlock extends ConsumerStatefulWidget {
  const MermaidCodeBlock({
    super.key,
    required this.source,
    this.theme,
    this.styleSheet,
  });

  final String source;
  final core.MermaidTheme? theme;
  final MarkdownStyleSheet? styleSheet;

  @override
  ConsumerState<MermaidCodeBlock> createState() => _MermaidCodeBlockState();
}

class _MermaidCodeBlockState extends ConsumerState<MermaidCodeBlock> {
  bool _canRender(core.MermaidTheme theme) {
    try {
      core.Mermaid(
        measurer: const FlutterTextMeasurer(),
        theme: theme,
      ).render(widget.source);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? resolveMermaidTheme(context);
    final isEnabled = ref.watch(chatRenderMermaidProvider);

    // 开关关闭 → 直接兜底渲染（普通代码块）
    if (!isEnabled) {
      return CodeBlockFallback(
        text: widget.source,
        styleSheet: widget.styleSheet,
      );
    }

    // 语法错误检测：若不可渲染，通过 MermaidDiagram 的 errorBuilder 回退兜底代码块
    if (!_canRender(theme)) {
      return MermaidDiagram(
        source: widget.source,
        theme: theme,
        keepLastGoodSceneOnError: false,
        errorBuilder: (context, error) {
          return CodeBlockFallback(
            text: widget.source,
            styleSheet: widget.styleSheet,
          );
        },
      );
    }

    // 正常渲染：带全屏按钮与尺寸约束的图形卡片
    final fullscreenLabel = AppLocalizations.of(context).mermaidFullscreen;

    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: double.infinity,
              maxHeight: 420.0,
            ),
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.center,
              child: MermaidDiagram(
                key: const ValueKey('mermaid-diagram'),
                source: widget.source,
                theme: theme,
                keepLastGoodSceneOnError: false,
                errorBuilder: (context, error) {
                  return CodeBlockFallback(
                    text: widget.source,
                    styleSheet: widget.styleSheet,
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: CupertinoButton(
              key: const ValueKey('mermaid-fullscreen-button'),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              minimumSize: Size.zero,
              onPressed: () {
                Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (context) => MermaidFullscreenPage(
                      source: widget.source,
                      theme: theme,
                    ),
                  ),
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.arrow_up_left_arrow_down_right,
                    size: 12,
                    color: LightSurfaces.resolve(
                      context,
                      LightSurfaces.textSecondary,
                      dark: CupertinoColors.secondaryLabel,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    fullscreenLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: LightSurfaces.resolve(
                        context,
                        LightSurfaces.textSecondary,
                        dark: CupertinoColors.secondaryLabel,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
