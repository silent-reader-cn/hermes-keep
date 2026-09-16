import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/core/models/json_value.dart';
import 'package:hermes_ui/core/models/tool_call.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

/// `tool_call.dart` 覆盖率补强 · 批次 TC1：`ToolCallGroup` 基础段（行 188–352）。
///
/// 覆盖：构造器（188）/ 字段（196–205）/ `copyWith`（207，逐参数三态）/
/// `activityTitle`（224，全分支）/ `localizedActivityTitle`（239，中英两路）/
/// `isComplete`（271）/ `hasFailedTool`（274）/ `mergedWith`（282）/
/// `live`（286）/ `groups`（306）与引用相等阶梯。
///
/// 预期值全部按实现读出来写死，不用空断言充数。**不触碰** 12–186 与 354+ 区间。
const AppLocalizations _zh = AppLocalizations(Locale('zh'));
const AppLocalizations _en = AppLocalizations(Locale('en'));

/// 便捷构造：`id` 缺省时由 [ToolCall] 自行生成（`live-tool-<uuid>`）。
/// `startedAt` 固定为 1.0：`ToolCall.==` 含该时间戳，钉死才能构造「内容相等」的对照件。
ToolCall _call(
  String? name, {
  String? id,
  bool completed = true,
  bool? isError,
  String? thinking,
  double startedAt = 1,
}) => ToolCall(
  id: id,
  name: name,
  isCompleted: completed,
  isError: isError,
  thinking: thinking,
  startedAt: startedAt,
);

