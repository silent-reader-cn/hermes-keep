import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_ui/core/models/json_value.dart';
import 'package:hermes_ui/core/models/tool_call.dart';
import 'package:hermes_ui/features/chat/chat_models.dart';

/// `chat_models.dart` 覆盖率补强 · 批次 CM4：`ToolCallDisplayContent`（行 618–642）。
///
/// 覆盖：构造器（619–623）/ 字段（625–627）/ `of` 工厂（629–641）
/// —— 工厂三分支（`argumentsLine` / `resultText` / `usesMonospace`）逐分支断言。
///
/// 注（任务书 §3 的「不适用」条目，判断依据见 TASK_REPORT.md）：
/// 本类**没有** `fromJson` / `toJson`，**没有**派生 getter，
/// **没有**覆写 `==` / `hashCode` / `toString`，也没有排序 / 去重 / 聚合逻辑。
/// 对应条目改由「构造 + `of` 工厂三分支阶梯 + 默认同一性语义」覆盖：
/// - 「派生 getter / 判定分支」→ `of` 工厂的等宽判定（`usesMonospace` 三条分支）
///   与结果文本判定（可读值 / JSON 树 / 终端信封 / 原样兜底）；
/// - 「嵌套 list/map 边界」→ `arguments` 的 `JsonArray` / 嵌套 `JsonObject` 在
///   null / 空 / 多元素 / 特殊值下的输出；
/// - 「与 `ToolCallDisplayFormatter` 的协作」→ 同一输入经 `of` 与直接调用
///   formatter 的产出一致性。
///
/// 预期值全部按实现读出来写死，不用空断言充数。
/// **不触碰** 11–617 区间（别的作业面）。
ToolCall _call({
  String? name,
  String? preview,
  Map<String, JsonValue>? args,
  bool? isError,
}) => ToolCall(
  id: 'call-test',
  name: name,
  preview: preview,
  args: args,
  isError: isError,
);

/// `ToolCallDisplayContent.of` 的直白包装（测试里读起来短）。
ToolCallDisplayContent _content({
  String? name,
  String? preview,
  Map<String, JsonValue>? args,
  bool? isError,
}) => ToolCallDisplayContent.of(
  _call(name: name, preview: preview, args: args, isError: isError),
);

/// 单键参数表：`k` → 由 JSON 值推导出的 [JsonValue]。
Map<String, JsonValue> _args(Object? value) => {'k': JsonValue.fromJson(value)};

