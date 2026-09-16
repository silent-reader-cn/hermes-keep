import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_ui/core/models/json_value.dart';
import 'package:hermes_ui/core/models/tool_call.dart';
import 'package:hermes_ui/features/chat/chat_models.dart';

/// `chat_models.dart` 覆盖率补强 · 批次 CM3：
/// `ToolCallDisplayFormatter`（行 360–617 / 类体 360–615）。
///
/// 覆盖公开面：`argumentsLine`（364–369）/ `toolDisplayText`（372–383）/
/// `terminalToolNames`（416–425）/ `resultText`（428–448）/
/// `usesMonospace`（451–457），以及它们下达不到的私有分支
/// （`_objectTree`、`_formatNumber`、`_normalizeNewlines`、
/// `_terminalEnvelopeText`、`_isTerminalEnvelope`、`_firstReadableValue`、
/// `_jsonTreeText`、`_scalarText`、`_firstNonEmptyString`、`_intField`、
/// `_tryParseJsonTree`、`_decodeJson`）。
///
/// 预期值全部按实现读出来写死，不用空断言充数。
/// **不触碰** 11–359（已交付）与 618+（`ToolCallDisplayContent`，别的作业面）。
///
/// 注（任务书 §3 与实现的差异，详 TASK_REPORT.md）：
/// 本区间**没有** `AppLocalizations` 参数、**没有**工具名中文标签映射、
/// **没有** `mcp__` 归并逻辑（那些在 `tool_call.dart` / `app_localizations.dart`）。
/// 区间内唯一的「名字 → 行为」映射表是 [ToolCallDisplayFormatter.terminalToolNames]。
ToolCall _call({String? name, String? preview, Map<String, JsonValue>? args}) =>
    ToolCall(name: name, preview: preview, args: args);

/// 把一段 JSON 文本再 `jsonEncode` 包 [times] 层（字符串套字符串）。
/// 用于敲 `_tryParseJsonTree` 的嵌套解包与 3 层深度上限。
String _wrap(String json, int times) {
  var value = json;
  for (var i = 0; i < times; i++) {
    value = jsonEncode(value);
  }
  return value;
}