void main() {
  group('ToolCallGroup 构造器 / 字段', () {
    test('缺省 id 自动生成 uuid v4 形状，方向字段落默认值，toolCalls 保持实例', () {
      final calls = <ToolCall>[_call('bash')];
      final group = ToolCallGroup(toolCalls: calls);

      expect(
        group.id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
            r'[0-9a-f]{12}$',
          ),
        ),
      );
      expect(group.anchorMessageID, isNull);
      expect(group.precedingMessageID, isNull);
      expect(group.isAboveContent, isFalse);
      expect(identical(group.toolCalls, calls), isTrue);

      // 每次构造各自取新 uuid。
      expect(ToolCallGroup(toolCalls: calls).id == group.id, isFalse);
    });

    test('显式 id 与全部方向字段逐字段落位', () {
      final group = ToolCallGroup(
        id: 'group-a',
        anchorMessageID: 'm1',
        precedingMessageID: 'm0',
        isAboveContent: true,
        toolCalls: const [],
      );

      expect(group.id, 'group-a');
      expect(group.anchorMessageID, 'm1');
      expect(group.precedingMessageID, 'm0');
      expect(group.isAboveContent, isTrue);
      expect(group.toolCalls, isEmpty);
    });

    test('toolCalls 为可变列表时保持同一引用（不做防御性拷贝）', () {
      final calls = <ToolCall>[_call('bash')];
      final group = ToolCallGroup(toolCalls: calls);
      calls.add(_call('read_file'));

      expect(group.toolCalls, hasLength(2));
      expect(group.toolCalls.last.name, 'read_file');
    });
  });

  group('ToolCallGroup.copyWith（逐参数三态：传值 / 传 null / 不传）', () {
    final original = <ToolCall>[_call('bash', id: 't1')];
    final base = ToolCallGroup(
      id: 'g1',
      anchorMessageID: 'a1',
      precedingMessageID: 'p1',
      isAboveContent: true,
      toolCalls: original,
    );

    test('不传任何参数 → 全字段保持，toolCalls 同实例，但返回新对象', () {
      final copy = base.copyWith();

      expect(identical(copy, base), isFalse);
      expect(copy.id, 'g1');
      expect(copy.anchorMessageID, 'a1');
      expect(copy.precedingMessageID, 'p1');
      expect(copy.isAboveContent, isTrue);
      expect(identical(copy.toolCalls, original), isTrue);
    });

    test('id：传值覆盖；显式传 null 不清空（`?? this.id` 兜底）', () {
      expect(base.copyWith(id: 'g2').id, 'g2');
      expect(base.copyWith(id: null).id, 'g1');
      expect(base.copyWith(id: 'g2').anchorMessageID, 'a1');
    });

    test('anchorMessageID：传值覆盖；显式传 null 保持原值；原值为 null 时保持 null', () {
      expect(base.copyWith(anchorMessageID: 'a2').anchorMessageID, 'a2');
      expect(base.copyWith(anchorMessageID: null).anchorMessageID, 'a1');

      final unanchored = ToolCallGroup(toolCalls: const []);
      expect(unanchored.copyWith().anchorMessageID, isNull);
      expect(
        unanchored.copyWith(anchorMessageID: null).anchorMessageID,
        isNull,
      );
      expect(unanchored.copyWith(anchorMessageID: 'a9').anchorMessageID, 'a9');
    });

    test('precedingMessageID：传值覆盖；显式传 null 保持原值', () {
      expect(base.copyWith(precedingMessageID: 'p2').precedingMessageID, 'p2');
      expect(base.copyWith(precedingMessageID: null).precedingMessageID, 'p1');

      final noPreceding = ToolCallGroup(toolCalls: const []);
      expect(noPreceding.copyWith().precedingMessageID, isNull);
      expect(
        noPreceding.copyWith(precedingMessageID: 'p9').precedingMessageID,
        'p9',
      );
    });

    test('isAboveContent：true→false 覆盖；不传或传 null 时保持原布尔值', () {
      expect(base.copyWith(isAboveContent: false).isAboveContent, isFalse);
      expect(base.copyWith(isAboveContent: true).isAboveContent, isTrue);
      expect(base.copyWith(isAboveContent: null).isAboveContent, isTrue);

      final below = ToolCallGroup(toolCalls: const []);
      expect(below.copyWith().isAboveContent, isFalse);
      expect(below.copyWith(isAboveContent: null).isAboveContent, isFalse);
      expect(below.copyWith(isAboveContent: true).isAboveContent, isTrue);
    });

    test('toolCalls：传值换实例；传空列表可清空；传 null 保持原列表实例', () {
      final replacement = <ToolCall>[_call('read_file', id: 't2')];

      expect(
        identical(base.copyWith(toolCalls: replacement).toolCalls, replacement),
        isTrue,
      );
      expect(base.copyWith(toolCalls: const <ToolCall>[]).toolCalls, isEmpty);
      expect(
        identical(base.copyWith(toolCalls: null).toolCalls, original),
        isTrue,
      );
      expect(base.copyWith(toolCalls: replacement).toolCalls, hasLength(1));
    });

    test('只改一项时其余字段原样携带（逐字段核对）', () {
      final copy = base.copyWith(id: 'g3');

      expect(copy.id, 'g3');
      expect(copy.anchorMessageID, 'a1');
      expect(copy.precedingMessageID, 'p1');
      expect(copy.isAboveContent, isTrue);
      expect(identical(copy.toolCalls, original), isTrue);
    });
  });

  group('ToolCallGroup.isComplete / hasFailedTool', () {
    test('空列表：every 空真值 → isComplete = true，hasFailedTool = false', () {
      final group = ToolCallGroup(toolCalls: const []);

      expect(group.isComplete, isTrue);
      expect(group.hasFailedTool, isFalse);
    });

    test('全部已完成 → true；任一条未完成 → false', () {
      final allDone = ToolCallGroup(
        toolCalls: [
          _call('bash', id: 't1'),
          _call('read_file', id: 't2'),
        ],
      );
      expect(allDone.isComplete, isTrue);

      final partial = ToolCallGroup(
        toolCalls: [
          _call('bash', id: 't1'),
          _call('read_file', id: 't2', completed: false),
        ],
      );
      expect(partial.isComplete, isFalse);

      // 未完成项在末尾也照判（every 短路到最后一项）。
      final tailPending = ToolCallGroup(
        toolCalls: [
          _call('bash', id: 't1', completed: true),
          _call('read_file', id: 't2', completed: true),
          _call('grep', id: 't3', completed: false),
        ],
      );
      expect(tailPending.isComplete, isFalse);
    });

    test('思考子卡行（ToolCall.thinking 出厂即完成）计入 isComplete', () {
      final withThinking = ToolCallGroup(
        toolCalls: [
          ToolCall.thinking('先看目录'),
          _call('bash', id: 't1'),
        ],
      );
      expect(withThinking.toolCalls.first.isThinking, isTrue);
      expect(withThinking.isComplete, isTrue);

      final thinkingPlusPending = ToolCallGroup(
        toolCalls: [
          ToolCall.thinking('先看目录'),
          _call('bash', id: 't1', completed: false),
        ],
      );
      expect(thinkingPlusPending.isComplete, isFalse);
    });

    test('hasFailedTool：isError == true 命中；false / null / 空列表不命中', () {
      expect(
        ToolCallGroup(
          toolCalls: [
            _call('bash', id: 't1'),
            _call('read_file', id: 't2', isError: true),
          ],
        ).hasFailedTool,
        isTrue,
      );
      expect(
        ToolCallGroup(toolCalls: [_call('bash', id: 't1', isError: false)])
            .hasFailedTool,
        isFalse,
      );
      // isError 缺省为 null：不得当作失败。
      expect(
        ToolCallGroup(toolCalls: [_call('bash', id: 't1')]).hasFailedTool,
        isFalse,
      );
      expect(ToolCallGroup(toolCalls: const []).hasFailedTool, isFalse);
    });

    test('报错与完成互相独立：失败但已完成 → isComplete true 且 hasFailedTool true', () {
      final failed = ToolCallGroup(
        toolCalls: [_call('bash', id: 't1', isError: true)],
      );
      expect(failed.isComplete, isTrue);
      expect(failed.hasFailedTool, isTrue);
    });
  });

  // 注：`==` / `hashCode` / `toString` 的实现体在 1561–1585（`ToolCallGroup` 尾部，
  // 属「354+」区间的另一作业面）；本组按任务书 §3 的「阶梯式」要求逐字段打穿。
  group('ToolCallGroup 值相等阶梯（== / hashCode / toString）', () {
    test('全字段相同 → 相等（不同实例）；自反；跨类型不等', () {
      final lhs = ToolCallGroup(
        id: 'same',
        anchorMessageID: 'a1',
        precedingMessageID: 'p1',
        isAboveContent: true,
        toolCalls: [_call('bash', id: 't1')],
      );
      final rhs = ToolCallGroup(
        id: 'same',
        anchorMessageID: 'a1',
        precedingMessageID: 'p1',
        isAboveContent: true,
        toolCalls: [_call('bash', id: 't1')],
      );

      expect(identical(lhs, rhs), isFalse);
      expect(lhs == rhs, isTrue);
      expect(rhs == lhs, isTrue);
      expect(lhs == lhs, isTrue);
      expect(lhs == Object(), isFalse);
      expect(lhs.hashCode == rhs.hashCode, isTrue);
    });

    test(
      '逐字段改一项即不等：id / anchorMessageID / precedingMessageID / isAboveContent',
      () {
        const calls = <ToolCall>[];
        final base = ToolCallGroup(
          id: 'g1',
          anchorMessageID: 'a1',
          precedingMessageID: 'p1',
          isAboveContent: true,
          toolCalls: calls,
        );

        ToolCallGroup withOnly({
          String? id,
          String? anchor,
          String? preceding,
          bool? above,
        }) => ToolCallGroup(
          id: id ?? 'g1',
          anchorMessageID: anchor ?? 'a1',
          precedingMessageID: preceding ?? 'p1',
          isAboveContent: above ?? true,
          toolCalls: calls,
        );

        expect(base == withOnly(id: 'g2'), isFalse);
        expect(base == withOnly(anchor: 'a2'), isFalse);
        // 对照：anchor 置 null 与 'a1' 必须区分（null 亦参与比对）。
        expect(
          base ==
              ToolCallGroup(
                id: 'g1',
                precedingMessageID: 'p1',
                isAboveContent: true,
                toolCalls: calls,
              ),
          isFalse,
        );
        expect(base == withOnly(preceding: 'p2'), isFalse);
        expect(
          base ==
              ToolCallGroup(
                id: 'g1',
                anchorMessageID: 'a1',
                isAboveContent: true,
                toolCalls: calls,
              ),
          isFalse,
        );
        expect(base == withOnly(above: false), isFalse);
        expect(
          base ==
              ToolCallGroup(
                id: 'g1',
                anchorMessageID: 'a1',
                precedingMessageID: 'p1',
                toolCalls: calls,
              ),
          isFalse,
        );
        expect(base == withOnly(), isTrue);
      },
    );

    test('copyWith 产物：非同一实例但相等（与本体字段全同）', () {
      final group = ToolCallGroup(
        id: 'g1',
        anchorMessageID: 'a1',
        precedingMessageID: 'p1',
        isAboveContent: true,
        toolCalls: [_call('bash', id: 't1')],
      );
      final copy = group.copyWith();

      expect(identical(copy, group), isFalse);
      expect(copy == group, isTrue);
      expect(copy.hashCode == group.hashCode, isTrue);
    });

    test('hashCode：相等对象同 hash，同一实例稳定', () {
      final group = ToolCallGroup(id: 'g1', toolCalls: const []);
      expect(group.hashCode, group.hashCode);
      expect(group.hashCode, isA<int>());

      expect(
        ToolCallGroup(id: 'g1', toolCalls: const []).hashCode,
        ToolCallGroup(id: 'g1', toolCalls: const []).hashCode,
      );
    });

    test('toString 逐字段复读（含 toolCalls 数量）', () {
      expect(
        ToolCallGroup(id: 'g1', toolCalls: const []).toString(),
        'ToolCallGroup(id: g1, anchorMessageID: null, preceding: null, '
        'isAbove: false, toolCalls: 0)',
      );
      expect(
        ToolCallGroup(
          id: 'g2',
          anchorMessageID: 'a1',
          precedingMessageID: 'p1',
          isAboveContent: true,
          toolCalls: [
            _call('bash', id: 't1'),
            _call('grep', id: 't2'),
          ],
        ).toString(),
        'ToolCallGroup(id: g2, anchorMessageID: a1, preceding: p1, '
        'isAbove: true, toolCalls: 2)',
      );
    });

    test('toolCalls 阶梯：null 保持 ↔ 空列表 ↔ 长度不同 ↔ 元素不同 ↔ 同实例', () {
      final one = <ToolCall>[_call('bash', id: 't1')];
      final oneSameContent = <ToolCall>[_call('bash', id: 't1')];
      final two = <ToolCall>[_call('bash', id: 't1'), _call('grep', id: 't2')];
      final otherName = <ToolCall>[_call('read_file', id: 't1')];
      final otherStartedAt = <ToolCall>[_call('bash', id: 't1', startedAt: 2)];
      final empty = <ToolCall>[];
      final base = ToolCallGroup(
        id: 'g1',
        anchorMessageID: 'a1',
        toolCalls: one,
      );

      // （1）同实例 / 「内容相等」的另一列表 → 组相等（deepEquals 逐元素比对）。
      expect(identical(base.copyWith(toolCalls: one).toolCalls, one), isTrue);
      expect(base == base.copyWith(toolCalls: oneSameContent), isTrue);
      expect(identical(one, oneSameContent), isFalse);
      // （2）传 null → 保持原列表实例。
      expect(identical(base.copyWith(toolCalls: null).toolCalls, one), isTrue);
      expect(base == base.copyWith(toolCalls: null), isTrue);
      // （3）空列表 ↔ 非空 → 不等；空 ↔ 空 → 相等。
      expect(base == base.copyWith(toolCalls: empty), isFalse);
      expect(
        ToolCallGroup(id: 'g1', anchorMessageID: 'a1', toolCalls: empty) ==
            ToolCallGroup(
              id: 'g1',
              anchorMessageID: 'a1',
              toolCalls: const <ToolCall>[],
            ),
        isTrue,
      );
      // （4）长度不同 → 不等（1 vs 2）。
      expect(base == base.copyWith(toolCalls: two), isFalse);
      expect(
        base.copyWith(toolCalls: two) ==
            base.copyWith(toolCalls: two.sublist(0, 1)),
        isFalse,
      );
      // （5）长度相同、元素不同：name 与 startedAt 各自成例 → 不等。
      expect(base == base.copyWith(toolCalls: otherName), isFalse);
      expect(base == base.copyWith(toolCalls: otherStartedAt), isFalse);
      expect(one.first == otherName.first, isFalse);
      expect(one.first == otherStartedAt.first, isFalse);
    });
  });

  group('ToolCallGroup.activityTitle（按首次出现顺序取前 3 个「不同名」）', () {
    test('空列表 → No tools', () {
      expect(ToolCallGroup(toolCalls: const []).activityTitle, 'No tools');
    });

    test('唯一名集合大小 1 → `Activity: 1 tool`（多个同名调用也算 1 种工具）', () {
      expect(
        ToolCallGroup(toolCalls: [_call('bash', id: 't1')]).activityTitle,
        'Activity: 1 tool',
      );
      expect(
        ToolCallGroup(
          toolCalls: [
            _call('bash', id: 't1'),
            _call('bash', id: 't2'),
            _call('bash', id: 't3'),
          ],
        ).activityTitle,
        'Activity: 1 tool',
      );
    });

    test('2 / 3 个不同名 → 逗号连接，无 +N（remaining = 0 分支）', () {
      expect(
        ToolCallGroup(
          toolCalls: [
            _call('bash', id: 't1'),
            _call('grep', id: 't2'),
          ],
        ).activityTitle,
        'bash, grep',
      );
      expect(
        ToolCallGroup(
          toolCalls: [
            _call('bash', id: 't1'),
            _call('grep', id: 't2'),
            _call('read_file', id: 't3'),
          ],
        ).activityTitle,
        'bash, grep, read_file',
      );
    });

    test('4 / 5 / 6 个不同名 → 前 3 个 + `+N`（remaining > 0 分支）', () {
      final names4 = ['a', 'b', 'c', 'd'];
      final names5 = ['a', 'b', 'c', 'd', 'e'];
      final names6 = ['a', 'b', 'c', 'd', 'e', 'f'];
      List<ToolCall> build(List<String> names) => [
        for (var i = 0; i < names.length; i++) _call(names[i], id: 't$i'),
      ];

      expect(
        ToolCallGroup(toolCalls: build(names4)).activityTitle,
        'a, b, c, +1',
      );
      expect(
        ToolCallGroup(toolCalls: build(names5)).activityTitle,
        'a, b, c, +2',
      );
      expect(
        ToolCallGroup(toolCalls: build(names6)).activityTitle,
        'a, b, c, +3',
      );
    });

    test('重名不去重计数：uniqueNames 只收首次出现的名字', () {
      expect(
        ToolCallGroup(
          toolCalls: [
            _call('a', id: 't1'),
            _call('a', id: 't2'),
            _call('b', id: 't3'),
            _call('b', id: 't4'),
            _call('c', id: 't5'),
            _call('d', id: 't6'),
          ],
        ).activityTitle,
        'a, b, c, +1',
      );
    });

    test('name 为 null / 纯空白 → 回落 displayName「Tool」并参与去重', () {
      expect(
        ToolCallGroup(toolCalls: [_call(null, id: 't1')]).activityTitle,
        'Activity: 1 tool',
      );
      expect(
        ToolCallGroup(
          toolCalls: [
            _call(null, id: 't1'),
            _call('   ', id: 't2'),
          ],
        ).activityTitle,
        'Activity: 1 tool',
      );
      expect(
        ToolCallGroup(
          toolCalls: [
            _call(null, id: 't1'),
            _call('bash', id: 't2'),
          ],
        ).activityTitle,
        'Tool, bash',
      );
    });

    test('name 首尾空白被 displayName trim 后再判重', () {
      expect(
        ToolCallGroup(
          toolCalls: [
            _call('  bash  ', id: 't1'),
            _call('bash', id: 't2'),
          ],
        ).activityTitle,
        'Activity: 1 tool',
      );
    });

    test('思考子卡行以 name「thinking」参与（activityTitle 不走 l10n）', () {
      expect(
        ToolCallGroup(
          toolCalls: [
            ToolCall.thinking('先看目录'),
            _call('bash', id: 't1'),
          ],
        ).activityTitle,
        'thinking, bash',
      );
    });
  });

  group('ToolCallGroup.localizedActivityTitle（中英两路 + 频次排序）', () {
    test('空列表 → l10n.noTools（zh 无工具 / en No tools）', () {
      final empty = ToolCallGroup(toolCalls: const []);
      expect(empty.localizedActivityTitle(_zh), '无工具');
      expect(empty.localizedActivityTitle(_en), 'No tools');
    });

    test('单条目：`名称 ×次数`（zh 终端 / en Terminal）', () {
      final group = ToolCallGroup(toolCalls: [_call('bash', id: 't1')]);
      expect(group.localizedActivityTitle(_zh), '终端 ×1');
      expect(group.localizedActivityTitle(_en), 'Terminal ×1');
    });

    test('多条同名累加次数：read_file ×3', () {
      final group = ToolCallGroup(
        toolCalls: [
          _call('read_file', id: 't1'),
          _call('read_file', id: 't2'),
          _call('read_file', id: 't3'),
        ],
      );
      expect(group.localizedActivityTitle(_zh), '读取文件 ×3');
      expect(group.localizedActivityTitle(_en), 'Read File ×3');
    });

    test('2–3 个条目全部展开（entries.length - 3 <= 0，无 +N）', () {
      final two = ToolCallGroup(
        toolCalls: [
          _call('bash', id: 't1'),
          _call('read_file', id: 't2'),
        ],
      );
      expect(two.localizedActivityTitle(_zh), '终端 ×1, 读取文件 ×1');
      expect(two.localizedActivityTitle(_en), 'Terminal ×1, Read File ×1');

      final three = ToolCallGroup(
        toolCalls: [
          _call('bash', id: 't1'),
          _call('read_file', id: 't2'),
          _call('write_file', id: 't3'),
        ],
      );
      expect(three.localizedActivityTitle(_zh), '终端 ×1, 读取文件 ×1, 写入文件 ×1');
      expect(
        three.localizedActivityTitle(_en),
        'Terminal ×1, Read File ×1, Write File ×1',
      );
    });

    test('4 / 5 个条目 → 前 3 + `+N`', () {
      final four = ToolCallGroup(
        toolCalls: [
          _call('bash', id: 't1'),
          _call('read_file', id: 't2'),
          _call('write_file', id: 't3'),
          _call('grep', id: 't4'),
        ],
      );
      expect(four.localizedActivityTitle(_zh), '终端 ×1, 读取文件 ×1, 写入文件 ×1, +1');
      expect(
        four.localizedActivityTitle(_en),
        'Terminal ×1, Read File ×1, Write File ×1, +1',
      );

      final five = ToolCallGroup(
        toolCalls: [
          _call('bash', id: 't1'),
          _call('read_file', id: 't2'),
          _call('write_file', id: 't3'),
          _call('grep', id: 't4'),
          _call('web_search', id: 't5'),
        ],
      );
      expect(five.localizedActivityTitle(_zh), endsWith(', +2'));
      expect(five.localizedActivityTitle(_en), endsWith(', +2'));
    });

    test('频次降序优先于出现顺序：×3 的排到最前', () {
      final group = ToolCallGroup(
        toolCalls: [
          _call('bash', id: 't1'),
          _call('read_file', id: 't2'),
          _call('read_file', id: 't3'),
          _call('read_file', id: 't4'),
          _call('write_file', id: 't5'),
          _call('grep', id: 't6'),
        ],
      );
      // 4 种：读取文件 ×3 领先，其余同频次按首次出现顺序，第 4 种折成 +1。
      expect(group.localizedActivityTitle(_zh), '读取文件 ×3, 终端 ×1, 写入文件 ×1, +1');
      expect(
        group.localizedActivityTitle(_en),
        'Read File ×3, Terminal ×1, Write File ×1, +1',
      );

      // 仅 3 种时无 +N（entries.length - 3 == 0 分支）。
      final threeKinds = ToolCallGroup(
        toolCalls: [
          _call('bash', id: 't1'),
          _call('read_file', id: 't2'),
          _call('read_file', id: 't3'),
          _call('read_file', id: 't4'),
          _call('write_file', id: 't5'),
        ],
      );
      expect(threeKinds.localizedActivityTitle(_zh), '读取文件 ×3, 终端 ×1, 写入文件 ×1');
      expect(
        threeKinds.localizedActivityTitle(_en),
        'Read File ×3, Terminal ×1, Write File ×1',
      );
    });

    test('同频次按首次出现顺序稳定排序', () {
      final group = ToolCallGroup(
        toolCalls: [
          _call('read_file', id: 't1'),
          _call('bash', id: 't2'),
          _call('write_file', id: 't3'),
        ],
      );
      expect(group.localizedActivityTitle(_zh), '读取文件 ×1, 终端 ×1, 写入文件 ×1');
      expect(
        group.localizedActivityTitle(_en),
        'Read File ×1, Terminal ×1, Write File ×1',
      );
    });

    test('思考子卡行归入 thinkingLabel；纯思考卡标题即「思考 ×N」', () {
      final mixed = ToolCallGroup(
        toolCalls: [
          ToolCall.thinking('第一段思考'),
          ToolCall.thinking('第二段思考'),
          _call('bash', id: 't1'),
        ],
      );
      expect(mixed.localizedActivityTitle(_zh), '思考 ×2, 终端 ×1');
      expect(mixed.localizedActivityTitle(_en), 'Thinking ×2, Terminal ×1');

      final pureThinking = ToolCallGroup(
        toolCalls: [ToolCall.thinking('甲'), ToolCall.thinking('乙')],
      );
      expect(pureThinking.localizedActivityTitle(_zh), '思考 ×2');
      expect(pureThinking.localizedActivityTitle(_en), 'Thinking ×2');
    });

    test('思考行优先按 isThinking 判定（name=thinking 但 thinking 为空 → 走名字路径）', () {
      // ToolCall.thinking('') 的 thinking 为空白 → isThinking=false；
      // 此时按 name「thinking」交给 localizeToolName → 仍是「思考」，两路一致。
      final group = ToolCallGroup(
        toolCalls: [
          ToolCall.thinking('   '),
          _call('bash', id: 't1'),
        ],
      );
      expect(group.toolCalls.first.isThinking, isFalse);
      expect(group.localizedActivityTitle(_zh), '思考 ×1, 终端 ×1');
      expect(group.localizedActivityTitle(_en), 'Thinking ×1, Terminal ×1');
    });

    test('第三方 MCP 工具归并为 externalToolsLabel ×N', () {
      final group = ToolCallGroup(
        toolCalls: [
          _call('mcp__github__create_issue', id: 't1'),
          _call('mcp__playwright__browser_click', id: 't2'),
          _call('terminal', id: 't3'),
        ],
      );
      expect(group.localizedActivityTitle(_zh), '外部工具 ×2, 终端 ×1');
      expect(
        group.localizedActivityTitle(_en),
        'External Tools ×2, Terminal ×1',
      );
    });

    test('未收录工具名原样保留（default 分支）；空白名回落「工具」/「Tool」', () {
      final custom = ToolCallGroup(
        toolCalls: [_call('my_custom_tool', id: 't1')],
      );
      expect(custom.localizedActivityTitle(_zh), 'my_custom_tool ×1');
      expect(custom.localizedActivityTitle(_en), 'my_custom_tool ×1');

      final blank = ToolCallGroup(toolCalls: [_call('   ', id: 't1')]);
      // displayName → 'Tool'，localizeToolName('tool') 未收录 → 原样 'Tool'。
      expect(blank.localizedActivityTitle(_zh), 'Tool ×1');
      expect(blank.localizedActivityTitle(_en), 'Tool ×1');
    });

    test('名称首尾空白参与归类前已被 displayName trim', () {
      final group = ToolCallGroup(toolCalls: [_call('  bash  ', id: 't1')]);
      expect(group.localizedActivityTitle(_zh), '终端 ×1');
      expect(group.localizedActivityTitle(_en), 'Terminal ×1');
    });

    test('>3 条目时被折叠的计数以去重后的种类数为准（不含 ×N 数量）', () {
      final group = ToolCallGroup(
        toolCalls: [
          _call('a', id: 't1'),
          _call('a', id: 't2'),
          _call('b', id: 't3'),
          _call('c', id: 't4'),
          _call('d', id: 't5'),
        ],
      );
      // 4 种 → 展示前 3 种（a ×2, b ×1, c ×1），+1。
      expect(group.localizedActivityTitle(_zh), 'a ×2, b ×1, c ×1, +1');
    });
  });

  group('ToolCallGroup.live（live 场景工厂）', () {
    test('anchor 为 null → id 用 unanchored 兜底', () {
      final calls = <ToolCall>[_call('bash', id: 't1')];
      final group = ToolCallGroup.live(toolCalls: calls);

      expect(group.id, 'live-tools-unanchored');
      expect(group.anchorMessageID, isNull);
      expect(group.precedingMessageID, isNull);
      expect(group.isAboveContent, isFalse);
      expect(identical(group.toolCalls, calls), isTrue);
    });

    test('anchor 非空 → id 形如 `live-tools-<anchor>`，其余字段原样透传', () {
      final group = ToolCallGroup.live(
        anchorMessageID: 'm1',
        precedingMessageID: 'm0',
        isAboveContent: true,
        toolCalls: const [],
      );

      expect(group.id, 'live-tools-m1');
      expect(group.anchorMessageID, 'm1');
      expect(group.precedingMessageID, 'm0');
      expect(group.isAboveContent, isTrue);
      expect(group.toolCalls, isEmpty);
    });

    test('空 anchor 字符串视为已给出（不落 unanchored 分支）', () {
      final group = ToolCallGroup.live(
        anchorMessageID: '',
        toolCalls: const [],
      );
      expect(group.id, 'live-tools-');
      expect(group.anchorMessageID, '');
    });

    test('多条工具时保持入参顺序，且无 anchor 时 repeated 调用 id 相同（同一 live 卡）', () {
      final calls = [
        _call('bash', id: 't1'),
        _call('read_file', id: 't2'),
        _call('grep', id: 't3'),
      ];
      final group = ToolCallGroup.live(toolCalls: calls);

      expect(group.toolCalls.map((c) => c.id).toList(), ['t1', 't2', 't3']);
      expect(
        ToolCallGroup.live(toolCalls: calls).id,
        ToolCallGroup.live(toolCalls: calls).id,
      );
    });
  });

  group('ToolCallGroup.mergedWith（跨源相邻合并入口，行 282）', () {
    test('保留本组 id / anchor / 方向，且工具行以本组在前', () {
      final base = ToolCallGroup(
        id: 'base',
        anchorMessageID: 'a1',
        precedingMessageID: 'a0',
        isAboveContent: true,
        toolCalls: [_call('bash', id: 't1')],
      );
      final other = ToolCallGroup(
        id: 'other',
        anchorMessageID: 'a2',
        toolCalls: [_call('read_file', id: 't2')],
      );

      final merged = base.mergedWith(other);

      expect(merged.id, 'base');
      expect(merged.anchorMessageID, 'a1');
      expect(merged.precedingMessageID, 'a0');
      expect(merged.isAboveContent, isTrue);
      expect(merged.toolCalls.map((c) => c.id).toList(), ['t1', 't2']);
    });

    test('本组为空 → 工具行全部来自另一组，但卡位仍取本组', () {
      final base = ToolCallGroup(id: 'base', toolCalls: const []);
      final other = ToolCallGroup(
        id: 'other',
        anchorMessageID: 'a2',
        toolCalls: [_call('grep', id: 't9')],
      );

      final merged = base.mergedWith(other);

      expect(merged.id, 'base');
      expect(merged.anchorMessageID, isNull);
      expect(merged.toolCalls.map((c) => c.id).toList(), ['t9']);
    });

    test('另一组为空 → 工具行原样保留', () {
      final base = ToolCallGroup(
        id: 'base',
        toolCalls: [_call('bash', id: 't1')],
      );
      final merged = base.mergedWith(
        ToolCallGroup(id: 'other', toolCalls: const []),
      );

      expect(merged.toolCalls.map((c) => c.id).toList(), ['t1']);
    });

    test('稳定 id 相同 → 去重为一条（不双显）', () {
      final base = ToolCallGroup(
        id: 'base',
        anchorMessageID: 'a1',
        toolCalls: [_call('bash', id: 't1')],
      );
      final other = ToolCallGroup(
        id: 'other',
        anchorMessageID: 'a1',
        toolCalls: [_call('bash', id: 't1')],
      );

      final merged = base.mergedWith(other);

      expect(merged.toolCalls, hasLength(1));
      expect(merged.toolCalls.single.id, 't1');
    });

    test('结果与本体不同实例；可与自身合并（幂等形状）', () {
      final base = ToolCallGroup(
        id: 'base',
        anchorMessageID: 'a1',
        toolCalls: [_call('bash', id: 't1')],
      );

      final merged = base.mergedWith(base);

      expect(identical(merged, base), isFalse);
      expect(merged.toolCalls, hasLength(1));
      expect(merged.id, 'base');
    });
  });

  group(
    'ToolCallGroup.groups（聚合入口：空入参 / 持久化 / 元数据 / 思考 / offset / coalesce）',
    () {
      test('persisted 与 messages 双空 → 无组', () {
        expect(
          ToolCallGroup.groups(
            persistedToolCalls: const [],
            messages: const [],
          ),
          isEmpty,
        );
      });

      test('persisted 非空但 messages 为空 → 索引越界该条全丢，仍返回空', () {
        expect(
          ToolCallGroup.groups(
            persistedToolCalls: const [
              PersistedToolCall(
                name: 'bash',
                tid: 'call_1',
                assistantMsgIdx: 0,
              ),
            ],
            messages: const [],
          ),
          isEmpty,
        );
      });

      test('assistantMsgIdx 缺失 / 越界 → 该条被跳过（无元数据时不产组）', () {
        const messages = [
          ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
          ChatMessage(role: 'assistant', content: 'a', messageId: 'm1'),
        ];

        expect(
          ToolCallGroup.groups(
            persistedToolCalls: const [
              PersistedToolCall(name: 'bash', tid: 'call_1'),
              PersistedToolCall(
                name: 'grep',
                tid: 'call_2',
                assistantMsgIdx: 5,
              ),
              PersistedToolCall(
                name: 'cat',
                tid: 'call_3',
                assistantMsgIdx: -1,
              ),
            ],
            messages: messages,
          ),
          isEmpty,
        );
      });

      test('persisted 命中 assistant 消息 → 单组：id/anchor/卡位/工具行逐项钉死', () {
        const messages = [
          ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
          ChatMessage(role: 'assistant', content: 'a', messageId: 'm1'),
        ];
        final groups = ToolCallGroup.groups(
          persistedToolCalls: const [
            PersistedToolCall(
              name: 'write_file',
              snippet: '写入片段',
              tid: 'call_1',
              assistantMsgIdx: 1,
            ),
          ],
          messages: messages,
        );

        expect(groups, hasLength(1));
        final group = groups.single;
        // 工具行位于 m1 正文之后：卡位锚 m1、前驱正文 m1、不在正文上方。
        expect(group.id, 'persisted-tools-m1');
        expect(group.anchorMessageID, 'm1');
        expect(group.precedingMessageID, 'm1');
        expect(group.isAboveContent, isFalse);
        expect(group.toolCalls, hasLength(1));
        expect(group.toolCalls.single.id, 'call_1');
        expect(group.toolCalls.single.name, 'write_file');
        expect(group.toolCalls.single.preview, '写入片段');
        // PersistedToolCall.toolCall 出厂即完成。
        expect(group.toolCalls.single.isCompleted, isTrue);
        expect(group.isComplete, isTrue);
      });

      test('同一 assistant 消息下多条 persisted → 同组、按入参顺序', () {
        const messages = [
          ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
          ChatMessage(role: 'assistant', content: 'a', messageId: 'm1'),
        ];
        final groups = ToolCallGroup.groups(
          persistedToolCalls: const [
            PersistedToolCall(name: 'bash', tid: 'call_1', assistantMsgIdx: 1),
            PersistedToolCall(
              name: 'read_file',
              tid: 'call_2',
              assistantMsgIdx: 1,
            ),
            PersistedToolCall(name: 'grep', tid: 'call_3', assistantMsgIdx: 1),
          ],
          messages: messages,
        );

        expect(groups, hasLength(1));
        expect(groups.single.toolCalls.map((c) => c.id).toList(), [
          'call_1',
          'call_2',
          'call_3',
        ]);
        expect(
          groups.single.localizedActivityTitle(_zh),
          '终端 ×1, 读取文件 ×1, 搜索 ×1',
        );
      });

      test('重复 tid → 去重为一条（stable id 去重）', () {
        const messages = [
          ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
          ChatMessage(role: 'assistant', content: 'a', messageId: 'm1'),
        ];
        final groups = ToolCallGroup.groups(
          persistedToolCalls: const [
            PersistedToolCall(name: 'bash', tid: 'call_1', assistantMsgIdx: 1),
            PersistedToolCall(name: 'bash', tid: 'call_1', assistantMsgIdx: 1),
          ],
          messages: messages,
        );

        expect(groups, hasLength(1));
        expect(groups.single.toolCalls, hasLength(1));
        expect(groups.single.toolCalls.single.id, 'call_1');
      });

      test('无 persisted 时用消息元数据兜底：OpenAI 形状 + tool 结果回填 preview', () {
        const messages = [
          ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
          ChatMessage(
            role: 'assistant',
            content: 'a',
            messageId: 'm1',
            toolCalls: [
              JsonObject({
                'id': JsonString('call_a'),
                'function': JsonObject({'name': JsonString('read_file')}),
              }),
            ],
          ),
          ChatMessage(role: 'tool', content: '文件内容', toolCallId: 'call_a'),
        ];
        final groups = ToolCallGroup.groups(
          persistedToolCalls: const [],
          messages: messages,
        );

        expect(groups, hasLength(1));
        expect(groups.single.id, 'persisted-tools-m1');
        expect(groups.single.anchorMessageID, 'm1');
        expect(groups.single.toolCalls, hasLength(1));
        expect(groups.single.toolCalls.single.id, 'call_a');
        expect(groups.single.toolCalls.single.name, 'read_file');
        expect(groups.single.toolCalls.single.preview, '文件内容');
      });

      test('元数据缺 id/name → 回落到 message-tool-<索引>-<序号> 与「tool」', () {
        const messages = [
          ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
          ChatMessage(
            role: 'assistant',
            content: 'a',
            messageId: 'm1',
            toolCalls: [JsonObject({})],
          ),
        ];
        final groups = ToolCallGroup.groups(
          persistedToolCalls: const [],
          messages: messages,
        );

        expect(groups.single.toolCalls.single.id, 'message-tool-1-0');
        expect(groups.single.toolCalls.single.name, 'tool');
        expect(groups.single.toolCalls.single.preview, isNull);
      });

      test('messageOffset 决定 assistantMsgIdx 的落点（同入参换 offset 换锚）', () {
        const messages = [
          ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
          ChatMessage(role: 'assistant', content: 'a', messageId: 'm1'),
          ChatMessage(role: 'assistant', content: 'b', messageId: 'm2'),
        ];
        const persisted = [
          PersistedToolCall(name: 'bash', tid: 'call_1', assistantMsgIdx: 2),
        ];

        final offset0 = ToolCallGroup.groups(
          persistedToolCalls: persisted,
          messages: messages,
        );
        final offset1 = ToolCallGroup.groups(
          persistedToolCalls: persisted,
          messages: messages,
          messageOffset: 1,
        );

        // offset=0 → 载入索引 2 → m2；offset=1 → 载入索引 1 → m1。
        expect(offset0.single.anchorMessageID, 'm2');
        expect(offset0.single.id, 'persisted-tools-m2');
        expect(offset1.single.anchorMessageID, 'm1');
        expect(offset1.single.id, 'persisted-tools-m1');
      });

      test('hideThinking=false：reasoning 转思考行，与工具行同组且钉在首段正文上方', () {
        const messages = [
          ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
          ChatMessage(role: 'assistant', messageId: 'm1', reasoning: '我先思考一下'),
          ChatMessage(role: 'assistant', content: '结论', messageId: 'm2'),
        ];
        final groups = ToolCallGroup.groups(
          persistedToolCalls: const [
            PersistedToolCall(name: 'bash', tid: 'call_1', assistantMsgIdx: 1),
          ],
          messages: messages,
        );

        expect(groups, hasLength(1));
        final group = groups.single;
        expect(group.isAboveContent, isTrue);
        expect(group.precedingMessageID, isNull);
        // 卡位锚到首个带正文的 assistant 消息。
        expect(group.anchorMessageID, 'm2');
        expect(group.id, 'persisted-tools-m1');
        expect(group.toolCalls, hasLength(2));
        expect(group.toolCalls.first.isThinking, isTrue);
        expect(group.toolCalls.first.thinking, '我先思考一下');
        expect(group.toolCalls.last.id, 'call_1');
        expect(group.localizedActivityTitle(_zh), '思考 ×1, 终端 ×1');
      });

      test('hideThinking=true：思考行被剔除，卡位与工具行不变', () {
        const messages = [
          ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
          ChatMessage(role: 'assistant', messageId: 'm1', reasoning: '我先思考一下'),
          ChatMessage(role: 'assistant', content: '结论', messageId: 'm2'),
        ];
        final groups = ToolCallGroup.groups(
          persistedToolCalls: const [
            PersistedToolCall(name: 'bash', tid: 'call_1', assistantMsgIdx: 1),
          ],
          messages: messages,
          hideThinking: true,
        );

        expect(groups, hasLength(1));
        expect(groups.single.toolCalls, hasLength(1));
        expect(groups.single.toolCalls.single.id, 'call_1');
        expect(groups.single.isAboveContent, isTrue);
        expect(groups.single.anchorMessageID, 'm2');
      });

      test('coalesce=true：同一用户回合内被正文打断的两组仍合为一张大卡', () {
        final groups = ToolCallGroup.groups(
          persistedToolCalls: _brokenTurnPersisted,
          messages: _brokenTurnMessages,
          coalesce: true,
        );

        expect(groups, hasLength(1));
        expect(groups.single.anchorMessageID, 'm1');
        expect(groups.single.isAboveContent, isFalse);
        expect(groups.single.toolCalls.map((c) => c.id).toList(), [
          'call_1',
          'call_2',
        ]);
        // 卡位取回合内首个带正文的 assistant 消息（m1），且卡在正文下方。
        expect(groups.single.precedingMessageID, 'm1');
      });

      test('coalesce=false：同一用户回合内被正文打断 → 保持两组穿插', () {
        final groups = ToolCallGroup.groups(
          persistedToolCalls: _brokenTurnPersisted,
          messages: _brokenTurnMessages,
          coalesce: false,
        );

        expect(groups, hasLength(2));
        expect(groups[0].anchorMessageID, 'm1');
        expect(groups[0].toolCalls.map((c) => c.id).toList(), ['call_1']);
        expect(groups[1].anchorMessageID, 'm2');
        expect(groups[1].toolCalls.map((c) => c.id).toList(), ['call_2']);
      });

      test('两个用户回合 → 各成一组，按 anchor 消息在 transcript 中的顺序排列', () {
        const messages = [
          ChatMessage(role: 'user', content: 'q1', messageId: 'u1'),
          ChatMessage(role: 'assistant', content: 'a1', messageId: 'm1'),
          ChatMessage(role: 'user', content: 'q2', messageId: 'u2'),
          ChatMessage(role: 'assistant', content: 'a2', messageId: 'm2'),
        ];
        final groups = ToolCallGroup.groups(
          persistedToolCalls: const [
            PersistedToolCall(name: 'bash', tid: 'call_1', assistantMsgIdx: 1),
            PersistedToolCall(name: 'grep', tid: 'call_2', assistantMsgIdx: 3),
          ],
          messages: messages,
        );

        expect(groups, hasLength(2));
        expect(groups.map((g) => g.anchorMessageID).toList(), ['m1', 'm2']);
        expect(groups.map((g) => g.toolCalls.single.id).toList(), [
          'call_1',
          'call_2',
        ]);
        expect(groups.map((g) => g.isComplete).toList(), [true, true]);
      });

      test('只有用户消息、无 assistant 工具 → 无组', () {
        expect(
          ToolCallGroup.groups(
            persistedToolCalls: const [],
            messages: const [
              ChatMessage(role: 'user', content: 'q1', messageId: 'u1'),
              ChatMessage(role: 'user', content: 'q2', messageId: 'u2'),
            ],
          ),
          isEmpty,
        );
      });
    },
  );
}

/// 「同回合两段工具被中间正文打断」的公共入参（coalesce 真/假 对照用）。
const List<ChatMessage> _brokenTurnMessages = [
  ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
  ChatMessage(role: 'assistant', content: 'a', messageId: 'm1'),
  ChatMessage(role: 'assistant', content: '中间有可见文本', messageId: 'm_mid'),
  ChatMessage(role: 'assistant', content: 'b', messageId: 'm2'),
];

const List<PersistedToolCall> _brokenTurnPersisted = [
  PersistedToolCall(name: 'write_file', tid: 'call_1', assistantMsgIdx: 1),
  PersistedToolCall(name: 'read_file', tid: 'call_2', assistantMsgIdx: 3),
];