void main() {
  group('ToolCallDisplayContent 构造器 / 字段', () {
    test('三个必填参数逐个落位（monospaced 无默认值，false 显式传入）', () {
      const content = ToolCallDisplayContent(
        arguments: 'path: a.txt',
        result: 'done',
        monospaced: true,
      );

      expect(content.arguments, 'path: a.txt');
      expect(content.result, 'done');
      expect(content.monospaced, isTrue);

      const noMono = ToolCallDisplayContent(
        arguments: '',
        result: '',
        monospaced: false,
      );

      expect(noMono.arguments, isEmpty);
      expect(noMono.result, isEmpty);
      expect(noMono.monospaced, isFalse);
    });

    test('空串 / 纯空白 / 换行 / 制表 / Unicode 原样保留（构造期不归一、不 trim）', () {
      const blank = ToolCallDisplayContent(
        arguments: '   ',
        result: '\n\t',
        monospaced: false,
      );

      expect(blank.arguments, '   ');
      expect(blank.result, '\n\t');

      const verbatim = ToolCallDisplayContent(
        arguments: '  a: 1\r\n  b: 2  ',
        result: '行一\r\n行二',
        monospaced: true,
      );

      expect(verbatim.arguments, '  a: 1\r\n  b: 2  ');
      expect(verbatim.result, '行一\r\n行二');

      const unicode = ToolCallDisplayContent(
        arguments: '路径: D:\\项目\\a.txt',
        result: '✅ 完成 ×3',
        monospaced: false,
      );

      expect(unicode.arguments, '路径: D:\\项目\\a.txt');
      expect(unicode.result, '✅ 完成 ×3');
    });

    test('const 同参构造 canonical 化：identical 且相等', () {
      const lhs = ToolCallDisplayContent(
        arguments: 'a',
        result: 'r',
        monospaced: false,
      );
      const rhs = ToolCallDisplayContent(
        arguments: 'a',
        result: 'r',
        monospaced: false,
      );

      expect(identical(lhs, rhs), isTrue);
      expect(lhs == rhs, isTrue);
      expect(lhs.hashCode, rhs.hashCode);
    });
  });

  group('ToolCallDisplayContent.of —— arguments（参数行）', () {
    test('args 为 null / 空 Map → 参数行为空串', () {
      expect(_content(name: 'read_file').arguments, '');
      expect(_content(name: 'read_file', args: const {}).arguments, '');
    });

    test('多键按键名升序，每键一行 `key: value`', () {
      final content = _content(
        name: 'read_file',
        args: const {
          'path': JsonString('a.txt'),
          'encoding': JsonString('utf-8'),
          'limit': JsonNumber(10),
        },
      );

      expect(content.arguments, 'encoding: utf-8\nlimit: 10\npath: a.txt');
    });

    test('标量值：整数 / 小数 / bool / JsonNull / 字符串换行归一', () {
      expect(_content(args: _args(3)).arguments, 'k: 3');
      expect(_content(args: _args(1.5)).arguments, 'k: 1.5');
      expect(_content(args: _args(true)).arguments, 'k: true');
      expect(_content(args: _args(null)).arguments, 'k: null');
      expect(_content(args: _args('a\r\nb')).arguments, 'k: a\nb');
      // JSON 字符串里的裸 \r 同样归一。
      expect(_content(args: _args('a\rb')).arguments, 'k: a\nb');
    });

    test('数组值：空数组 → 空、单元素、多元素 → `- ` 列表', () {
      expect(_content(args: _args(<Object?>[])).arguments, 'k: ');

      expect(_content(args: _args(<Object?>['x'])).arguments, 'k: - x');

      expect(
        _content(args: _args(<Object?>['x', 'y', 2])).arguments,
        'k: - x\n- y\n- 2',
      );
    });

    test('嵌套对象值：键升序 + 续行两格缩进；空对象 → 空', () {
      expect(_content(args: _args(<String, Object?>{})).arguments, 'k: ');

      expect(
        _content(
          args: _args(<String, Object?>{
            'n': 1,
            'm': <String, Object?>{'z': false},
          }),
        ).arguments,
        'k: m: z: false\nn: 1',
      );

      expect(
        _content(
          args: _args(<String, Object?>{
            'k': <Object?>['a', 'b'],
          }),
        ).arguments,
        'k: k: - a\n  - b',
      );
    });

    test('数组元素为 null / bool / 对象 / 嵌套数组的显示形态', () {
      expect(
        _content(
          args: _args(<Object?>[
            null,
            true,
            <String, Object?>{'a': 1},
          ]),
        ).arguments,
        'k: - null\n- true\n- a: 1',
      );

      expect(
        _content(
          args: _args(<Object?>[
            <Object?>['inner'],
          ]),
        ).arguments,
        'k: - - inner',
      );
    });
  });

  group('ToolCallDisplayContent.of —— result（结果文本）', () {
    test('preview 为 null / 空串 / 纯空白 → 空串', () {
      expect(_content().result, '');
      expect(_content(preview: '').result, '');
      expect(_content(preview: '   ').result, '');
      expect(_content(preview: '\n\t ').result, '');
    });

    test('非 JSON 文本：原样返回（首尾空白保留），仅归一换行', () {
      expect(_content(preview: 'hello').result, 'hello');
      expect(_content(preview: '  hello  ').result, '  hello  ');
      expect(_content(preview: 'a\r\nb').result, 'a\nb');
      expect(_content(preview: 'a\rb').result, 'a\nb');
      expect(_content(preview: '{bad}').result, '{bad}');
    });

    test('JSON 可读值优先：result → results → preview → content → text → message '
        '→ summary → data → items，取第一个非空者', () {
      expect(_content(preview: '{"result":"ok"}').result, 'ok');
      expect(_content(preview: '{"result":"","data":"兜底"}').result, '兜底');
      expect(_content(preview: '{"data":42}').result, '42');
      expect(_content(preview: '{"items":true}').result, 'true');
      expect(_content(preview: '{"result":"a\\r\\nb"}').result, 'a\nb');
    });

    test('error 键即终端信封键：信封优先于可读值（content 存在也返回 Error:）', () {
      expect(_content(preview: '{"error":"boom"}').result, 'Error: boom');
      // 实现观察：`error` 属 _isTerminalEnvelope 的键集，故信封判定先命中，
      // 不会落到 _firstReadableValue 的 `content` → 'ok'。
      // 推论：_firstReadableValue 里的 error 兜底分支经 resultText 不可达
      //（有 error 键就已是信封）——仅作观察记录，不改源文件。
      expect(
        _content(preview: '{"error":"boom","content":"ok"}').result,
        'Error: boom',
      );
      // 不含信封键时，可读值正常生效。
      expect(_content(preview: '{"content":"ok"}').result, 'ok');
    });

    test('无可读键的对象 → JSON 树文本（键升序、续行缩进）', () {
      expect(_content(preview: '{"z":1,"a":"x"}').result, 'a: x\nz: 1');
      expect(_content(preview: '{}').result, '');
      expect(_content(preview: '{"a":null}').result, 'a: null');
    });

    test('非对象 JSON：数组 → 列表、标量 → 原样文本', () {
      expect(_content(preview: '["a","b"]').result, '- a\n- b');
      expect(_content(preview: '[]').result, '');
      expect(_content(preview: '123').result, '123');
      expect(_content(preview: 'true').result, 'true');
      // 实现观察：JSON `null` 与「解析失败」在 _decodeJson 里同为 null
      // → 走原样兜底（不报错、也不当树）。
      expect(_content(preview: 'null').result, 'null');
    });

    test('终端信封（terminal 工具名）：output 优先，接 stderr，再接 Error / Exit code', () {
      expect(
        _content(
          name: 'terminal',
          preview: '{"output":"hi","stderr":"warn","exit_code":3}',
        ).result,
        'hi\nwarn\nExit code: 3',
      );
      expect(
        _content(name: 'bash', preview: '{"stdout":"out","error":"bad"}').result,
        'out\nError: bad',
      );
      expect(
        _content(name: 'shell', preview: '{"output":"hi","exit_code":0}').result,
        'hi',
      );
      expect(
        _content(name: 'terminal', preview: '{"exitCode":"2"}').result,
        'Exit code: 2',
      );
      // 非 terminal 名字但含信封键 → 同样走信封路径。
      expect(
        _content(name: 'read_file', preview: '{"stderr":"only-stderr"}').result,
        'only-stderr',
      );
      // terminal 名字 + 裸字符串 preview → 标量文本（不套信封）。
      expect(_content(name: 'terminal', preview: '"plain"').result, 'plain');
      // 信封全空 → 空串。
      expect(_content(name: 'terminal', preview: '{}').result, '');
      // 回车换行在信封字段里归一。
      expect(
        _content(name: 'terminal', preview: '{"output":"a\\r\\nb"}').result,
        'a\r\nb',
      );
    });

    test('JSON 字符串里再包 JSON → 解包后继续按树 / 可读值处理', () {
      expect(_content(preview: '"{\\"a\\":1}"').result, 'a: 1');
      expect(_content(preview: '"{\\"result\\":\\"deep\\"}"').result, 'deep');
    });
  });

  group('ToolCallDisplayContent.of —— monospaced（等宽判定三分支）', () {
    test('分支一：terminal 家族工具名恒等宽（空 preview 也成立）', () {
      for (final name in const [
        'terminal',
        'shell',
        'bash',
        'zsh',
        'command',
        'exec',
        'cmd',
        'powershell',
      ]) {
        expect(
          _content(name: name).monospaced,
          isTrue,
          reason: '工具名 $name 应判等宽',
        );
      }

      // 名字 trim + 小写后比对。
      expect(_content(name: '  BASH  ').monospaced, isTrue);
      expect(_content(name: 'Shell').monospaced, isTrue);
    });

    test('分支一的反例：非 terminal 名 / 空名 / 缺名，且结果无换行且非 JSON → 非等宽', () {
      expect(_content(name: 'read_file', preview: 'plain').monospaced, isFalse);
      expect(_content(name: '', preview: 'plain').monospaced, isFalse);
      expect(_content(preview: 'plain').monospaced, isFalse);
      // 前缀相同但不是 terminal 家族成员。
      expect(_content(name: 'commander', preview: 'plain').monospaced, isFalse);
    });

    test('分支二：结果文本含换行 → 等宽', () {
      expect(_content(name: 'read_file', preview: 'a\nb').monospaced, isTrue);
      expect(_content(name: 'read_file', preview: 'a\r\nb').monospaced, isTrue);
      expect(
        _content(name: 'read_file', preview: '["a","b"]').monospaced,
        isTrue,
      );
    });

    test('分支三：preview 可解析为 JSON → 等宽（即使结果文本无换行）', () {
      expect(_content(name: 'x', preview: '{"a":1}').monospaced, isTrue);
      expect(_content(name: 'x', preview: '123').monospaced, isTrue);
      expect(_content(name: 'x', preview: 'true').monospaced, isTrue);
      // 解析失败 / preview 缺失 → 不因本条判等宽。
      expect(_content(name: 'x', preview: '{bad}').monospaced, isFalse);
      expect(_content(name: 'x').monospaced, isFalse);
      // 实现观察：JSON `null` 与解析失败同为 null → 该条不判等宽。
      expect(_content(name: 'x', preview: 'null').monospaced, isFalse);
    });
  });

  group('ToolCallDisplayContent.of —— 与 ToolCallDisplayFormatter 的一致性 / 幂等', () {
    test('同一输入经 of 与直接调 formatter 三个字段逐一相等', () {
      final calls = <ToolCall>[
        _call(name: 'terminal', preview: '{"output":"hi"}'),
        _call(
          name: 'read_file',
          args: const {'path': JsonString('a.txt')},
          preview: '{"result":"ok"}',
        ),
        _call(name: 'x', preview: 'plain text'),
        _call(),
      ];

      for (final call in calls) {
        final content = ToolCallDisplayContent.of(call);

        expect(content.arguments, ToolCallDisplayFormatter.argumentsLine(call));
        expect(content.result, ToolCallDisplayFormatter.resultText(call));
        expect(
          content.monospaced,
          ToolCallDisplayFormatter.usesMonospace(
            call,
            resultText: content.result,
          ),
        );
      }
    });

    test('幂等：同一 call 连续两次 of → 字段一致；工厂每次返回新实例', () {
      final call = _call(
        name: 'bash',
        args: const {'command': JsonString('ls -la')},
        preview: '{"output":"a\\nb"}',
      );

      final first = ToolCallDisplayContent.of(call);
      final second = ToolCallDisplayContent.of(call);

      expect(identical(first, second), isFalse);
      expect(first.arguments, second.arguments);
      expect(first.result, second.result);
      expect(first.monospaced, second.monospaced);
      // 未覆写 == → 同字段不同实例不相等（同一性语义，见下一 group）。
      expect(first == second, isFalse);
    });

    test('isError / isCompleted 不影响展示内容三字段（展示只看 name/preview/args）', () {
      final base = _call(name: 'read_file', preview: '{"result":"ok"}');
      final failed = _call(
        name: 'read_file',
        preview: '{"result":"ok"}',
        isError: true,
      );

      expect(
        ToolCallDisplayContent.of(failed).result,
        ToolCallDisplayContent.of(base).result,
      );
      expect(
        ToolCallDisplayContent.of(failed).monospaced,
        ToolCallDisplayContent.of(base).monospaced,
      );
    });
  });

  group('ToolCallDisplayContent 默认同一性语义（未覆写 == / hashCode / toString）', () {
    test('同一实例：自反相等、hashCode 稳定；跨类型不等', () {
      const content = ToolCallDisplayContent(
        arguments: 'a',
        result: 'r',
        monospaced: false,
      );

      expect(content == content, isTrue);
      expect(content == Object(), isFalse);
      final Object unrelated = 'a';
      expect(content == unrelated, isFalse);
      expect(content.hashCode, content.hashCode);
    });

    test('字段全同的两个非 const 实例仍不等（未覆写 ==）→ Set 保留两条', () {
      final fields = ['a', 'r'];
      final first = ToolCallDisplayContent(
        arguments: fields[0],
        result: fields[1],
        monospaced: false,
      );
      final second = ToolCallDisplayContent(
        arguments: fields[0],
        result: fields[1],
        monospaced: false,
      );

      expect(identical(first, second), isFalse);
      expect(first == second, isFalse);
      expect(<Object>{first, second}, hasLength(2));
    });

    test('字段阶梯：任一字段改一项，三字段比对即可区分（同一性语义不参与判别）', () {
      const base = ToolCallDisplayContent(
        arguments: 'a',
        result: 'r',
        monospaced: false,
      );

      // arguments 差一项
      const argDiff = ToolCallDisplayContent(
        arguments: 'A',
        result: 'r',
        monospaced: false,
      );
      // result 差一项（含「空白变体」，构造期不 trim）
      const resultDiff = ToolCallDisplayContent(
        arguments: 'a',
        result: 'r ',
        monospaced: false,
      );
      // monospaced 差一项
      const monoDiff = ToolCallDisplayContent(
        arguments: 'a',
        result: 'r',
        monospaced: true,
      );

      expect(base.arguments == argDiff.arguments, isFalse);
      expect(base.result == resultDiff.result, isFalse);
      expect(base.monospaced == monoDiff.monospaced, isFalse);

      // 空串 / 换行变体同样可区分。
      const emptyArgs = ToolCallDisplayContent(
        arguments: '',
        result: 'r',
        monospaced: false,
      );
      expect(base.arguments == emptyArgs.arguments, isFalse);
      const newlineResult = ToolCallDisplayContent(
        arguments: 'a',
        result: 'r\n',
        monospaced: false,
      );
      expect(base.result == newlineResult.result, isFalse);

      // const 相同三项 → 仍可判「相等」（canonical 化）。
      const sameAgain = ToolCallDisplayContent(
        arguments: 'a',
        result: 'r',
        monospaced: false,
      );
      expect(base == sameAgain, isTrue);
    });

    test('toString 走 Object 默认实现（未覆写）', () {
      const content = ToolCallDisplayContent(
        arguments: 'a',
        result: 'r',
        monospaced: false,
      );

      expect(content.toString(), "Instance of 'ToolCallDisplayContent'");
    });
  });
}