void main() {
  group('argumentsLine', () {
    test('args 为 null → 空串', () {
      expect(ToolCallDisplayFormatter.argumentsLine(_call(name: 'terminal')), '');
    });

    test('args 为空 map → 空串', () {
      expect(
        ToolCallDisplayFormatter.argumentsLine(
          _call(name: 'terminal', args: const {}),
        ),
        '',
      );
    });

    test('单键：`key: 值`（冒号后一个空格）', () {
      expect(
        ToolCallDisplayFormatter.argumentsLine(
          _call(args: const {'command': JsonString('ls -la')}),
        ),
        'command: ls -la',
      );
    });

    test('多键按 key 升序排列（与插入顺序无关）', () {
      expect(
        ToolCallDisplayFormatter.argumentsLine(
          _call(
            args: const {
              'zeta': JsonString('z'),
              'alpha': JsonString('a'),
              'mid': JsonString('m'),
            },
          ),
        ),
        'alpha: a\nmid: m\nzeta: z',
      );
    });

    test('值类型各异：bool / number / null / 空串 / 空容器各自成行', () {
      expect(
        ToolCallDisplayFormatter.argumentsLine(
          _call(
            args: const {
              'a_bool': JsonBool(false),
              'b_num': JsonNumber(3),
              'c_null': JsonNull(),
              'd_empty': JsonString(''),
              'e_empty_obj': JsonObject({}),
              'f_empty_arr': JsonArray([]),
            },
          ),
        ),
        'a_bool: false\n'
        'b_num: 3\n'
        'c_null: null\n'
        'd_empty: \n'
        'e_empty_obj: \n'
        'f_empty_arr: ',
      );
    });

    test('嵌套对象：首行接在 key 后，续行**不加缩进**（argumentsLine 不做树缩进）', () {
      expect(
        ToolCallDisplayFormatter.argumentsLine(
          _call(
            args: const {
              'a': JsonObject({'c': JsonString('1'), 'b': JsonString('2')}),
            },
          ),
        ),
        // 内层 keys 升序 → b, c；只有内层 `_objectTree` 会缩进，argumentsLine 不会。
        'a: b: 2\nc: 1',
      );
    });

    test('嵌套对象里的数组值：同样不缩进续行', () {
      expect(
        ToolCallDisplayFormatter.argumentsLine(
          _call(
            args: const {
              'a': JsonArray([JsonString('x'), JsonString('y')]),
            },
          ),
        ),
        'a: - x\n- y',
      );
    });

    test('输入含换行的字符串值：原样换行（前缀不被复制）', () {
      expect(
        ToolCallDisplayFormatter.argumentsLine(
          _call(args: const {'content': JsonString('l1\r\nl2')}),
        ),
        'content: l1\nl2',
      );
    });

    test('幂等：同一调用连续两次结果相同', () {
      final call = _call(
        args: const {'b': JsonNumber(2.5), 'a': JsonObject({'x': JsonNull()})},
      );

      final first = ToolCallDisplayFormatter.argumentsLine(call);
      final second = ToolCallDisplayFormatter.argumentsLine(call);

      expect(first, second);
      expect(first, 'a: x: null\nb: 2.5');
    });
  });

  group('toolDisplayText', () {
    test('null → 空串', () {
      expect(ToolCallDisplayFormatter.toolDisplayText(null), '');
    });

    test('JsonNull → "null"', () {
      expect(ToolCallDisplayFormatter.toolDisplayText(const JsonNull()), 'null');
    });

    test('JsonBool → true / false', () {
      expect(
        ToolCallDisplayFormatter.toolDisplayText(const JsonBool(true)),
        'true',
      );
      expect(
        ToolCallDisplayFormatter.toolDisplayText(const JsonBool(false)),
        'false',
      );
    });

    test('JsonNumber 整数 → 去小数点', () {
      expect(ToolCallDisplayFormatter.toolDisplayText(const JsonNumber(3)), '3');
      expect(
        ToolCallDisplayFormatter.toolDisplayText(const JsonNumber(-3)),
        '-3',
      );
      expect(ToolCallDisplayFormatter.toolDisplayText(const JsonNumber(0)), '0');
    });

    test('JsonNumber 负零 → "0"（roundToDouble 相等后 toInt）', () {
      expect(ToolCallDisplayFormatter.toolDisplayText(const JsonNumber(-0.0)), '0');
    });

    test('JsonNumber 非整数 → 原样 toString', () {
      expect(
        ToolCallDisplayFormatter.toolDisplayText(const JsonNumber(1.5)),
        '1.5',
      );
      expect(
        ToolCallDisplayFormatter.toolDisplayText(const JsonNumber(-0.25)),
        '-0.25',
      );
      expect(
        ToolCallDisplayFormatter.toolDisplayText(const JsonNumber(2.5)),
        '2.5',
      );
    });

    test('JsonString：CRLF / CR 归一为 LF；空串原样', () {
      expect(
        ToolCallDisplayFormatter.toolDisplayText(const JsonString('a\r\nb\rc')),
        'a\nb\nc',
      );
      expect(ToolCallDisplayFormatter.toolDisplayText(const JsonString('')), '');
      expect(
        ToolCallDisplayFormatter.toolDisplayText(const JsonString('  x  ')),
        '  x  ',
      );
    });

    test('JsonArray：空数组 → 空串；元素逐行 "- 值"', () {
      expect(
        ToolCallDisplayFormatter.toolDisplayText(const JsonArray([])),
        '',
      );
      expect(
        ToolCallDisplayFormatter.toolDisplayText(
          const JsonArray([JsonBool(true), JsonNull(), JsonNumber(1)]),
        ),
        '- true\n- null\n- 1',
      );
    });

    test('JsonArray 套 JsonArray → "- - 值"（递归不缩进）', () {
      expect(
        ToolCallDisplayFormatter.toolDisplayText(
          const JsonArray([
            JsonArray([JsonString('a')]),
          ]),
        ),
        '- - a',
      );
    });

    test('JsonObject：空对象 → 空串；单层按 key 升序', () {
      expect(ToolCallDisplayFormatter.toolDisplayText(const JsonObject({})), '');
      expect(
        ToolCallDisplayFormatter.toolDisplayText(
          const JsonObject({'b': JsonString('2'), 'a': JsonString('1')}),
        ),
        'a: 1\nb: 2',
      );
    });

    test('JsonObject 嵌套：子值首行接父 key，续行缩进两个空格', () {
      expect(
        ToolCallDisplayFormatter.toolDisplayText(
          const JsonObject({
            'b': JsonObject({'c': JsonString('1'), 'd': JsonString('2')}),
          }),
        ),
        'b: c: 1\n  d: 2',
      );
    });

    test('JsonObject 内数组值：数组的第二行起缩进两个空格', () {
      expect(
        ToolCallDisplayFormatter.toolDisplayText(
          const JsonObject({
            'k': JsonArray([JsonString('x'), JsonString('y')]),
          }),
        ),
        'k: - x\n  - y',
      );
    });

    test('顶层 JsonObject 的每一行都不带前导缩进（含多行子值的首行）', () {
      expect(
        ToolCallDisplayFormatter.toolDisplayText(
          const JsonObject({
            'a': JsonObject({'c': JsonString('1'), 'b': JsonString('2')}),
            'z': JsonString('z'),
          }),
        ),
        'a: b: 2\n  c: 1\nz: z',
      );
    });

    test('性质：标量值场景下 argumentsLine 与 toolDisplayText(JsonObject(args)) 等价', () {
      final args = <String, JsonValue>{
        'zeta': const JsonString('z'),
        'alpha': const JsonNumber(1),
        'beta': const JsonBool(true),
      };

      expect(
        ToolCallDisplayFormatter.argumentsLine(_call(args: args)),
        ToolCallDisplayFormatter.toolDisplayText(JsonObject(args)),
      );
    });
  });

  group('terminalToolNames', () {
    test('集合内容与实现一致（8 项）', () {
      expect(ToolCallDisplayFormatter.terminalToolNames, <String>{
        'terminal',
        'shell',
        'bash',
        'zsh',
        'command',
        'exec',
        'cmd',
        'powershell',
      });
    });

    test('未收录名（含近义名）不在集合里', () {
      for (final name in ['run', 'sh', 'console', 'Terminal ', 'BASH', '']) {
        expect(
          ToolCallDisplayFormatter.terminalToolNames.contains(name),
          isFalse,
          reason: '$name 不应被当作终端工具名',
        );
      }
    });
  });

  group('resultText · 空值 / 非 JSON 回落', () {
    test('preview 为 null → 空串', () {
      expect(
        ToolCallDisplayFormatter.resultText(_call(name: 'read_file')),
        '',
      );
    });

    test('preview 空串 → 空串', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: ''),
        ),
        '',
      );
    });

    test('preview 纯空白 → 空串（trim 后判空）', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: ' \r\n\t '),
        ),
        '',
      );
    });

    test('非 JSON 文本原样返回', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: 'plain text'),
        ),
        'plain text',
      );
    });

    test('非 JSON 文本：CRLF / CR 归一为 LF', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: 'a\r\nb\rc'),
        ),
        'a\nb\nc',
      );
    });

    test('形似 JSON 但解析失败 → 原样返回（不抛错）', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"a":}'),
        ),
        '{"a":}',
      );
    });

    test('preview 为 JSON 字面量 null → 原样返回 "null"（解析失败与 JSON null 不可区分）', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: 'null'),
        ),
        'null',
      );
    });

    test('preview 外带首尾空白 → 照样解析为 JSON', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '  {"result":"ok"}  '),
        ),
        'ok',
      );
    });
  });

  group('resultText · JSON 标量 / 容器', () {
    test('JSON 字符串解包后返回（已去转义）', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '"line1\\nline2"'),
        ),
        'line1\nline2',
      );
    });

    test('JSON 数字标量 → _formatNumber', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '1.5'),
        ),
        '1.5',
      );
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '7'),
        ),
        '7',
      );
    });

    test('JSON 布尔标量 → true / false', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: 'true'),
        ),
        'true',
      );
    });

    test('JSON 数组标量 → 逐行 "- 值"', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '[1,"x"]'),
        ),
        '- 1\n- x',
      );
    });

    test('对象无「可读键」→ JSON 树（键升序、标量直转）', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"a":1}'),
        ),
        'a: 1',
      );
    });

    test('对象里的嵌套对象值 → jsonEncode 压成一行', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"a":{"b":1}}'),
        ),
        'a: {"b":1}',
      );
    });

    test('对象里的数组值 → 首行接键、续行缩进两空格', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"items":[1,"x"]}'),
        ),
        'items: - 1\n  - x',
      );
    });

    test('可读键优先级：result 先于 content', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"content":"c","result":"r"}'),
        ),
        'r',
      );
    });

    test('可读键：9 个键名逐一首位命中（顺序表全覆盖）', () {
      const keys = [
        'result',
        'results',
        'preview',
        'content',
        'text',
        'message',
        'summary',
        'data',
        'items',
      ];

      for (final key in keys) {
        expect(
          ToolCallDisplayFormatter.resultText(
            _call(name: 'read_file', preview: '{"$key":"v"}'),
          ),
          'v',
          reason: '键 $key 应命中可读值路径',
        );
      }
    });

    test('可读键的空白字符串值被跳过 → 回落 JSON 树', () {
      // 值为「三个空格」：trim 后为空 → 不算可读值；_jsonTreeText 原样输出该值。
      const blanks = '   ';

      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"result":"$blanks"}'),
        ),
        'result: $blanks',
      );
    });

    test('可读键的 null 值被跳过 → 回落 JSON 树', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"result":null}'),
        ),
        'result: null',
      );
    });

    test('可读键为数组 → 不算可读值，回落 JSON 树', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"items":[1,2]}'),
        ),
        'items: - 1\n  - 2',
      );
    });

    test('可读键为数字 / 布尔 → 标量文本', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"result":5}'),
        ),
        '5',
      );
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"result":true}'),
        ),
        'true',
      );
    });

    test('空对象 {} → 空串（JSON 树无键）', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{}'),
        ),
        '',
      );
    });

    test('嵌套解包：套 1 / 2 / 3 层字符串都还原成同一棵树', () {
      const base = '{"a":1}';

      for (final times in [1, 2, 3]) {
        expect(
          ToolCallDisplayFormatter.resultText(
            _call(name: 'read_file', preview: _wrap(base, times)),
          ),
          'a: 1',
          reason: '套 $times 层应仍解包到 {"a":1}',
        );
      }
    });

    test('嵌套解包 3 层为上限：套 4 层时回落成 JSON 文本字面量', () {
      // `_tryParseJsonTree` 循环 3 次后 return _decodeJson(candidate)，
      // 此时 candidate 仍是「被引号包住的字符串」，故结果是被包住的原文。
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: _wrap('{"a":1}', 4)),
        ),
        '{"a":1}',
      );
    });
  });

  group('resultText · 终端信封', () {
    test('未收录工具名但对象含 output 键 → 也走信封（键判定）', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"output":"out"}'),
        ),
        'out',
      );
    });

    test('stdout 作为 output 的别名', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"stdout":"s"}'),
        ),
        's',
      );
    });

    test('output 优先于 stdout', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"stdout":"s","output":"o"}'),
        ),
        'o',
      );
    });

    test('output 为纯空白 → 让位给 stdout', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"output":"   ","stdout":"s"}'),
        ),
        's',
      );
    });

    test('output 非字符串（数字 / 对象）→ 被忽略', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"output":123}'),
        ),
        '',
      );
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"output":{"a":1}}'),
        ),
        '',
      );
    });

    test('output + stderr 拼接（换行分隔）', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"output":"out","stderr":"err"}'),
        ),
        'out\nerr',
      );
    });

    test('stderr 单独存在时无前导换行', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"stderr":"err"}'),
        ),
        'err',
      );
    });

    test('error 键加 "Error: " 前缀', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"error":"boom"}'),
        ),
        'Error: boom',
      );
    });

    test('exit_code 非 0 → "Exit code: N"；0 → 不输出', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"exit_code":3}'),
        ),
        'Exit code: 3',
      );
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"exit_code":0}'),
        ),
        '',
      );
    });

    test('exitCode（驼峰）同样识别', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"exitCode":2}'),
        ),
        'Exit code: 2',
      );
    });

    test('exit_code 为字符串 → int.tryParse（含两侧空白）', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"exit_code":"4"}'),
        ),
        'Exit code: 4',
      );
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"exit_code":" 5 "}'),
        ),
        'Exit code: 5',
      );
    });

    test('exit_code 为小数 → truncate 取整', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'read_file', preview: '{"exit_code":1.9}'),
        ),
        'Exit code: 1',
      );
    });

    test('exit_code 不可解析（"abc" / true / null）→ 静默省略', () {
      for (final raw in ['"abc"', 'true', 'null', '[1]']) {
        expect(
          ToolCallDisplayFormatter.resultText(
            _call(name: 'read_file', preview: '{"exit_code":$raw}'),
          ),
          '',
          reason: 'exit_code=$raw 应不产出任何行',
        );
      }
    });

    test('四要素齐全 → output / stderr / Error / Exit code 顺序拼接', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(
            name: 'read_file',
            preview:
                '{"output":"out","stderr":"err","error":"bad","exit_code":3}',
          ),
        ),
        'out\nerr\nError: bad\nExit code: 3',
      );
    });

    test('终端工具名 + 无信封键的对象 → 空串（按名字强制走信封，丢掉 JSON 树回落）', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'terminal', preview: '{"a":1}'),
        ),
        '',
      );
    });

    test('终端工具名 + 裸 JSON 字符串 preview → 标量原样', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'bash', preview: '"hello"'),
        ),
        'hello',
      );
    });

    test('终端工具名 + JSON 数组 preview → 逐行 "- 值"（非 Map 走 _scalarText）', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'bash', preview: '[1,2]'),
        ),
        '- 1\n- 2',
      );
    });

    test('终端工具名 + 非 JSON preview → 原样（解析失败回落）', () {
      expect(
        ToolCallDisplayFormatter.resultText(
          _call(name: 'bash', preview: 'ls -la\r\n'),
        ),
        'ls -la\n',
      );
    });

    test('终端工具名 + 空白 preview → 空串', () {
      expect(
        ToolCallDisplayFormatter.resultText(_call(name: 'cmd', preview: '  ')),
        '',
      );
    });
  });

  group('resultText · 签名契约', () {
    test('monospaced 命名参数被忽略（同一调用两值结果相同）', () {
      final call = _call(name: 'read_file', preview: '{"result":"ok"}');

      expect(
        ToolCallDisplayFormatter.resultText(call, monospaced: true),
        ToolCallDisplayFormatter.resultText(call, monospaced: false),
      );
      expect(ToolCallDisplayFormatter.resultText(call), 'ok');
    });

    test('幂等：同一调用连续两次结果相同', () {
      final call = _call(name: 'read_file', preview: '{"b":2,"a":1}');

      expect(
        ToolCallDisplayFormatter.resultText(call),
        ToolCallDisplayFormatter.resultText(call),
      );
      expect(ToolCallDisplayFormatter.resultText(call), 'a: 1\nb: 2');
    });
  });

  group('usesMonospace', () {
    test('终端工具名（8 项逐一）→ true（与 preview / resultText 无关）', () {
      for (final name in ToolCallDisplayFormatter.terminalToolNames) {
        expect(
          ToolCallDisplayFormatter.usesMonospace(
            _call(name: name),
            resultText: '',
          ),
          isTrue,
          reason: '$name 应判等宽',
        );
      }
    });

    test('终端工具名：大小写 / 两侧空白被归一后仍识别', () {
      expect(
        ToolCallDisplayFormatter.usesMonospace(
          _call(name: '  TeRmInAl  '),
          resultText: '',
        ),
        isTrue,
      );
      expect(
        ToolCallDisplayFormatter.usesMonospace(
          _call(name: 'BASH'),
          resultText: '',
        ),
        isTrue,
      );
    });

    test('未收录名 + 单行结果 + 无 JSON preview → false', () {
      expect(
        ToolCallDisplayFormatter.usesMonospace(
          _call(name: 'read_file', preview: 'plain'),
          resultText: 'plain',
        ),
        isFalse,
      );
    });

    test('name 为 null / 空串 / 纯空白 → 只看结果与 preview', () {
      for (final name in <String?>[null, '', '   ']) {
        expect(
          ToolCallDisplayFormatter.usesMonospace(
            _call(name: name, preview: 'plain'),
            resultText: 'plain',
          ),
          isFalse,
          reason: 'name=$name 不应判等宽',
        );
      }
    });

    test('resultText 含换行 → true（preview 为 null 也成立）', () {
      expect(
        ToolCallDisplayFormatter.usesMonospace(
          _call(name: 'read_file'),
          resultText: 'a\nb',
        ),
        isTrue,
      );
    });

    test('preview 可解析成 JSON → true（即使结果是单行）', () {
      expect(
        ToolCallDisplayFormatter.usesMonospace(
          _call(name: 'read_file', preview: '{"a":1}'),
          resultText: 'a: 1',
        ),
        isTrue,
      );
      expect(
        ToolCallDisplayFormatter.usesMonospace(
          _call(name: 'read_file', preview: '{"exit_code":1}'),
          resultText: '',
        ),
        isTrue,
      );
    });

    test('preview 为 JSON 字面量 null → false（parse 失败与 JSON null 不可区分）', () {
      expect(
        ToolCallDisplayFormatter.usesMonospace(
          _call(name: 'read_file', preview: 'null'),
          resultText: 'null',
        ),
        isFalse,
      );
    });

    test('preview 为 null / 空串 / 空白 → 只看名字与结果', () {
      for (final preview in <String?>[null, '', '   ']) {
        expect(
          ToolCallDisplayFormatter.usesMonospace(
            _call(name: 'read_file', preview: preview),
            resultText: 'plain',
          ),
          isFalse,
          reason: 'preview=$preview 不应判等宽',
        );
      }
    });

    test('性质：resultText 为 resultText() 的输出时，含换行必然等宽', () {
      final multiline = _call(name: 'read_file', preview: '{"a":1,"b":2}');
      final rendered = ToolCallDisplayFormatter.resultText(multiline);

      expect(rendered.contains('\n'), isTrue);
      expect(
        ToolCallDisplayFormatter.usesMonospace(
          multiline,
          resultText: rendered,
        ),
        isTrue,
      );
    });
  });
}
