"""Reproduce the light-theme audit using only Python's standard library.

Usage (from any directory):
    python tools/light_theme_contrast.py --tokens
    python tools/light_theme_contrast.py --write-report
    python tools/light_theme_contrast.py --check-report

The default stdout is the complete report, including its numeric appendix.
Cupertino values come from the installed Flutter SDK, not documentation prose.
No application source, screenshot or golden is modified by this tool.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
from dataclasses import dataclass
import json
from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlparse


ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / 'docs/specs/light-theme-audit-2026-09-12.md'
NUMBER = r'(?:0[xX][0-9a-fA-F]+|\d+(?:\.\d+)?)'
LITERAL = rf'(?:\b(?:core|ui)\.)?\bColor(?:\.from(?:ARGB|RGBO))?\s*\(\s*{NUMBER}(?:\s*,\s*{NUMBER}){{0,3}}\s*\)'
COLORS = re.compile(rf'CupertinoColors\.\w+|LightSurfaces\.(?!resolve\b)\w+|\bstatus\w+Text\b|\bsecondaryText\b|\b_statusDebugText\b|{LITERAL}')
STRINGS_COMMENTS = re.compile(
    r"r?'''[\s\S]*?'''|r?\"\"\"[\s\S]*?\"\"\"|r?'(?:\\.|[^'\\])*'|r?\"(?:\\.|[^\"\\])*\"|//[^\n]*|/\*[\s\S]*?\*/"
)


@dataclass(frozen=True)
class Color:
    r: float
    g: float
    b: float
    a: float = 1.0

    def over(self, background: Color) -> Color:
        if background.a != 1:
            raise ValueError('Composite the background onto an opaque surface first.')
        return Color(*(x * self.a + y * (1 - self.a)
                       for x, y in zip(self.rgb, background.rgb)))

    @property
    def rgb(self) -> tuple[float, float, float]:
        return self.r, self.g, self.b

    @property
    def luminance(self) -> float:
        def linear(c: float) -> float:
            return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
        return sum(w * linear(c) for w, c in zip((0.2126, 0.7152, 0.0722), self.rgb))

    def alpha(self, value: float) -> Color:
        return Color(*self.rgb, value)

    def display(self) -> str:
        # Round only for the displayed RGB, never before contrast calculation.
        rgb = ''.join(f'{int(c * 255 + 0.5):02X}' for c in self.rgb)
        return '#' + rgb + (f' / α={self.a:.6f}' if self.a != 1 else '')


def hex_color(value: str) -> Color:
    value = value.removeprefix('#')
    if len(value) == 6:
        value = 'FF' + value
    a, r, g, b = (int(value[i:i + 2], 16) / 255 for i in range(0, 8, 2))
    return Color(r, g, b, a)


def literal_color(expression: str) -> Color:
    args = re.search(r'\((.*)\)', expression, re.S).group(1)
    numbers = [float(int(x.strip(), 16)) if x.strip().lower().startswith('0x')
               else float(x.strip()) for x in args.split(',')]
    if '.fromARGB' in expression:
        a, r, g, b = numbers
        return Color(r / 255, g / 255, b / 255, a / 255)
    if '.fromRGBO' in expression:
        r, g, b, a = numbers
        return Color(r / 255, g / 255, b / 255, a)
    return hex_color(f'{int(numbers[0]):08X}')


def contrast(foreground: Color, background: Color) -> float:
    luminances = sorted((foreground.over(background).luminance, background.luminance))
    return (luminances[1] + 0.05) / (luminances[0] + 0.05)


def mask(source: str) -> str:
    return STRINGS_COMMENTS.sub(lambda m: re.sub(r'[^\n]', ' ', m.group()), source)


def sdk_path(explicit: str | None) -> Path:
    if explicit:
        return Path(explicit) / 'packages/flutter'
    config = json.loads((ROOT / '.dart_tool/package_config.json').read_text(encoding='utf-8'))
    uri = next(p['rootUri'] for p in config['packages'] if p['name'] == 'flutter')
    parsed = urlparse(uri)
    if parsed.scheme == 'file':
        path = unquote(parsed.path)
        if re.match(r'^/[A-Za-z]:', path):
            path = path[1:]
        return Path(path)
    return (ROOT / '.dart_tool' / unquote(uri)).resolve()


def palette(flutter: Path) -> dict[str, Color]:
    result: dict[str, Color] = {}
    source = (flutter / 'lib/src/cupertino/colors.dart').read_text(encoding='utf-8')
    definitions = re.findall(r'static const (?:CupertinoDynamicColor|Color) (\w+)\s*=\s*([\s\S]*?);', source)
    pending = []
    for name, body in definitions:
        key = 'CupertinoColors.' + name
        value = re.search(rf'\bcolor:\s*({LITERAL})', body)
        if value:
            result[key] = literal_color(value.group(1))
        elif re.fullmatch(LITERAL, body.strip()):
            result[key] = literal_color(body.strip())
        else:
            pending.append((key, 'CupertinoColors.' + body.strip()))
    for _ in range(len(pending) + 1):
        for name, target in pending:
            if target in result:
                result[name] = result[target]
    for relative in ('lib/app/theme/status_colors.dart', 'lib/features/diagnostics/diagnostics_models.dart'):
        source = (ROOT / relative).read_text(encoding='utf-8')
        for name, body in re.findall(r'const CupertinoDynamicColor (\w+)\s*=([\s\S]*?);', source):
            match = re.search(rf'\bcolor:\s*({LITERAL})', body)
            if match:
                result[name] = literal_color(match.group(1))
    source = (ROOT / 'lib/app/theme/light_surfaces.dart').read_text(encoding='utf-8')
    for name, value in re.findall(r'static const Color (\w+) = ([^;]+);', source):
        result['LightSurfaces.' + name] = (literal_color(value) if 'Color(' in value
                                         else result['LightSurfaces.' + value])
    result['theme.primaryColor'] = hex_color('007AFF')
    for filename in ('dialog.dart', 'text_field.dart', 'list_section.dart',
                     'nav_bar.dart', 'route.dart', 'button.dart',
                     'sliding_segmented_control.dart'):
        source = (flutter / 'lib/src/cupertino' / filename).read_text(encoding='utf-8')
        for name, body in re.findall(
                r'const (?:Color|CupertinoDynamicColor|BoxDecoration|BorderSide|Border) (\w+)\s*=([\s\S]*?);', source):
            value = re.search(rf'\bcolor:\s*({LITERAL}|CupertinoColors\.\w+)', body)
            expression = value.group(1) if value else body.strip()
            if re.fullmatch(LITERAL, expression):
                result[f'SDK/{filename}#{name}'] = literal_color(expression)
            elif expression in result:
                result[f'SDK/{filename}#{name}'] = result[expression]
    return result


def calls(source: str) -> list[tuple[int, int, str]]:
    stack: list[tuple[int, str]] = []
    result = []
    for i, char in enumerate(source):
        if char == '(':
            found = re.search(r'([\w.]+)\s*$', source[max(0, i - 100):i])
            stack.append((i, found.group(1) if found else ''))
        elif char == ')' and stack:
            start, name = stack.pop()
            result.append((start, i, name))
    return result


def role_at(source: str, position: int, enclosing: list[tuple[int, int, str]], path: str) -> str:
    parents = sorted((c for c in enclosing if c[0] < position < c[1]), reverse=True)
    if 'mermaid_block.dart' in path and source[max(0, position - 5):position].endswith('core.'):
        return '图表深色配置豁免'
    if 'mermaid_block.dart' in path and source[position:position + 10].startswith('core.Color'):
        return '图表深色配置豁免'
    if 'onboarding_hero_motion.dart' in path and position > source.find('class _HaloPainter'):
        return '纯装饰豁免'
    for start, _, name in parents:
        argument = source[start:position]
        last_named = re.findall(r'\b(\w+)\s*:', argument)
        if name == 'LightSurfaces.resolve' and last_named and last_named[-1] == 'dark':
            return '暗色保留豁免'
    line = source[source.rfind('\n', 0, position) + 1:position]
    if re.search(r'\b(?:darkColor|darkHighContrastColor|darkElevatedColor|highContrastColor|highContrastElevatedColor|darkHighContrastElevatedColor):', line):
        return '其他主题定义豁免'
    # Identify the positive arm of a nearby isDark ternary (nested calls included).
    for match in re.finditer(r'\bisDark\s*\?', source[max(0, position - 500):position]):
        start = max(0, position - 500) + match.end()
        between = source[start:position]
        if ':' not in between and ';' not in between:
            return '暗色保留豁免'
    for start, _, name in parents:
        base = name.split('.')[0]
        if base in ('Border', 'BorderSide', 'TableBorder', 'BoxShadow', 'LinearGradient', 'RadialGradient'):
            return '装饰线/投影豁免'
        if name.endswith('TextStyle') or name == '_body':
            named = re.findall(r'\b(\w+)\s*:', source[start:position])
            return '面' if named and named[-1] == 'backgroundColor' else '文字'
        if base in ('Icon', 'CupertinoActivityIndicator', 'BarChartRodData'):
            return '图标/图形'
        if base in ('BoxDecoration', 'ShapeDecoration', 'ColoredBox', 'Container',
                    'AnimatedContainer', 'CupertinoPageScaffold'):
            return '面'
    assignment = source[max(0, source.rfind(';', 0, position) + 1):position]
    found = re.search(r'(?:final|const|Color)\s+(\w+)\s*=', assignment)
    name = found.group(1).lower() if found else ''
    if any(word in name for word in ('background', 'bg', 'fill', 'surface')):
        return '面/复用'
    if any(word in name for word in ('text', 'label', 'link')):
        return '文字/复用'
    if any(word in name for word in ('border', 'separator', 'divider', 'shadow')):
        return '装饰线/投影豁免'
    if name in ('page', 'card', 'selection', 'pressed', 'grey5', 'effectiveTrackColor'):
        return '面/复用'
    return '复用色；按承载面判级'


@dataclass
class Use:
    name: str
    color: Color
    role: str
    lines: list[int]
    note: str = ''


def scan_file(path: Path, values: dict[str, Color]) -> tuple[list[Use], list[str]]:
    original = path.read_text(encoding='utf-8')
    source = mask(original)
    enclosing = calls(source)
    uses: dict[tuple[str, str, str], Use] = {}
    # Resolve aliases in their lexical scope. A later `white`/`color` variable
    # in another builder must not change an earlier alpha calculation.
    scopes = [(0, len(source))]
    stack = []
    for i, char in enumerate(source):
        if char == '{':
            stack.append(i)
        elif char == '}' and stack:
            scopes.append((stack.pop(), i))
    aliases: dict[str, list[tuple[int, tuple[int, int], Color]]] = defaultdict(list)
    candidates = list(COLORS.finditer(source))
    candidates += list(re.finditer(r'\b(?:theme\.primaryColor|CupertinoTheme\.of\(context\)\.primaryColor)\b', source))
    for match in candidates:
        prefix = source[max(0, match.start() - 100):match.start()]
        assigned = re.search(r'(?:final|const)(?:\s+Color)?\s+(\w+)\s*=\s*$', prefix)
        raw = match.group()
        color = values.get(raw)
        if 'primaryColor' in raw:
            color = values['theme.primaryColor']
        if color is None and re.fullmatch(LITERAL, raw):
            color = literal_color(raw)
        if assigned and color:
            scope = max((s for s in scopes if s[0] <= match.start() < s[1]))
            aliases[assigned.group(1)].append((match.start(), scope, color))
    candidates += [m for m in re.finditer(r'\b\w+(?=\s*\.with(?:Values|Opacity|Alpha)\()', source)
                   if m.group() in aliases]
    for match in sorted(candidates, key=lambda m: m.start()):
        name = re.sub(r'\s+', '', match.group())
        color = values.get(name)
        if color is None and name in aliases:
            bindings = [(scope[0], pos, c) for pos, scope, c in aliases[name]
                        if pos < match.start() and scope[0] <= match.start() < scope[1]]
            if not bindings:
                continue
            color = max(bindings, key=lambda b: (b[0], b[1]))[2]
        if 'primaryColor' in name:
            color = values['theme.primaryColor']
            name = 'theme.primaryColor'
        if color is None:
            if re.fullmatch(LITERAL, match.group()):
                color = literal_color(match.group())
            else:
                raise ValueError(f'Unresolved color at {path}:{match.group()}')
        suffix = source[match.end():match.end() + 200]
        suffix = re.sub(r'^\s*\.resolveFrom\(\w+\)', '', suffix)
        alpha = re.match(rf'\s*\.with(?:Values\(\s*alpha:\s*|Opacity\(\s*)({NUMBER})\s*\)', suffix)
        note = ''
        if alpha:
            color = color.alpha(float(alpha.group(1)))
            name += f' @ {color.a:g}'
        else:
            alpha_int = re.match(rf'\s*\.withAlpha\(\s*({NUMBER})\s*\)', suffix)
            if alpha_int:
                color = color.alpha(int(alpha_int.group(1), 0) / 255)
                name += f' @ {color.a:.6f}'
            elif re.match(r'\s*\.with(?:Values|Opacity|Alpha)\(', suffix):
                # Do not pretend an animation/state-dependent alpha is a constant.
                note = '运行时 alpha；表中仅列未调制基色，不能据此声明实际帧达标'
        role = role_at(source, match.start(), enclosing, path.as_posix())
        if path.name == 'chat_media_view.dart' and name == 'CupertinoColors.systemGrey':
            note = '固定黑底媒体文字；实际组合见 P0/media inverse secondary'
        if path.name == 'markdown_styles.dart' and name in ('CupertinoColors.systemGrey5', 'CupertinoColors.link'):
            note = '非聊天共享默认/暗色分支；聊天浅色已显式传入令牌'
        key = name, role, note
        line = original.count('\n', 0, match.start()) + 1
        if key not in uses:
            uses[key] = Use(name, color, role, [], note)
        uses[key].lines.append(line)
    defaults = [name for name in (
        'CupertinoPageScaffold', 'CupertinoListSection', 'CupertinoListTile',
        'CupertinoTextField', 'CupertinoSearchTextField', 'CupertinoButton',
        'CupertinoNavigationBar', 'CupertinoSliverNavigationBar',
        'CupertinoAlertDialog', 'CupertinoActionSheet',
    ) if re.search(r'\b' + name + r'\b', source)]
    return list(uses.values()), defaults


def ratio_string(foreground: Color, background: Color) -> str:
    return f'{contrast(foreground, background):.6f}'


def token_table(values: dict[str, Color]) -> str:
    page, card, secondary = (values['LightSurfaces.' + name] for name in ('page', 'card', 'textSecondary'))
    lines = ['| token | 不透明 RGB | 对 page | 对 card | 对 textSecondary |',
             '|---|---|---:|---:|---:|']
    for name in ('page', 'card', 'cardBorder', 'divider', 'textSecondary', 'selection', 'pressed', 'placeholder',
                 'tintGreen', 'tintWarning', 'tintError', 'tintClarification', 'userDetail'):
        color = values['LightSurfaces.' + name]
        lines.append(f'| {name} | {color.display()} | {ratio_string(color, page)} | {ratio_string(color, card)} | {ratio_string(color, secondary)} |')
    return '\n'.join(lines)


def location(relative: str, needle: str) -> str:
    path = ROOT / 'lib' / relative
    source = path.read_text(encoding='utf-8')
    positions = [m.start() for m in re.finditer(re.escape(needle), source)]
    if not positions:
        raise ValueError(f'Audit source anchor missing: {relative}: {needle}')
    return f'`lib/{relative}:' + ','.join(str(source.count('\n', 0, p) + 1) for p in positions) + '`'


GROUPS = [
    ('features/chat', 'P0 聊天', '阶段二已接入局部 page/bar、可读次级文字及状态色、输入框/工具/审批/注入卡/媒体占位轮廓和选中按下面。assistant 正文仍直接落在页面底；共享 Markdown 默认不影响记忆和文件预览。用户主蓝气泡是 Leader 授权保留项；代码、链接、附件和引用局部底单独达 AA。确认弹窗仅调整浅色动作文字，保留 SDK 暗色默认。完整组合与限制见附录 P0。'),
    ('app/shell', 'P1 自适应外壳', '会话侧边栏中的列表已通过页面局部主题接入；侧边栏工具条、拖拽手柄、空态占位与导航仍沿用旧色。工具条 inactive 图标使用半透明 secondaryLabel，空态 tertiaryLabel 是弱装饰图标；可读提示使用相同次级色时不能套用装饰豁免。建议独立处理工具条/导航/空态，影响全部宽屏路由，不在阶段一改全局主题。'),
    ('app/widgets', 'P1 通用导航、菜单和浮层', '白浮层由 systemBackground 承载，separator / systemGrey4 做边框，systemGrey3 透明阴影。菜单副标题 secondaryLabel 与 destructiveRed 小字需处理；先定义可复用的面、正文及危险操作语义，再迁移调用点。预计覆盖所有弹层/菜单/导航入口；默认半透明遮罩和阴影须独立审计，不当成文字色。'),
    ('features/kanban', 'P2 看板', '卡片 secondarySystemBackground 与旧分组页面底同为浅灰，不能形成卡片层级；灰色描边只提供弱轮廓。顶部选中标签为蓝底白字，详情/元数据 secondaryText，failed 状态仍返回 systemRed。建议白卡+轮廓、可读状态文字、选择状态和详情空占位一起迁移；预计涉及看板列/卡片/详情/创建弹层，不涉及 WS 或排序逻辑。'),
    ('features/insights', 'P2 洞察/用量', '分组统计卡继承白卡，secondaryText 用于时间、说明及坐标轴；蓝色柱本身可按非文本图形判级，但轴标签仍须正文 AA。#004999 是柱图触摸态，属于数据图形，不能当浅色卡片替换。建议卡片轮廓及轴标签优先，保留现有柱形高亮；预计影响统计总览、模型列表及日用量图。'),
    ('features/settings', 'P3 设置及全部子区', 'settings_page / settings_subpages / profile / extensions / MCP / auxiliary_models / webui_sidecar 都继承分组面。先修服务器地址、说明、辅助模型元数据以及输入框 placeholder；各状态色虽有 AA 版，仍要核对 resolve 与真实背景。新增面令牌按子区接入，影响全部设置表单、子页和弹层；不改持久化键或文案。'),
    ('features/onboarding', 'P4 引导页、连接向导与安装向导', 'hero 中 #E5E5EA 是品牌图标承载面，柔光/轨道/配准线为 ExcludeSemantics 内的装饰，不承担表单可读性；保持动画设计，不用提高装饰对比度替代文字修复。优先修连接表单 placeholder、说明、错误/步骤状态和安装日志的真实承载面。预计影响宽屏品牌/表单双栏及窄屏连接表单，保持 reduceMotion 和窄屏几何。'),
    ('features/workspace', '后续 会话工作区', '文件列表、空态和选中文件信息仍使用分组面及 secondaryText。建议白卡轮廓、可读的文件大小/路径/空态提示；选中态和媒体反色控件单列。影响单会话浏览/上传/预览，不改文件/API 操作。'),
    ('features/workspace_manager', '后续 工作区管理及共享文件预览', '注册表、添加 Sheet、文件预览正文分属不同承载面。预览代码背景 systemGrey6 与页面灰接近；多媒体黑底上的白字属于反色 UI，保留语义并按实际黑底测量。建议目录/路径/元数据先修，office/媒体预览单独做视觉验收。影响注册表及聊天附件/下载复用的预览入口。'),
    ('features/git', '后续 Git 面板', '分组列表、分支树、diff 增删及操作提示存在多套灰阶与状态色。优先次级元数据和 diff 正文对比度，新增白卡描边；状态圆点不能替代文件变更文字语义。影响分支、状态和差异视图，不改 Git 操作。'),
    ('features/skills', '后续 技能', '白色分组列表/搜索与灰色摘要，空态图标和说明须分别判级。建议摘要、路径和 placeholder 使用达标次级文字，白卡补轮廓。影响技能列表/详情及搜索。'),
    ('features/memory', '后续 记忆', '分组卡、记忆编辑框、覆盖提示、字数和空态共享次级灰。建议可读文字与装饰分隔分开，编辑背景和 placeholder 配套修复。影响记忆列表与编辑表单，不改写入行为。'),
    ('features/tasks', '后续 定时任务', '列表和编辑/详情页继承 Cupertino 分组面，副标题及参数提示使用 secondaryText；状态颜色按文字和图标分别核对。建议卡片轮廓、次级文字、输入占位依次落地。影响任务列表/创建/详情。'),
    ('features/projects', '后续 项目选择 Sheet', '主要使用标准 Cupertino 列表与输入控件，显式颜色少不代表没有默认 placeholder/按下色。建议随通用 Sheet 令牌迁移；影响项目选择、新建及移动会话入口。'),
    ('features/prompts', '后续 提示词库', '收藏列表/编辑 Sheet 的 secondaryLabel、搜索占位和空态需随白卡一起迁移。影响聊天输入栏提示词选择和编辑，不改收藏内容。'),
    ('features/downloads', '后续 下载', '灰色进度轨道、白卡和多类状态色共存；文件路径/字节进度 secondaryLabel 未达正文 AA。进度轨道属于非文本对照物，按钮白图标需按其真实底色判定。建议先修可读元数据，保留下载状态机。'),
    ('features/diagnostics', '后续 诊断及详情 Sheet', '日志级别、筛选标签、展开箭头、代码/复制区共享灰面，动态级别 tint 叠加透明底。建议逐级别测量真实 tint/background 组合，修时间、来源、正文灰。影响诊断列表及详情，不改日志采集。'),
    ('features/notifications', '后续 通知浮条与后台保活设置', '应用内通知白卡、次级消息和关闭图标需迁移；系统通知平台外观不属于 lib 静态页面面色。保活说明/错误状态仍按正文核对。影响 in-app 通知及保活设置，系统通知发送不动。'),
    ('features/shared', '共享组件', 'AppBackButton / app_navigation 复用框架/通用导航，无独立颜色常量；继承导航动作色和禁用色，随 P1 验收。'),
    ('features/desktop', '桌面能力', '本目录是窗口、托盘、快捷键及启动服务，没有 Flutter 页面面色；桌面设置的 UI 在 settings 中审计，托盘操作系统主题不由这里的 Dart Color 控制。'),
    ('features/webui_sidecar', '内置服务', '配置、状态模型、Provider 与服务，无独立 Flutter 面色；可见设置区在 settings/webui_sidecar_section.dart，引导入口在 onboarding/widgets/builtin_tab.dart。'),
    ('features/session_list', '阶段一 会话列表', '主列表、紧凑侧栏复用区、搜索框、菜单图标、副标题、选中/按下态、筛选弹层、批量栏和 FAB 工作区浮层按浅色令牌接入。session_list_header 不改源码，由页面局部 bar/page 主题消费；scheduled_session_disclosure 是弃用兼容组件，仍同步修正计数和标题。下面暗色原值/反色 tooltip 另有明确豁免，业务状态与分组逻辑不改。'),
    ('app/theme', '共用主题与语义令牌', '全局主题保持原样，仅新建 LightSurfaces opt-in 层。旧 status_colors 注释不作数字来源：以源码 ARGB 实算。状态色在白卡达标不代表叠加任意彩色面也达标；secondaryText 的 alpha 必须先合成。'),
    ('app/locale', '本地化', '语言 Provider/Resolver，无颜色或可视页面；不改文案。'),
    ('app', '应用壳接线', 'CupertinoApp 使用 buildCupertinoTheme；Material 桥接在 main.dart，不是本轮功能页改造范围。这里只读审计，保留路由/本地化/启动逻辑。'),
    ('main.dart', '启动与 Material 桥接', 'Material 桥接把 Cupertino 的面和语义色传给依赖组件；错误页/详情使用红色文字与反色按钮。属于允许的壳桥接例外，不据此向业务 UI 引入 Material。'),
    ('core', '核心层', '模型/API/缓存不渲染 UI。accessibility.dart 的 AccessibleButton 复用 CupertinoButton 颜色；数据解析中的整数不是颜色。'),
]


def group_of(path: Path) -> str:
    relative = path.relative_to(ROOT / 'lib').as_posix()
    for key, _, _ in GROUPS:
        if relative == key or relative.startswith(key + '/'):
            return key
    return 'core'


def grade(use: Use, page: Color, card: Color) -> str:
    if '豁免' in use.role:
        return use.role
    if use.note:
        return use.note
    if use.role.startswith('面'):
        return '装饰面豁免；分层强弱见三向值'
    limit = 3 if use.role == '图标/图形' else 4.5
    a = '达' if contrast(use.color, page) >= limit else '不达'
    b = '达' if contrast(use.color, card) >= limit else '不达'
    return f'{"非文本" if limit == 3 else "正文 AA"}：页面{a} / 白卡{b}；反色见局部组合'


def local_pairs(values: dict[str, Color]) -> list[tuple[str, Color, Color, str, str]]:
    v = values
    white, black = hex_color('FFFFFF'), hex_color('000000')
    page = v['CupertinoColors.systemGroupedBackground']
    blue = v['CupertinoColors.activeBlue']
    pairs = []
    def add(name: str, fg: Color, bg: Color, role: str, source: str) -> None:
        pairs.append((name, fg, bg, role, source))
    for bg_name, bg in [('旧页面', page), ('白卡', white), ('新页面', v['LightSurfaces.page'])]:
        for name in ('label', 'secondaryLabel', 'tertiaryLabel', 'placeholderText', 'systemGrey', 'activeBlue'):
            add(f'{bg_name}/{name}', v['CupertinoColors.' + name], bg, '文字', 'Flutter colors.dart + 默认控件')
    for name in ('statusGreenText', 'statusOrangeText', 'statusBlueText', 'statusGreyText', 'statusTealText', 'statusRedText', 'secondaryText', '_statusDebugText'):
        for bg_name, bg in [('页面', page), ('白卡', white)]:
            add(f'{name}/{bg_name}', v[name], bg, '文字', 'status_colors.dart / diagnostics_models.dart')
    add('聊天用户气泡/正文', white, blue, '品牌保留', 'chat/widgets/message_bubble.dart + markdown_styles.dart')
    for alpha in (0.22, 0.15, 0.12):
        add(f'旧方案参考/用户白色代码或引用底 α={alpha}', white, white.alpha(alpha).over(blue), '文字', 'chat/widgets/markdown_styles.dart')
    add('非聊天共享默认/assistant 代码引用', black, v['CupertinoColors.systemGrey5'], '文字', 'chat/widgets/markdown_styles.dart')
    add('绿色提示卡/正文', black, v['LightSurfaces.tintGreen'], '文字', 'chat/chat_page.dart bgColor')
    add('绿色提示卡/装饰勾', v['statusGreenText'], v['LightSurfaces.tintGreen'], '装饰', 'chat/chat_page.dart：已有文字重复语义')
    add('绿色提示卡/灰色关闭图标', v['LightSurfaces.textSecondary'], v['LightSurfaces.tintGreen'], '图标', 'chat/chat_page.dart')
    for name, alpha in [('systemBlue', 0.1), ('systemRed', 0.1), ('systemIndigo', 0.12)]:
        c = v['CupertinoColors.' + name]
        add(f'旧方案参考/聊天提示条/{name}', c, c.alpha(alpha).over(page), '文字', 'chat/chat_page.dart')
    # Phase-two assertions use the actual opaque local surfaces, not a generic white reference.
    for surface in ('page', 'card', 'selection', 'pressed', 'tintGreen',
                    'tintWarning', 'tintError', 'tintClarification'):
        bg = v['LightSurfaces.' + surface]
        add(f'P0/textSecondary/{surface}', v['LightSurfaces.textSecondary'], bg,
            '文字', 'chat_page + chat/widgets: metadata, fields, cards, menu selections')
        add(f'P0/cardBorder/{surface}', v['LightSurfaces.cardBorder'], bg,
            '装饰', 'chat cards/fields: 0.5-1 logical pixel hairline')
    for name in ('inline code', 'code block', 'link', 'attachment', 'blockquote'):
        add(f'P0/user detail/{name}', white, v['LightSurfaces.userDetail'],
            '文字', 'chat/widgets/markdown_styles.dart + chat_media_view.dart')
    for fg, bg, name in (
        ('statusOrangeText', 'tintWarning', 'approval + queued warning'),
        ('statusOrangeText', 'tintClarification', 'urgent clarification timer'),
        ('statusGreenText', 'tintGreen', 'success tool/notice'),
        ('statusRedText', 'tintError', 'failed tool/error banner'),
        ('statusBlueText', 'selection', 'offline banner/selected menu'),
        ('statusBlueText', 'page', 'assistant link'),
        ('statusBlueText', 'card', 'tool name + selected context title'),
    ):
        add(f'P0/{name}', v[fg], v['LightSurfaces.' + bg], '文字',
            'chat_page + chat/widgets: light-only status colors')
    dialog_backdrop = v['SDK/route.dart#kCupertinoModalBarrierColor'].over(v['LightSurfaces.page'])
    for state, token in [('normal', '_kDialogColor'), ('pressed', '_kDialogPressedColor')]:
        bg = v['SDK/dialog.dart#' + token].over(dialog_backdrop)
        for fg in ('statusBlueText', 'statusRedText'):
            add(f'P0/dialog {state}/{fg}', v[fg], bg, '文字',
                'SDK dialog surface over modal scrim + uniform chat page; arbitrary backdrop is not certified')
    add('P0/clarification title', v['CupertinoColors.systemIndigo'],
        v['LightSurfaces.tintClarification'], '文字', 'chat/chat_page.dart')
    add('P0/context warning ring', v['statusOrangeText'], v['LightSurfaces.page'],
        '图标', 'chat/widgets/context_window_indicator.dart')
    add('P0/media inverse secondary', v['CupertinoColors.systemGrey'], black,
        '文字', 'chat/widgets/chat_media_view.dart: fixed black lightbox, unchanged')
    add('P0/green notice layering', v['LightSurfaces.tintGreen'], v['LightSurfaces.page'],
        '装饰', 'chat/chat_page.dart: paired with the explicit hairline')
    add('看板选中标签/白字', white, blue, '文字', 'kanban/kanban_page.dart')
    add('看板卡片/secondaryText', v['secondaryText'], v['CupertinoColors.secondarySystemBackground'], '文字', 'kanban/kanban_page.dart')
    add('看板黄色提醒/正文', black, v['CupertinoColors.systemYellow'].alpha(0.2).over(page), '文字', 'kanban/kanban_page.dart')
    for tint in ('statusGreyText', '_statusDebugText', 'statusBlueText', 'statusOrangeText', 'statusRedText'):
        add(f'诊断日志级别标签/{tint}', v[tint], v[tint].alpha(0.15).over(white), '文字', 'diagnostics/diagnostics_detail_sheet.dart + diagnostics_models.dart')
    for bg_name, bg in [('页面', page), ('白卡', white)]:
        add(f'默认搜索框/{bg_name}', v['CupertinoColors.secondaryLabel'], v['CupertinoColors.tertiarySystemFill'].over(bg), '文字', 'SDK/search_field.dart')
    add('默认列表按下行/secondaryLabel', v['CupertinoColors.secondaryLabel'], v['CupertinoColors.systemGrey4'], '文字', 'SDK/list_tile.dart')
    for name, bg in [(n, c) for n, c in v.items()
                     if n.startswith('SDK/dialog.dart#') and 'Text' not in n and 'Divider' not in n]:
        add(f'框架弹层/label · {name}', black, bg.over(page), '文字', 'SDK/dialog.dart；以均匀旧页面作模糊下层参考')
    sheet_bg = v['SDK/dialog.dart#_kActionSheetBackgroundColor'].over(page)
    add('默认 ActionSheet 内容灰字', v['SDK/dialog.dart#_kActionSheetContentTextColor'], sheet_bg, '文字', 'SDK/dialog.dart；以均匀旧页面作模糊下层参考')
    add('用量柱形/默认蓝', v['CupertinoColors.systemBlue'], white, '图形', 'insights/insights_page.dart')
    add('用量柱形/触摸深蓝', hex_color('004999'), white, '图形', 'insights/insights_page.dart')
    add('品牌图标承载面/黑色图标', black, hex_color('E5E5EA'), '图标', 'onboarding/widgets/onboarding_hero_motion.dart')
    add('Mermaid 深色节点/白字', white, hex_color('2C2C2E'), '配置豁免', 'chat/widgets/mermaid_block.dart：非浅色 UI 面')
    add('Mermaid 深色 cluster/白字', white, hex_color('1C1C1E'), '配置豁免', 'chat/widgets/mermaid_block.dart：非浅色 UI 面')
    for bg_name, bg in [('新页面', v['LightSurfaces.page']), ('白卡', white)]:
        add(f'会话列表反色 tooltip/{bg_name}', white, hex_color('F0000000').over(bg), '文字', 'session_list/session_list_page.dart')
        add(f'外壳反色 toast/{bg_name}', white, black.alpha(0.82).over(bg), '文字', 'app/shell/adaptive_shell.dart')
    return pairs


def render_report(values: dict[str, Color], flutter: Path) -> str:
    old_page = values['CupertinoColors.systemGroupedBackground']
    new_page = values['LightSurfaces.page']
    card, label = hex_color('FFFFFF'), hex_color('000000')
    paths = sorted((ROOT / 'lib').rglob('*.dart'))
    files = [(p, *scan_file(p, values)) for p in paths]
    color_count = sum(sum(len(u.lines) for u in uses) for _, uses, _ in files)
    version = json.loads((flutter.parent.parent / 'bin/cache/flutter.version.json').read_text(encoding='utf-8'))
    lines = [
        '# 浅色主题全仓审计 · 2026-09-12', '',
        '本报告按 TASK.md §1 的方案执行。阶段一完成令牌层和会话列表；阶段二继续 P0 聊天与 P1 外壳/导航，P2+ 页面保持只读。视觉取舍由 Leader 验收。', '',
        '## 范围与复验方法', '',
        f'- 扫描 `lib/` 全部 **{len(paths)}** 个 Dart 文件，记录 **{color_count}** 个颜色引用/常量/别名透明度使用点。按实际目录补入下载、诊断和内置服务，不沿用旧目录快照假定覆盖。',
        f'- 语义色取自 Flutter **{version["frameworkVersion"]}** / Dart **{version["dartSdkVersion"]}** 的 `packages/flutter/lib/src/cupertino/colors.dart` 普通浅色分支；增强对比度和暗色保留分支另标豁免。',
        '- WCAG：sRGB 通道 `c<=0.04045 ? c/12.92 : ((c+0.055)/1.055)^2.4`；相对亮度 `0.2126R+0.7152G+0.0722B`；比值 `(L高+0.05)/(L低+0.05)`。先按实际 alpha 在 sRGB 合成，再线性化；中间值不取整，表格保留六位小数。',
        '- 正文 AA 门槛 4.5:1，功能图标/数据图形按 3:1；纯装饰面、边框、投影不套正文 AA。低对比度卡片面仍可存在视觉分层问题，不能用“装饰豁免”宣称已经分层充分。',
        '- 逐文件表三向列为：该色合成到**页面底 P**、**白卡 C**、**黑色 label L** 后各自的对比度。会话列表与聊天 P 用新 page，其他文件 P 用现行全局分组背景。它们是明确的承载面参考值；反色内容和已知彩色组合另列附录，不能拿白字对白卡的参考值误判反色 tooltip。',
        '- 静态审计列出所有可解析颜色及来源、透明度和组件默认色。运行时透明度/任意图片内容不能由单个基色证明 AA，表中明确保留限制；本轮没有逐页启动所有状态，也不声称全仓视觉验收通过。',
        '- `python tools/light_theme_contrast.py` 输出本报告全文；`--tokens` 复算令牌注释；`--write-report` 生成文件；`--check-report` 校验报告与当前源码/SDK 完全一致。无第三方 Python 依赖。没有 `.dart_tool/package_config.json` 时可传 `--flutter-sdk <SDK根目录>`。', '',
        '## 阶段一结果及保留项', '',
        f'- page/card 的对比度由 {ratio_string(card, old_page)} 变为 {ratio_string(card, new_page)}；cardBorder 对白卡为 {ratio_string(values["LightSurfaces.cardBorder"], card)}，对新页面为 {ratio_string(values["LightSurfaces.cardBorder"], new_page)}。描边保持任务指定 #DDE0E8、0.5–1 逻辑像素，视觉差由 before/after 供 Leader 判断。',
        f'- 原候选 #6E6E73 对新页面仅 {ratio_string(hex_color("6E6E73"), new_page)}；保持 R=G、B=R+5，#6A6A6F 为最浅整字节达标值；再浅一档 #6B6B70 为 {ratio_string(hex_color("6B6B70"), new_page)}。',
        '- 新 page 仅用于会话列表和其侧栏复用区，局部导航背景同步；全局 buildCupertinoTheme 未改。白卡、搜索框、次级文案/菜单图标、过滤 Sheet、批量栏、弃用 disclosure 计数、FAB 工作区浮层接入。选中和按下反馈只在浅色分支启用。',
        '- 源码未渲染时间戳文字（时间只参与分组排序），没有为满足任务描述而新增时间戳或改业务数据流。三点菜单/副标题/置顶图标使用新次级色。',
        '- #EEFFFFFF 与 #B3FFFFFF 的普通浮层面归 card；#1F000000 作为普通浮层边框的调用归 cardBorder，作为投影的调用保留。#F0000000 是反色 tooltip，白字组合见附录，保留其语义。',
        '- 深色 helper 使用原语义色并显式 resolve；历史未 resolve 的灰图标和选中蓝图标保留原实际绘制 ARGB，避免顺手改变深色增强对比度像素。暗色路径无新增按下/选中填色。',
        '- README 截图工装原样调用，通过外部 comparator 重定向到 `C:/tmp/light-theme-shots/before/` 与 `after/`；没有写入 `docs/screenshots/`。该工装的 CupertinoApp 未接 buildCupertinoTheme，改造前页面使用其默认背景；全局主题数值以源码和正式金照为准。', '',
        '## 阶段二 P0 结果及保留项', '',
        '- 聊天页局部 page/bar 接 #EBEBF0；动作色 #005FB8，不改全局主题。次级文字、占位符、功能灰图标按各自承载面接令牌。',
        '- 审批/澄清/错误/绿色提示面固定为不透明 tint，输入框、工具卡、选中上下文、注入卡和媒体占位接白面/描边；模型/工作区/推理选择保留勾选并增加选中、按下面。',
        f'- 用户主气泡 #007AFF + 白字按 Leader 决定保留（实算 {ratio_string(card, values["CupertinoColors.activeBlue"]) }，未达正文 AA）。白字降透明度或加字重不能达到 4.5:1；代码/链接/附件/引用的局部底 #005FB8 与白字为 {ratio_string(card, values["LightSurfaces.userDetail"])}。主气泡后续可选 #006FE8（白字 {ratio_string(card, hex_color("006FE8"))}），待 Leader 裁决，未实施。',
        '- assistant Markdown 新样式由聊天调用点 useLightSurfaces 显式启用；记忆页和文件预览的共享默认保持不变。普通用户消息仍为原纯文本渲染，未改动 Markdown 触发条件。',
        '- 暗色语义色保留原 resolve；历史未解析图标保留原实际 ARGB。固定黑底媒体、Mermaid 深底配置、重复文字语义的状态圆点及装饰轨线保留且显式标注用途。',
        '- 本阶段截图目录 `C:/tmp/light-theme-shots-p2/before/`、`after/`；P0 单区留证另存 `after-p0/`。P0 验收：analyze 零告警，test 2710 passed / 8 skipped；13 张既有暗色金照、7 张 README 暗色截图和 24 张暗色状态图共 44/44 SHA256 一致。证据在 `after-p0-verification.json`，docs/screenshots 的 7 张原图未写入。',
        '- README 演示数据固定在 2026-09-12，原工装的分组时钟却读取系统日期；跨午夜后出现今天/昨天漂移。临时工装仅补 sessionListNowProvider 固定为演示日期，重录后与原始改码前暗色 PNG 字节一致；生产代码和原工装均未修改。', '',
        '## 阶段二优先级', '',
        '| 顺序 | 改法建议 | 预估影响面 |', '|---|---|---|',
        '| P0 聊天 | 蓝气泡白字/代码、可读次级文字、提示卡与工具卡轮廓 | chat_page + chat/widgets，历史/流式/输入/审批/媒体 |',
        '| P1 外壳/导航 | 工具条、空态提示、菜单文字与浮层面分开迁移 | app/shell + app/widgets，所有宽屏及弹层入口 |',
        '| P2 看板/用量 | 白卡轮廓、状态文字/轴标签、保留图形触摸态 | Kanban 主/详情/创建，Insights 总览/图表 |',
        '| P3 设置 | 次级说明、地址、placeholder，子区逐一接入 | settings 全部子页/表单及 sidecar 设置 |',
        '| P4 引导 | 表单/步骤/日志优先，hero 装饰独立评估 | onboarding 宽/窄屏、连接及安装向导 |',
        '| 后续配套 | 按共用令牌修元数据与表单，预览反色 UI 单独验收 | 工作区、Git、技能、记忆、任务、下载、诊断、通知、项目、提示词库 |', '',
        '## 硬编码定位与代码可判定的发现', '',
        f'- {location("features/chat/chat_page.dart", "LightSurfaces.tintGreen")}：绿色提示卡已接 tintGreen + cardBorder；正文、状态图标和关闭图标的实际组合见附录 P0。暗色 #2C2C2E 及原描边、投影保留。',
        f'- {location("features/onboarding/widgets/onboarding_hero_motion.dart", "0xFFE5E5EA")}：品牌图标承载面；halo 的透明渐变、轨道线在同文件 _HaloPainter 中，属无交互装饰，按设计保留/后续整体评估。',
        f'- {location("features/chat/widgets/mermaid_block.dart", "0xffffffff")}：`core.Color` 是 Mermaid 深色 theme 的 primaryText/text/title 配置，不是浅色 Flutter 卡片面，归配置豁免。',
        '- 旧 secondaryText/secondaryLabel 实际浅色是 #3C3C43/153，不符合旧注释所述正文 AA；参见附录的逐背景实算。tertiaryLabel/placeholderText 更浅；输入占位属于可读信息，不能因为名字含 tertiary 就豁免。',
        '- 主色 #007AFF 的小字号白字/蓝字也不自动满足正文 AA。阶段一保持品牌/全局按钮语义；会话搜索命中改用 statusBlueText，批量栏危险文字使用 statusRedText 的浅色分支。其他品牌动作/禁用态列入后续，不宣称会话页所有文字已全域达标。', '',
        '## 框架默认面和文字（逐文件的“默认控件”引用此表）', '',
        '| 控件/默认路径 | 来源及浅色语义 | 验证要点 |', '|---|---|---|',
        '| CupertinoPageScaffold / NavigationBar / SliverNavigationBar | buildCupertinoTheme.scaffold/bar → systemGroupedBackground；label 黑；primaryColor #007AFF | 会话列表局部 page 例外；导航底边/遮罩另算装饰 |',
        '| CupertinoListSection.insetGrouped / CupertinoListTile | 分组底 systemGroupedBackground；白卡 secondarySystemGroupedBackground；separator；label / secondaryLabel；按下 systemGrey4 | 没有显式 color 的页面也使用这些语义；选中/按下不等于卡片边框 |',
        '| CupertinoTextField | systemBackground / 默认输入框装饰，placeholderText，label；边框与光标另算 | 默认 placeholder 的 AA 数字见附录 |',
        '| CupertinoSearchTextField | tertiarySystemFill 透明面，secondaryLabel 占位和图标 | 会话列表已显式白底+placeholder；其余按各页面底合成 |',
        '| CupertinoButton / filled / AccessibleButton | primaryColor 动作字或按钮底，primaryContrastingColor 白字；禁用色由框架控制 | 普通动作正文、白字按钮、图标和禁用态分开验收 |',
        '| CupertinoAlertDialog / CupertinoActionSheet / ModalPopup | SDK 动态背景/模糊/遮罩；label、destructiveRed、primaryColor | 透明背景/模糊须结合下层截图，不能静态保证所有任意下层 AA |', '',
        '## 逐页、逐组件源色清单', '',
        '每个表包含该文件的所有可解析显式颜色（含定义、分支和透明度别名），同色同用途合并行号。无显式颜色的 UI 文件仍列出默认控件；纯逻辑文件也单列覆盖清单。表内“复用色”按普通文字做保守的承载面参考，具体反色或非文本用途依局部组合/说明判定。', '',
    ]
    for group, title, note in GROUPS:
        members = [(p, u, d) for p, u, d in files if group_of(p) == group]
        if not members:
            continue
        lines.extend([f'### {title}', '', note, ''])
        logic = []
        for path, uses, defaults in members:
            relative = path.relative_to(ROOT).as_posix()
            if not uses and not defaults:
                logic.append(f'`{relative}`')
                continue
            lines.extend([f'#### `{relative}`', ''])
            if defaults:
                lines.extend(['默认控件：' + '、'.join(f'`{d}`' for d in defaults) + '。', ''])
            if not uses:
                lines.extend(['无额外显式颜色，继承上表语义。', ''])
                continue
            page = new_page if group in ('features/session_list', 'features/chat') else old_page
            lines.extend([f'参考页面 P={page.display()}；C=#FFFFFF；L=#000000。', '',
                          '| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |',
                          '|---|---|---|---:|---:|---:|---|'])
            for use in uses:
                refs = ','.join(map(str, sorted(set(use.lines))))
                name = use.name.replace('|', '\\|')
                lines.append(f'| `{name}` L{refs} | {use.role} | {use.color.display()} | {ratio_string(use.color, page)} | {ratio_string(use.color, card)} | {ratio_string(use.color, label)} | {grade(use, page, card)} |')
            lines.append('')
        if logic:
            lines.extend(['无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：' + '、'.join(logic) + '。', ''])
    lines.extend(['## 附录：脚本实算输出', '',
                  '以下表与上文逐页数字全部由同一脚本输出，正文不手填比值。执行默认命令输出本报告全文，`--check-report` 会进行全文比对。', '',
                  '### A. 浅色令牌三向矩阵', '', token_table(values), '',
                  '### B. 实际局部组合与通用语义色', '',
                  '“面/旧页面”用于看层级；“字/旧页面”用于复核上下文；AA 按“字/实际面”判级。RGB 展示为最接近整字节，计算仍使用未经取整的 alpha 合成结果。', '',
                  '| 组合 / 来源 | 前景 | 实际承载面 | 面/旧页面 | 字/旧页面 | 字/实际面 | 判级 |',
                  '|---|---|---|---:|---:|---:|---|'])
    for name, fg, bg, role, source in local_pairs(values):
        ratio = contrast(fg, bg)
        threshold = 3 if role in ('图标', '图形') else 4.5
        result = ('装饰豁免' if role in ('装饰', '配置豁免')
                  else f'{"非文本" if threshold == 3 else "正文 AA"} {"达" if ratio >= threshold else "不达标"}')
        if role == '品牌保留':
            result = '正文 AA 不达标；Leader 指定保留主气泡'
        if role == '配置豁免':
            result = '深色图表配置豁免'
        lines.append(f'| {name} · `{source}` | {fg.display()} | {bg.display()} | {ratio_string(bg, old_page)} | {ratio_string(fg, old_page)} | {ratio:.6f} | {result} |')
    lines.extend(['', '### C. SDK 默认面、控件文字与装饰实算', '',
                  '私有默认常量从上述同一 SDK 自动读取；动态背景按页面/白卡/黑色三个均匀下层分别合成。渐变/模糊上叠加任意内容时，仍需实际画面复核。', '',
                  '| SDK 来源 | RGB / alpha | 对页面 | 对白卡 | 对黑色 | 用途 |',
                  '|---|---|---:|---:|---:|---|'])
    for name, color in sorted(values.items()):
        if not name.startswith('SDK/'):
            continue
        role = ('文字：按实际面 AA' if 'TextColor' in name or 'HeaderFooter' in name
                else '功能图标：3:1' if 'ClearButton' in name
                else '装饰面/边框/状态背景豁免')
        lines.append(f'| `{name}` | {color.display()} | {ratio_string(color, old_page)} | {ratio_string(color, card)} | {ratio_string(color, label)} | {role} |')
    lines.extend(['', '### D. 复验边界', '',
                  'AA 数字评估的是指定颜色组合，不能代替字体大小/字重、模糊下层、动态透明度、照片内容或系统级通知的视觉验证。阶段一的截图和暗色比对证据在任务临时目录；全仓其余页本轮只读，下一阶段按优先级迁移并补对应状态截图。', ''])
    return '\n'.join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter-sdk')
    action = parser.add_mutually_exclusive_group()
    action.add_argument('--tokens', action='store_true')
    action.add_argument('--write-report', action='store_true')
    action.add_argument('--check-report', action='store_true')
    args = parser.parse_args()
    flutter = sdk_path(args.flutter_sdk)
    values = palette(flutter)
    if args.tokens:
        print(token_table(values))
        return
    report = render_report(values, flutter)
    if args.write_report:
        REPORT.write_bytes(report.encode('utf-8'))
        print(f'Wrote {REPORT} ({len(report.splitlines())} lines)')
    elif args.check_report:
        for name, fg, bg, role, _ in local_pairs(values):
            if name.startswith(('P0/', 'P1/')) and role not in ('装饰', '配置豁免'):
                limit = 3 if role in ('图标', '图形') else 4.5
                if contrast(fg, bg) < limit:
                    raise SystemExit(f'FAIL: {name}: {contrast(fg, bg):.6f} < {limit}')
        if REPORT.read_text(encoding='utf-8') != report:
            raise SystemExit('Report differs from current source/SDK. Re-run --write-report.')
        print(f'PASS: all report text, source locations and ratios reproduced ({len(report.splitlines())} lines).')
    else:
        print(report, end='')


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    main()
