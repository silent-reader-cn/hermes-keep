import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/json_value.dart';
import 'package:hermes_ui/core/models/tool_call.dart';

/// `tool_call.dart` 第 12–186 行两个基础类（`ToolCall` / `PersistedToolCall`）补测。
///
/// 专攻模型自身：
/// - `ToolCall` 全部构造参数（含命名构造 `ToolCall.thinking`）、
///   派生 getter（`isThinking` / `displayName` / `isExternalMcp` / `summary`）、
///   内联 `==` / `hashCode` / `toString`（逐字段阶梯式差异）；
/// - `PersistedToolCall` 的 `fromJson` 各分支（lossy 转换、双键回退链逐键、
///   类型不符 / null / 空集合 / 嵌套 `JsonValue`）、`toJson` 条件字段、
///   `toolCall(fallbackIndex)` 的 id 回退、内联 `==` / `hashCode` / `toString`。
///
/// 预期值全部按实现读出来写死；`ToolCallGroup`（187 行起）不在本批范围。
void main() {
  group('ToolCall 构造', () {
    test('全部构造参数逐项落位', () {
      final call = ToolCall(
        id: 'fixed-1',
        name: 'read_file',
        preview: 'preview text',
        args: {'path': const JsonString('/a/b.txt')},
        duration: 1.25,
        isError: true,
        isCompleted: true,
        thinking: '想了很久',
        startedAt: 100.5,
      );

      expect(call.id, 'fixed-1');
      expect(call.name, 'read_file');
      expect(call.preview, 'preview text');
      expect(call.args, {'path': const JsonString('/a/b.txt')});
      expect(call.duration, 1.25);
      expect(call.isError, isTrue);
      expect(call.isCompleted, isTrue);
      expect(call.thinking, '想了很久');
      expect(call.startedAt, 100.5);
    });

    test('可选参数默认值：id 自动生成 / startedAt 取当前秒 / isCompleted=false', () {
      final before = DateTime.now().millisecondsSinceEpoch / 1000;
      final call = ToolCall();
      final after = DateTime.now().millisecondsSinceEpoch / 1000;

      expect(call.id, startsWith('live-tool-'));
      expect(call.id.length, greaterThan('live-tool-'.length));
      expect(call.name, isNull);
      expect(call.preview, isNull);
      expect(call.args, isNull);
      expect(call.duration, isNull);
      expect(call.isError, isNull);
      expect(call.isCompleted, isFalse);
      expect(call.thinking, isNull);
      expect(call.startedAt, greaterThanOrEqualTo(before));
      expect(call.startedAt, lessThanOrEqualTo(after));
    });

    test('显式 id / startedAt 覆盖默认值；两次自生成 id 不同', () {
      final a = ToolCall(id: 'same', startedAt: 0.0);
      final b = ToolCall(id: 'same', startedAt: 0.0);

      expect(a.id, 'same');
      expect(a.startedAt, 0.0);
      expect(a, equals(b));
      expect(ToolCall().id, isNot(equals(ToolCall().id)));
    });

    test('ToolCall.thinking 命名构造：name=thinking / isCompleted=true', () {
      final call = ToolCall.thinking('思考内容');

      expect(call.name, 'thinking');
      expect(call.thinking, '思考内容');
      expect(call.isCompleted, isTrue);
      expect(call.isThinking, isTrue);
      expect(call.id, startsWith('live-tool-'));
    });
  });

  group('ToolCall 派生 getter', () {
    test('isThinking：null / 空串 / 纯空白 为 false，非空为 true', () {
      expect(ToolCall().isThinking, isFalse);
      expect(ToolCall(thinking: '').isThinking, isFalse);
      expect(ToolCall(thinking: '   ').isThinking, isFalse);
      expect(ToolCall(thinking: '\n\t ').isThinking, isFalse);
      expect(ToolCall(thinking: 'x').isThinking, isTrue);
      expect(ToolCall(thinking: ' x ').isThinking, isTrue);
    });

    test('displayName：null / 空 / 纯空白 → Tool，否则 trim 后原文', () {
      expect(ToolCall().displayName, 'Tool');
      expect(ToolCall(name: '').displayName, 'Tool');
      expect(ToolCall(name: '   ').displayName, 'Tool');
      expect(ToolCall(name: '\n').displayName, 'Tool');
      expect(ToolCall(name: 'bash').displayName, 'bash');
      expect(ToolCall(name: '  bash  ').displayName, 'bash');
    });

    test('isExternalMcp：mcp__ 前缀（大小写不敏感、trim 后）为 true', () {
      expect(ToolCall(name: 'mcp__fs__read').isExternalMcp, isTrue);
      expect(ToolCall(name: 'MCP__fs__read').isExternalMcp, isTrue);
      expect(ToolCall(name: '  mcp__fs__read  ').isExternalMcp, isTrue);
      expect(ToolCall(name: 'mcp__').isExternalMcp, isTrue);
      expect(ToolCall(name: 'read_file').isExternalMcp, isFalse);
      expect(ToolCall(name: 'Mcp').isExternalMcp, isFalse);
      // name 全空时 displayName 回落 'Tool' → 不是外部工具。
      expect(ToolCall(name: '  ').isExternalMcp, isFalse);
      expect(ToolCall().isExternalMcp, isFalse);
    });

    test('summary：走 toolCallSummary（命中分类 / 通用回落 / preview 回落 / null）', () {
      expect(
        ToolCall(
          name: 'bash',
          args: {'command': const JsonString('echo hi')},
        ).summary,
        'echo hi',
      );
      // name 缺失 → displayName 回落 'Tool' → toolName 空串，走分类外回落链。
      expect(
        ToolCall(args: {'path': const JsonString('/a/b.txt')}).summary,
        'b.txt',
      );
      // args 为 null → 回落 preview（去换行）。
      expect(ToolCall(preview: 'line1\nline2').summary, 'line1 line2');
      expect(ToolCall(preview: '   ').summary, isNull);
      expect(ToolCall().summary, isNull);
      // 思考子卡没有 args/preview → 无摘要。
      expect(ToolCall.thinking('想').summary, isNull);
    });
  });

  group('ToolCall == / hashCode / toString', () {
    ToolCall build() => ToolCall(
      id: 'a',
      name: 'read_file',
      preview: 'p',
      args: {'path': const JsonString('/a.txt')},
      duration: 2.0,
      isError: false,
      isCompleted: true,
      thinking: 'think',
      startedAt: 7.0,
    );

    test('同值不同实例：== 为 true 且 hashCode 相同（args 走 deepEquals）', () {
      expect(build(), equals(build()));
      expect(build().hashCode, build().hashCode);
      expect(build() == Object(), isFalse);
    });

    test('逐字段阶梯式差异：任一字段不同即 !=（覆盖 && 每一行比较）', () {
      expect(build() == ToolCall(
        id: 'b',
        name: 'read_file',
        preview: 'p',
        args: {'path': const JsonString('/a.txt')},
        duration: 2.0,
        isError: false,
        isCompleted: true,
        thinking: 'think',
        startedAt: 7.0,
      ), isFalse);
      expect(build() == ToolCall(
        id: 'a',
        name: 'write_file',
        preview: 'p',
        args: {'path': const JsonString('/a.txt')},
        duration: 2.0,
        isError: false,
        isCompleted: true,
        thinking: 'think',
        startedAt: 7.0,
      ), isFalse);
      expect(build() == ToolCall(
        id: 'a',
        name: 'read_file',
        preview: 'q',
        args: {'path': const JsonString('/a.txt')},
        duration: 2.0,
        isError: false,
        isCompleted: true,
        thinking: 'think',
        startedAt: 7.0,
      ), isFalse);
      // args 存在性差异
      expect(build() == ToolCall(
        id: 'a',
        name: 'read_file',
        preview: 'p',
        duration: 2.0,
        isError: false,
        isCompleted: true,
        thinking: 'think',
        startedAt: 7.0,
      ), isFalse);
      // args 值差异（同长度不同值 → deepEquals 逐项比较）
      expect(build() == ToolCall(
        id: 'a',
        name: 'read_file',
        preview: 'p',
        args: {'path': const JsonString('/b.txt')},
        duration: 2.0,
        isError: false,
        isCompleted: true,
        thinking: 'think',
        startedAt: 7.0,
      ), isFalse);
      // args 长度差异
      expect(build() == ToolCall(
        id: 'a',
        name: 'read_file',
        preview: 'p',
        args: {
          'path': const JsonString('/a.txt'),
          'extra': const JsonNull(),
        },
        duration: 2.0,
        isError: false,
        isCompleted: true,
        thinking: 'think',
        startedAt: 7.0,
      ), isFalse);
      // args 同长度但键名不同（走 deepEquals 的 containsKey 分支）
      expect(
        ToolCall(args: {'x': const JsonString('1')}) ==
            ToolCall(args: {'y': const JsonString('1')}),
        isFalse,
      );
      expect(build() == ToolCall(
        id: 'a',
        name: 'read_file',
        preview: 'p',
        args: {'path': const JsonString('/a.txt')},
        duration: 3.0,
        isError: false,
        isCompleted: true,
        thinking: 'think',
        startedAt: 7.0,
      ), isFalse);
      expect(build() == ToolCall(
        id: 'a',
        name: 'read_file',
        preview: 'p',
        args: {'path': const JsonString('/a.txt')},
        duration: 2.0,
        isError: true,
        isCompleted: true,
        thinking: 'think',
        startedAt: 7.0,
      ), isFalse);
      expect(build() == ToolCall(
        id: 'a',
        name: 'read_file',
        preview: 'p',
        args: {'path': const JsonString('/a.txt')},
        duration: 2.0,
        isError: false,
        isCompleted: false,
        thinking: 'think',
        startedAt: 7.0,
      ), isFalse);
      expect(build() == ToolCall(
        id: 'a',
        name: 'read_file',
        preview: 'p',
        args: {'path': const JsonString('/a.txt')},
        duration: 2.0,
        isError: false,
        isCompleted: true,
        thinking: 'other',
        startedAt: 7.0,
      ), isFalse);
      expect(build() == ToolCall(
        id: 'a',
        name: 'read_file',
        preview: 'p',
        args: {'path': const JsonString('/a.txt')},
        duration: 2.0,
        isError: false,
        isCompleted: true,
        thinking: 'think',
        startedAt: 8.0,
      ), isFalse);
      // thinking null vs 'think'（前面已覆盖相反方向）
      expect(
        ToolCall(thinking: null, startedAt: 1) ==
            ToolCall(thinking: 'think', startedAt: 1),
        isFalse,
      );
    });

    test('args 嵌套集合（JsonObject / JsonArray）也走深度比较', () {
      // id / startedAt 固定，只让 args 参与差异比较。
      ToolCall withArgs(Map<String, JsonValue> args) =>
          ToolCall(id: 'n', startedAt: 1, args: args);

      final nestedEqual = withArgs({
        'obj': const JsonObject({'k': JsonArray([JsonNumber(1.0)])}),
      });
      final nestedSame = withArgs({
        'obj': const JsonObject({'k': JsonArray([JsonNumber(1.0)])}),
      });
      final nestedDifferentValue = withArgs({
        'obj': const JsonObject({'k': JsonArray([JsonNumber(2.0)])}),
      });

      expect(nestedEqual, equals(nestedSame));
      expect(nestedEqual.hashCode, nestedSame.hashCode);
      expect(nestedEqual == nestedDifferentValue, isFalse);
      expect(
        withArgs({'obj': const JsonObject({'k': JsonNull()})}) ==
            withArgs({'obj': const JsonObject({})}),
        isFalse,
      );
      // 值类型不同的 JsonValue 不等（JsonBool vs JsonString 'true'）
      expect(
        withArgs({'flag': const JsonBool(true)}) ==
            withArgs({'flag': const JsonString('true')}),
        isFalse,
      );
      // 嵌套数组长度不同
      expect(
        withArgs({
          'list': const JsonArray([JsonNumber(1.0)]),
        }) ==
            withArgs({
              'list': const JsonArray([JsonNumber(1.0), JsonNumber(2.0)]),
            }),
        isFalse,
      );
    });

    test('toString：固定格式（不含 preview 之外的可选字段）', () {
      expect(
        build().toString(),
        'ToolCall(id: a, name: read_file, preview: p, '
        'isCompleted: true, isError: false)',
      );
      expect(
        ToolCall(id: 'z').toString(),
        'ToolCall(id: z, name: null, preview: null, '
        'isCompleted: false, isError: null)',
      );
    });
  });

  group('PersistedToolCall.fromJson', () {
    test('全字段正常解析（含嵌套 args 的 JsonValue 形态）', () {
      final call = PersistedToolCall.fromJson({
        'name': 'write_file',
        'snippet': 'Wrote /tmp/a.txt',
        'tid': 'call_9',
        'assistant_msg_idx': 3,
        'args': {
          'path': '/tmp/a.txt',
          'count': 3,
          'ratio': 1.5,
          'flag': true,
          'nil': null,
          'nested': {'k': 'v'},
          'list': [1, 'x'],
        },
        'is_error': false,
      });

      expect(call.name, 'write_file');
      expect(call.snippet, 'Wrote /tmp/a.txt');
      expect(call.tid, 'call_9');
      expect(call.assistantMsgIdx, 3);
      expect(call.isError, isFalse);
      expect(call.args, hasLength(7));
      expect(call.args!['path'], const JsonString('/tmp/a.txt'));
      expect(call.args!['count'], const JsonNumber(3.0));
      expect(call.args!['ratio'], const JsonNumber(1.5));
      expect(call.args!['flag'], const JsonBool(true));
      expect(call.args!['nil'], const JsonNull());
      expect(
        call.args!['nested'],
        const JsonObject({'k': JsonString('v')}),
      );
      expect(
        call.args!['list'],
        const JsonArray([JsonNumber(1.0), JsonString('x')]),
      );
    });

    test('空 map：全部字段 null', () {
      final call = PersistedToolCall.fromJson({});

      expect(call.name, isNull);
      expect(call.snippet, isNull);
      expect(call.tid, isNull);
      expect(call.assistantMsgIdx, isNull);
      expect(call.args, isNull);
      expect(call.isError, isNull);
    });

    test('name / snippet / tid 是 lossyString：类型不符做宽容转换', () {
      expect(
        PersistedToolCall.fromJson({'name': 1}).name,
        '1',
      );
      expect(
        PersistedToolCall.fromJson({'name': 1.5}).name,
        '1.5',
      );
      expect(
        PersistedToolCall.fromJson({'name': true}).name,
        'true',
      );
      expect(
        PersistedToolCall.fromJson({'name': false}).name,
        'false',
      );
      // 集合 / null 无法转换 → null（不 throw）
      expect(PersistedToolCall.fromJson({'name': []}).name, isNull);
      expect(PersistedToolCall.fromJson({'name': <Object?>[]}).name, isNull);
      expect(PersistedToolCall.fromJson({'name': {}}).name, isNull);
      expect(PersistedToolCall.fromJson({'name': null}).name, isNull);
      // 空串原样保留（不被 lossy 吞掉）
      expect(PersistedToolCall.fromJson({'name': ''}).name, '');

      expect(PersistedToolCall.fromJson({'snippet': 7}).snippet, '7');
      expect(PersistedToolCall.fromJson({'snippet': true}).snippet, 'true');
      expect(PersistedToolCall.fromJson({'snippet': []}).snippet, isNull);
      expect(PersistedToolCall.fromJson({'tid': 8}).tid, '8');
      expect(PersistedToolCall.fromJson({'tid': {}}).tid, isNull);
      expect(PersistedToolCall.fromJson({'tid': ''}).tid, '');
    });

    test('assistant_msg_idx 双键回退：蛇形键优先于驼峰键', () {
      expect(
        PersistedToolCall.fromJson({'assistant_msg_idx': 3}).assistantMsgIdx,
        3,
      );
      expect(
        PersistedToolCall.fromJson({'assistantMsgIdx': 5}).assistantMsgIdx,
        5,
      );
      expect(
        PersistedToolCall.fromJson({
          'assistant_msg_idx': 1,
          'assistantMsgIdx': 2,
        }).assistantMsgIdx,
        1,
      );
      // 蛇形键值无效（null / 类型不符）→ 继续尝试驼峰键
      expect(
        PersistedToolCall.fromJson({
          'assistant_msg_idx': null,
          'assistantMsgIdx': 7,
        }).assistantMsgIdx,
        7,
      );
      expect(
        PersistedToolCall.fromJson({
          'assistant_msg_idx': 'oops',
          'assistantMsgIdx': 7,
        }).assistantMsgIdx,
        7,
      );
      expect(
        PersistedToolCall.fromJson({
          'assistant_msg_idx': true,
          'assistantMsgIdx': 7,
        }).assistantMsgIdx,
        7,
      );
      // 两个键都无效 → null
      expect(
        PersistedToolCall.fromJson({
          'assistant_msg_idx': 'oops',
          'assistantMsgIdx': false,
        }).assistantMsgIdx,
        isNull,
      );
      // 未列入回退链的近似写法不被识别（取证：仅有这两条键）
      expect(
        PersistedToolCall.fromJson({'assistantMsgIndex': 9}).assistantMsgIdx,
        isNull,
      );
    });

    test('assistant_msg_idx 走 lossyInt：数字字符串 / 小数截断 / 溢出 / 错型', () {
      expect(
        PersistedToolCall.fromJson({'assistant_msg_idx': '3'}).assistantMsgIdx,
        3,
      );
      expect(
        PersistedToolCall.fromJson({
          'assistant_msg_idx': ' 4 ',
        }).assistantMsgIdx,
        4,
      );
      expect(
        PersistedToolCall.fromJson({'assistant_msg_idx': 2.7}).assistantMsgIdx,
        2,
      );
      expect(
        PersistedToolCall.fromJson({
          'assistant_msg_idx': -2.7,
        }).assistantMsgIdx,
        -2,
      );
      expect(
        PersistedToolCall.fromJson({'assistant_msg_idx': '3.9'}).assistantMsgIdx,
        3,
      );
      expect(
        PersistedToolCall.fromJson({'assistant_msg_idx': '3.9.9'})
            .assistantMsgIdx,
        isNull,
      );
      expect(
        PersistedToolCall.fromJson({'assistant_msg_idx': double.nan})
            .assistantMsgIdx,
        isNull,
      );
      expect(
        PersistedToolCall.fromJson({
          'assistant_msg_idx': double.infinity,
        }).assistantMsgIdx,
        isNull,
      );
      expect(
        PersistedToolCall.fromJson({'assistant_msg_idx': []}).assistantMsgIdx,
        isNull,
      );
      expect(
        PersistedToolCall.fromJson({'assistant_msg_idx': {}}).assistantMsgIdx,
        isNull,
      );
      expect(
        PersistedToolCall.fromJson({'assistant_msg_idx': true})
            .assistantMsgIdx,
        isNull,
      );
      expect(
        PersistedToolCall.fromJson({'assistant_msg_idx': 0}).assistantMsgIdx,
        0,
      );
    });

    test('is_error 双键回退：蛇形键优先于驼峰键', () {
      expect(PersistedToolCall.fromJson({'is_error': true}).isError, isTrue);
      expect(PersistedToolCall.fromJson({'isError': true}).isError, isTrue);
      expect(
        PersistedToolCall.fromJson({
          'is_error': false,
          'isError': true,
        }).isError,
        isFalse,
      );
      expect(
        PersistedToolCall.fromJson({
          'is_error': 2,
          'isError': true,
        }).isError,
        isTrue,
      );
      expect(
        PersistedToolCall.fromJson({
          'is_error': 'maybe',
          'isError': 'no',
        }).isError,
        isFalse,
      );
      expect(
        PersistedToolCall.fromJson({
          'is_error': 'maybe',
          'isError': 'nope',
        }).isError,
        isNull,
      );
      expect(PersistedToolCall.fromJson({'isError': null}).isError, isNull);
      // 近似写法不被识别
      expect(PersistedToolCall.fromJson({'iserror': true}).isError, isNull);
      expect(PersistedToolCall.fromJson({'is_err': true}).isError, isNull);
    });

    test('is_error 走 lossyBool：0/1 数字、yes/no 字符串、其他数字为 null', () {
      expect(PersistedToolCall.fromJson({'is_error': 1}).isError, isTrue);
      expect(PersistedToolCall.fromJson({'is_error': 0}).isError, isFalse);
      expect(PersistedToolCall.fromJson({'is_error': 2}).isError, isNull);
      expect(PersistedToolCall.fromJson({'is_error': -1}).isError, isNull);
      expect(PersistedToolCall.fromJson({'is_error': 'YES'}).isError, isTrue);
      expect(PersistedToolCall.fromJson({'is_error': '1'}).isError, isTrue);
      expect(PersistedToolCall.fromJson({'is_error': 'No'}).isError, isFalse);
      expect(PersistedToolCall.fromJson({'is_error': '0'}).isError, isFalse);
      expect(PersistedToolCall.fromJson({'is_error': '2'}).isError, isNull);
      expect(PersistedToolCall.fromJson({'is_error': <Object?>[]}).isError,
          isNull);
      expect(PersistedToolCall.fromJson({'is_error': {}}).isError, isNull);
      expect(PersistedToolCall.fromJson({'is_error': false}).isError, isFalse);
    });

    test('args：仅接受对象；空对象 → 空 map；非对象 / null → null', () {
      final call = PersistedToolCall.fromJson({
        'args': {'path': '/a.txt'},
      });
      expect(call.args, {'path': const JsonString('/a.txt')});

      final empty = PersistedToolCall.fromJson({'args': <String, Object?>{}});
      expect(empty.args, isNotNull);
      expect(empty.args, isEmpty);

      expect(PersistedToolCall.fromJson({'args': 'not-an-object'}).args, isNull);
      expect(PersistedToolCall.fromJson({'args': 1}).args, isNull);
      expect(PersistedToolCall.fromJson({'args': true}).args, isNull);
      expect(PersistedToolCall.fromJson({'args': <Object?>[]}).args, isNull);
      expect(PersistedToolCall.fromJson({'args': null}).args, isNull);
      expect(PersistedToolCall.fromJson({}).args, isNull);
    });

    test('合并畸形输入：错型字段各自容错，互不影响', () {
      final call = PersistedToolCall.fromJson({
        'name': 1,
        'snippet': false,
        'tid': null,
        'assistant_msg_idx': 'oops',
        'args': 'not-an-object',
        'is_error': 'maybe',
      });

      expect(call.name, '1');
      expect(call.snippet, 'false');
      expect(call.tid, isNull);
      expect(call.assistantMsgIdx, isNull);
      expect(call.args, isNull);
      expect(call.isError, isNull);
    });
  });

  group('PersistedToolCall.toJson', () {
    test('全字段：输出用蛇形键名（assistant_msg_idx / is_error）', () {
      const call = PersistedToolCall(
        name: 'read_file',
        snippet: 'snip',
        tid: 't1',
        assistantMsgIdx: 2,
        args: {'path': JsonString('/a.txt')},
        isError: true,
      );

      final json = call.toJson();
      expect(json, {
        'name': 'read_file',
        'snippet': 'snip',
        'tid': 't1',
        'assistant_msg_idx': 2,
        'args': {'path': '/a.txt'},
        'is_error': true,
      });
      expect(json.keys, containsAll(<String>['assistant_msg_idx', 'is_error']));
      expect(json.containsKey('assistantMsgIdx'), isFalse);
      expect(json.containsKey('isError'), isFalse);
    });

    test('全部字段为 null → 空 map（条件字段全被省略）', () {
      expect(const PersistedToolCall().toJson(), isEmpty);
    });

    test('假值字段（false / 0 / 空串 / 空集合）仍写出，不按真值判断', () {
      expect(const PersistedToolCall(isError: false).toJson(), {
        'is_error': false,
      });
      expect(const PersistedToolCall(assistantMsgIdx: 0).toJson(), {
        'assistant_msg_idx': 0,
      });
      expect(const PersistedToolCall(name: '').toJson(), {'name': ''});
      expect(const PersistedToolCall(snippet: '').toJson(), {'snippet': ''});
      expect(const PersistedToolCall(tid: '').toJson(), {'tid': ''});
      expect(const PersistedToolCall(args: <String, JsonValue>{}).toJson(), {
        'args': <String, Object?>{},
      });
    });

    test('args 是 JsonObject 的 toJson：嵌套对象 / 数组 / null 逐层展开', () {
      const call = PersistedToolCall(
        args: {
          'path': JsonString('/a.txt'),
          'count': JsonNumber(3.0),
          'ratio': JsonNumber(1.5),
          'flag': JsonBool(true),
          'nil': JsonNull(),
          'nested': JsonObject({'k': JsonString('v')}),
          'list': JsonArray([JsonNumber(1.0), JsonString('x'), JsonNull()]),
        },
      );

      expect(call.toJson(), {
        'args': {
          'path': '/a.txt',
          'count': 3.0,
          'ratio': 1.5,
          'flag': true,
          'nil': null,
          'nested': {'k': 'v'},
          'list': [1.0, 'x', null],
        },
      });
    });

    test('fromJson → toJson 往返：相同键值语义（含 args）', () {
      final source = <String, Object?>{
        'name': 'bash',
        'snippet': 'echo hi',
        'tid': 't2',
        'assistantMsgIdx': 1,
        'args': {'command': 'echo hi'},
        'isError': false,
      };
      final call = PersistedToolCall.fromJson(source);

      expect(call.toJson(), {
        'name': 'bash',
        'snippet': 'echo hi',
        'tid': 't2',
        'assistant_msg_idx': 1,
        'args': {'command': 'echo hi'},
        'is_error': false,
      });
      expect(PersistedToolCall.fromJson(call.toJson()), equals(call));
      expect(PersistedToolCall.fromJson(call.toJson()).hashCode, call.hashCode);
    });
  });

  group('PersistedToolCall.toolCall', () {
    test('tid 非空 → id 用 tid；字段映射到 ToolCall', () {
      const persisted = PersistedToolCall(
        name: 'write_file',
        snippet: 'Wrote /tmp/a.txt',
        tid: 'call_9',
        assistantMsgIdx: 3,
        args: {'path': JsonString('/tmp/a.txt')},
        isError: true,
      );

      final call = persisted.toolCall(4);

      expect(call.id, 'call_9');
      expect(call.name, 'write_file');
      expect(call.preview, 'Wrote /tmp/a.txt');
      expect(call.args, same(persisted.args));
      expect(call.isError, isTrue);
      expect(call.isCompleted, isTrue);
      expect(call.duration, isNull);
      expect(call.thinking, isNull);
    });

    test('tid 缺失 / 空 / 纯空白 → persisted-tool-<fallbackIndex>', () {
      expect(const PersistedToolCall(name: 'x').toolCall(0).id,
          'persisted-tool-0');
      expect(const PersistedToolCall(name: 'x').toolCall(7).id,
          'persisted-tool-7');
      expect(const PersistedToolCall(tid: '').toolCall(2).id,
          'persisted-tool-2');
      expect(const PersistedToolCall(tid: '   ').toolCall(-1).id,
          'persisted-tool--1');
    });

    test('tid 前后空白被 trim 后作为 id', () {
      expect(const PersistedToolCall(tid: '  call_2  ').toolCall(0).id,
          'call_2');
      expect(const PersistedToolCall(tid: '\ncall_3\t').toolCall(0).id,
          'call_3');
    });

    test('全字段为 null 的存档 → ToolCall 仍可用（id 回退、isCompleted=true）', () {
      final call = const PersistedToolCall().toolCall(5);

      expect(call.id, 'persisted-tool-5');
      expect(call.name, isNull);
      expect(call.preview, isNull);
      expect(call.args, isNull);
      expect(call.isError, isNull);
      expect(call.isCompleted, isTrue);
      expect(call.displayName, 'Tool');
      expect(call.isThinking, isFalse);
      expect(call.summary, isNull);
    });

    test('toolCall 结果参与 ToolCall 值相等（同 id/字段 → ==）', () {
      const persisted = PersistedToolCall(name: 'a', tid: 't', snippet: 's');

      expect(persisted.toolCall(0).id, 't');
      expect(
        const PersistedToolCall(name: 'a', tid: 't', snippet: 's').toolCall(1),
        equals(persisted.toolCall(0)),
      );
      // 无 tid 时两个不同 fallbackIndex 产生的 id 不同 → 实例不等
      expect(
        const PersistedToolCall(name: 'a').toolCall(0) ==
            const PersistedToolCall(name: 'a').toolCall(1),
        isFalse,
      );
    });
  });

  group('PersistedToolCall == / hashCode / toString', () {
    const base = PersistedToolCall(
      name: 'read_file',
      snippet: 'snip',
      tid: 't1',
      assistantMsgIdx: 2,
      args: {'path': JsonString('/a.txt')},
      isError: false,
    );

    test('同值 → == true 且 hashCode 相同；与非本类比较为 false', () {
      expect(
        base,
        equals(
          const PersistedToolCall(
            name: 'read_file',
            snippet: 'snip',
            tid: 't1',
            assistantMsgIdx: 2,
            args: {'path': JsonString('/a.txt')},
            isError: false,
          ),
        ),
      );
      expect(base.hashCode, base.hashCode);
      expect(base == Object(), isFalse);
      // 类型守卫：与非本类实例比较为 false（用 Object 静态类型避免 analyze 提示）
      final Object otherType = ToolCall(id: 't1');
      expect(base == otherType, isFalse);
      expect(const PersistedToolCall() == const PersistedToolCall(name: 'x'),
          isFalse);
    });

    test('逐字段阶梯式差异：任一字段不同即 !=（覆盖 && 每一行比较）', () {
      expect(base == const PersistedToolCall(
        name: 'write_file',
        snippet: 'snip',
        tid: 't1',
        assistantMsgIdx: 2,
        args: {'path': JsonString('/a.txt')},
        isError: false,
      ), isFalse);
      expect(base == const PersistedToolCall(
        name: 'read_file',
        snippet: 'other',
        tid: 't1',
        assistantMsgIdx: 2,
        args: {'path': JsonString('/a.txt')},
        isError: false,
      ), isFalse);
      expect(base == const PersistedToolCall(
        name: 'read_file',
        snippet: 'snip',
        tid: 't2',
        assistantMsgIdx: 2,
        args: {'path': JsonString('/a.txt')},
        isError: false,
      ), isFalse);
      expect(base == const PersistedToolCall(
        name: 'read_file',
        snippet: 'snip',
        tid: 't1',
        assistantMsgIdx: 3,
        args: {'path': JsonString('/a.txt')},
        isError: false,
      ), isFalse);
      expect(base == const PersistedToolCall(
        name: 'read_file',
        snippet: 'snip',
        tid: 't1',
        assistantMsgIdx: 2,
        args: {'path': JsonString('/a.txt')},
        isError: true,
      ), isFalse);
      // args：存在性差异
      expect(base == const PersistedToolCall(
        name: 'read_file',
        snippet: 'snip',
        tid: 't1',
        assistantMsgIdx: 2,
        isError: false,
      ), isFalse);
      // args：值差异（deepEquals 逐项比较）
      expect(base == const PersistedToolCall(
        name: 'read_file',
        snippet: 'snip',
        tid: 't1',
        assistantMsgIdx: 2,
        args: {'path': JsonString('/b.txt')},
        isError: false,
      ), isFalse);
      // args：长度差异
      expect(base == const PersistedToolCall(
        name: 'read_file',
        snippet: 'snip',
        tid: 't1',
        assistantMsgIdx: 2,
        args: {'path': JsonString('/a.txt'), 'n': JsonNumber(1)},
        isError: false,
      ), isFalse);
    });

    test('toString：固定格式', () {
      expect(
        base.toString(),
        'PersistedToolCall(name: read_file, snippet: snip, '
        'tid: t1, assistantMsgIdx: 2)',
      );
      expect(
        const PersistedToolCall().toString(),
        'PersistedToolCall(name: null, snippet: null, '
        'tid: null, assistantMsgIdx: null)',
      );
    });
  });
}
