import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/json_value.dart';
import 'package:hermes_ui/core/models/model_favorite.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';

/// `uuidV4()` 产物形状：8-4-4-4-12 小写十六进制，第 13 位固定 v4，
/// 变体位落在 8/9/a/b。
final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// 把 `Map<String, Object?>` 原样转成 `JsonObject`（保持与 jsonDecode 同构）。
JsonObject _obj(Map<String, Object?> raw) =>
    JsonValue.fromJson(raw) as JsonObject;

void main() {
  // ==========================================================================
  // CommandsResponse + AgentCommand
  // ==========================================================================
  group('CommandsResponse', () {
    test('fromJson：命令数组正常解析（含全部字段）', () {
      final response = CommandsResponse.fromJson({
        'commands': [
          {
            'name': 'help',
            'description': 'show help',
            'category': 'core',
            'aliases': ['h', '?'],
            'args_hint': '[cmd]',
            'subcommands': ['list', 'show'],
            'cli_only': true,
            'gateway_only': false,
          },
          {'name': 'model'},
        ],
      });

      expect(response.commands, hasLength(2));
      final first = response.commands!.first;
      expect(first.name, 'help');
      expect(first.description, 'show help');
      expect(first.category, 'core');
      expect(first.aliases, ['h', '?']);
      expect(first.argsHint, '[cmd]');
      expect(first.subcommands, ['list', 'show']);
      expect(first.cliOnly, true);
      expect(first.gatewayOnly, false);
      expect(response.commands!.last.name, 'model');
      expect(response.commands!.last.aliases, isNull);
    });

    test('fromJson：空集合 / 缺失 / null → null 或空列表', () {
      expect(CommandsResponse.fromJson(const {}).commands, isNull);
      expect(CommandsResponse.fromJson({'commands': null}).commands, isNull);
      expect(
        CommandsResponse.fromJson(const {'commands': <Object?>[]}).commands,
        isEmpty,
      );
      // 空对象元素仍是合法对象（全字段 null）。
      final blank = CommandsResponse.fromJson(const {
        'commands': <Object?>[<String, Object?>{}],
      });
      expect(blank.commands, hasLength(1));
      expect(blank.commands!.single.name, isNull);
      expect(blank.commands!.single.id, isNotNull);
    });

    test('fromJson：类型不符（非 List / 元素非对象）→ null', () {
      expect(CommandsResponse.fromJson({'commands': 'bad'}).commands, isNull);
      expect(CommandsResponse.fromJson({'commands': 1}).commands, isNull);
      expect(
        CommandsResponse.fromJson({
          'commands': {'name': 'x'},
        }).commands,
        isNull,
      );
      expect(CommandsResponse.fromJson(const {'commands': [1]}).commands, isNull);
      expect(
        CommandsResponse.fromJson(const {
          'commands': [
            <String, Object?>{'name': 'ok'},
            'bad',
          ],
        }).commands,
        isNull,
      );
    });

    test('fromJson：无 camelCase 回退（commands 无别名键）', () {
      expect(
        CommandsResponse.fromJson(const {'Commands': <Object?>[]}).commands,
        isNull,
      );
    });

    test('== / hashCode / toString（阶梯式）', () {
      CommandsResponse build(List<Object?>? commands) =>
          CommandsResponse.fromJson({'commands': commands});

      final base = build([
        {'name': 'a', 'description': 'd'},
      ]);
      expect(base, build([{'name': 'a', 'description': 'd'}]));
      expect(
        base.hashCode,
        build([{'name': 'a', 'description': 'd'}]).hashCode,
      );
      expect(base.toString(), 'CommandsResponse(commands: 1)');
      expect(
        const CommandsResponse().toString(),
        'CommandsResponse(commands: null)',
      );

      // null vs 空列表（deepEquals 的 null 分支）。
      expect(base == const CommandsResponse(), isFalse);
      expect(const CommandsResponse() == build(const <Object?>[]), isFalse);
      // 长度不同。
      expect(
        base ==
            build([
              {'name': 'a', 'description': 'd'},
              {'name': 'b'},
            ]),
        isFalse,
      );
      // 同长度、逐元素只差一个字段（走 AgentCommand ==）。
      expect(base == build([{'name': 'b', 'description': 'd'}]), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  group('AgentCommand', () {
    test('fromJson：正常键全解析 + 宽容转换', () {
      final command = AgentCommand.fromJson({
        'name': 'help',
        'description': 'd',
        'category': 'c',
        'aliases': ['h'],
        'args_hint': 'hint',
        'subcommands': ['s'],
        'cli_only': 1,
        'gateway_only': 'no',
      });
      expect(command.name, 'help');
      expect(command.description, 'd');
      expect(command.category, 'c');
      expect(command.aliases, ['h']);
      expect(command.argsHint, 'hint');
      expect(command.subcommands, ['s']);
      expect(command.cliOnly, true);
      expect(command.gatewayOnly, false);
    });

    test('fromJson：缺失 / null / 类型不符 → null', () {
      final empty = AgentCommand.fromJson(const {});
      expect(empty.name, isNull);
      expect(empty.description, isNull);
      expect(empty.category, isNull);
      expect(empty.aliases, isNull);
      expect(empty.argsHint, isNull);
      expect(empty.subcommands, isNull);
      expect(empty.cliOnly, isNull);
      expect(empty.gatewayOnly, isNull);

      final nulls = AgentCommand.fromJson({
        'name': null,
        'description': null,
        'category': null,
        'aliases': null,
        'args_hint': null,
        'subcommands': null,
        'cli_only': null,
        'gateway_only': null,
      });
      expect(nulls.name, isNull);
      expect(nulls.cliOnly, isNull);
      expect(nulls.gatewayOnly, isNull);

      final wrong = AgentCommand.fromJson({
        'name': [1],
        'description': {'a': 1},
        'category': 2.5,
        'aliases': 'bad',
        'args_hint': <Object?>[],
        'subcommands': 7,
        'cli_only': 2,
        'gateway_only': 'maybe',
      });
      expect(wrong.name, isNull);
      expect(wrong.description, isNull);
      // lossyString 会把 double 转字符串。
      expect(wrong.category, '2.5');
      expect(wrong.aliases, isNull);
      expect(wrong.argsHint, isNull);
      expect(wrong.subcommands, isNull);
      expect(wrong.cliOnly, isNull);
      expect(wrong.gatewayOnly, isNull);
    });

    test('fromJson：字符串数组要求全元素为 String（混合 → null）', () {
      expect(AgentCommand.fromJson(const {'aliases': <Object?>[]}).aliases,
          isEmpty);
      expect(
        AgentCommand.fromJson(const {
          'aliases': <Object?>['a', 1],
        }).aliases,
        isNull,
      );
      expect(
        AgentCommand.fromJson(const {
          'subcommands': <Object?>['a', 1],
        }).subcommands,
        isNull,
      );
    });

    test('fromJson：无 camelCase 回退（argsHint / cliOnly 不认）', () {
      final camel = AgentCommand.fromJson({
        'argsHint': 'h',
        'cliOnly': true,
        'gatewayOnly': true,
      });
      expect(camel.argsHint, isNull);
      expect(camel.cliOnly, isNull);
      expect(camel.gatewayOnly, isNull);
    });

    test('id：name 优先，缺失时回落到 uuidV4', () {
      expect(AgentCommand.fromJson({'name': 'help'}).id, 'help');
      expect(AgentCommand.fromJson(const {}).id, matches(_uuidPattern));
      expect(AgentCommand.fromJson({'name': ''}).id, '');
      // 两条无名命令各自生成不同 uuid。
      final a = AgentCommand.fromJson(const {}).id;
      final b = AgentCommand.fromJson(const {}).id;
      expect(a, isNot(b));
    });

    test('== / hashCode / toString（8 字段逐个阶梯）', () {
      AgentCommand build({
        String? name,
        String? description,
        String? category,
        List<Object?>? aliases,
        String? argsHint,
        List<Object?>? subcommands,
        bool? cliOnly,
        bool? gatewayOnly,
      }) =>
          AgentCommand.fromJson({
            'name': name,
            'description': description,
            'category': category,
            'aliases': aliases,
            'args_hint': argsHint,
            'subcommands': subcommands,
            'cli_only': cliOnly,
            'gateway_only': gatewayOnly,
          });

      final base = build(
        name: 'n1',
        description: 'd1',
        category: 'c1',
        aliases: ['a1'],
        argsHint: 'h1',
        subcommands: ['s1'],
        cliOnly: false,
        gatewayOnly: false,
      );
      expect(
        base,
        build(
          name: 'n1',
          description: 'd1',
          category: 'c1',
          aliases: ['a1'],
          argsHint: 'h1',
          subcommands: ['s1'],
          cliOnly: false,
          gatewayOnly: false,
        ),
      );
      expect(
        base.hashCode,
        build(
          name: 'n1',
          description: 'd1',
          category: 'c1',
          aliases: ['a1'],
          argsHint: 'h1',
          subcommands: ['s1'],
          cliOnly: false,
          gatewayOnly: false,
        ).hashCode,
      );
      expect(base.toString(), 'AgentCommand(name: n1)');
      expect(const AgentCommand().toString(), 'AgentCommand(name: null)');
      // 自身比较 → _listEquals 的 identical 分支。
      expect(base == base, isTrue);

      expect(
          base ==
              build(
                name: 'n2',
                description: 'd1',
                category: 'c1',
                aliases: ['a1'],
                argsHint: 'h1',
                subcommands: ['s1'],
                cliOnly: false,
                gatewayOnly: false,
              ),
          isFalse);
      expect(
          base ==
              build(
                name: 'n1',
                description: 'd2',
                category: 'c1',
                aliases: ['a1'],
                argsHint: 'h1',
                subcommands: ['s1'],
                cliOnly: false,
                gatewayOnly: false,
              ),
          isFalse);
      expect(
          base ==
              build(
                name: 'n1',
                description: 'd1',
                category: 'c2',
                aliases: ['a1'],
                argsHint: 'h1',
                subcommands: ['s1'],
                cliOnly: false,
                gatewayOnly: false,
              ),
          isFalse);
      expect(
          base ==
              build(
                name: 'n1',
                description: 'd1',
                category: 'c1',
                aliases: ['a2'],
                argsHint: 'h1',
                subcommands: ['s1'],
                cliOnly: false,
                gatewayOnly: false,
              ),
          isFalse);
      expect(
          base ==
              build(
                name: 'n1',
                description: 'd1',
                category: 'c1',
                aliases: ['a1'],
                argsHint: 'h2',
                subcommands: ['s1'],
                cliOnly: false,
                gatewayOnly: false,
              ),
          isFalse);
      expect(
          base ==
              build(
                name: 'n1',
                description: 'd1',
                category: 'c1',
                aliases: ['a1'],
                argsHint: 'h1',
                subcommands: ['s2'],
                cliOnly: false,
                gatewayOnly: false,
              ),
          isFalse);
      expect(
          base ==
              build(
                name: 'n1',
                description: 'd1',
                category: 'c1',
                aliases: ['a1'],
                argsHint: 'h1',
                subcommands: ['s1'],
                cliOnly: true,
                gatewayOnly: false,
              ),
          isFalse);
      expect(
          base ==
              build(
                name: 'n1',
                description: 'd1',
                category: 'c1',
                aliases: ['a1'],
                argsHint: 'h1',
                subcommands: ['s1'],
                cliOnly: false,
                gatewayOnly: true,
              ),
          isFalse);
      expect(base == const AgentCommand(), isFalse);
      expect(base == Object(), isFalse);
    });

    test('== ：_listEquals 的 null / 长度 / 元素分支', () {
      AgentCommand build({List<Object?>? aliases, List<Object?>? subcommands}) =>
          AgentCommand.fromJson({
            'aliases': aliases,
            'subcommands': subcommands,
          });

      // null vs 空列表 / 空列表 vs null 都判不等。
      expect(build(aliases: null) == build(aliases: const []), isFalse);
      expect(build(aliases: const []) == build(aliases: null), isFalse);
      // 长度不同。
      expect(build(aliases: ['a']) == build(aliases: ['a', 'b']), isFalse);
      // 等长但元素不同。
      expect(build(aliases: ['a']) == build(aliases: ['b']), isFalse);
      // 等长等值。
      expect(build(aliases: ['a']) == build(aliases: ['a']), isTrue);
      // subcommands 同样走一条。
      expect(build(subcommands: ['a']) == build(subcommands: ['b']), isFalse);
      // 两条 list 都为 null 时 identical 分支命中。
      expect(build() == build(), isTrue);
      // hashCode 对 null 列表走 `?? const []` 分支。
      expect(build().hashCode, build().hashCode);
      expect(build().hashCode == build(aliases: const []).hashCode, isTrue);
    });
  });

  // ==========================================================================
  // ModelsResponse / ModelsRefreshResponse / ProvidersResponse
  // ==========================================================================
  group('ModelsResponse', () {
    test('fromJson：groups / models 走 JsonValue 宽容列表', () {
      final response = ModelsResponse.fromJson({
        'groups': [
          {'provider_id': 'p1', 'models': <Object?>[]},
          'raw-string',
          42,
          true,
          null,
        ],
        'models': ['m1', 2],
        'default_model': 'gpt-5',
        'active_provider': 'p1',
      });
      expect(response.groups, hasLength(5));
      expect(response.groups!.first, isA<JsonObject>());
      expect(response.groups![1], const JsonString('raw-string'));
      expect(response.groups![2], const JsonNumber(42));
      expect(response.groups![3], const JsonBool(true));
      expect(response.groups![4], const JsonNull());
      expect(response.models, hasLength(2));
      expect(response.defaultModel, 'gpt-5');
      expect(response.activeProvider, 'p1');
    });

    test('fromJson：缺失 / null / 非 List → null，空 List → 空', () {
      final empty = ModelsResponse.fromJson(const {});
      expect(empty.groups, isNull);
      expect(empty.models, isNull);
      expect(empty.defaultModel, isNull);
      expect(empty.activeProvider, isNull);

      final nulls = ModelsResponse.fromJson({
        'groups': null,
        'models': null,
        'default_model': null,
        'active_provider': null,
      });
      expect(nulls.groups, isNull);
      expect(nulls.models, isNull);

      final wrong = ModelsResponse.fromJson({
        'groups': 'bad',
        'models': 1,
        'default_model': [1],
        'active_provider': {'a': 1},
      });
      expect(wrong.groups, isNull);
      expect(wrong.models, isNull);
      expect(wrong.defaultModel, isNull);
      expect(wrong.activeProvider, isNull);

      expect(
        ModelsResponse.fromJson(const {'groups': <Object?>[]}).groups,
        isEmpty,
      );
    });

    test('catalogGroups：解析分组（含 provider_id / name 兜底 / 空组丢弃）', () {
      final response = ModelsResponse.fromJson({
        'groups': [
          {
            'provider_id': 'p1',
            'name': 'Provider One',
            'models': [
              {'id': 'm1', 'name': 'M1'},
            ],
            'extra_models': [
              {'id': 'x1'},
            ],
          },
          {
            'models': <Object?>[],
          },
          {
            'name': 'No Provider',
            'models': [
              {'id': 'm2', 'label': 'M2'},
            ],
          },
          'not-an-object',
        ],
      });

      final groups = response.catalogGroups;
      expect(groups, hasLength(2));
      expect(groups[0].id, 'p1');
      expect(groups[0].name, 'Provider One');
      expect(groups[0].providerID, 'p1');
      expect(groups[0].models.single.id, 'm1');
      expect(groups[0].extraModels.single.id, 'x1');
      // 无 provider_id 时 id = name-index（index 为原始数组下标 2）。
      expect(groups[1].id, 'No Provider-2');
      expect(groups[1].name, 'No Provider');
      expect(groups[1].providerID, isNull);
      expect(groups[1].models.single.displayName, 'M2');
      expect(groups[1].extraModels, isEmpty);
    });

    test('catalogGroups：groups 为 null / 空 → 空列表', () {
      expect(ModelsResponse.fromJson(const {}).catalogGroups, isEmpty);
      expect(
        ModelsResponse.fromJson(const {'groups': <Object?>[]}).catalogGroups,
        isEmpty,
      );
      expect(
        ModelsResponse.fromJson({'groups': 'bad'}).catalogGroups,
        isEmpty,
      );
    });

    test('== / hashCode / toString（阶梯式）', () {
      ModelsResponse build({
        List<Object?>? groups,
        List<Object?>? models,
        String? defaultModel,
        String? activeProvider,
      }) =>
          ModelsResponse.fromJson({
            'groups': groups,
            'models': models,
            'default_model': defaultModel,
            'active_provider': activeProvider,
          });

      final base = build(
        groups: [
          {'provider_id': 'p1'},
        ],
        models: ['m1'],
        defaultModel: 'gpt-5',
        activeProvider: 'p1',
      );
      expect(
        base,
        build(
          groups: [
            {'provider_id': 'p1'},
          ],
          models: ['m1'],
          defaultModel: 'gpt-5',
          activeProvider: 'p1',
        ),
      );
      expect(
        base.hashCode,
        build(
          groups: [
            {'provider_id': 'p1'},
          ],
          models: ['m1'],
          defaultModel: 'gpt-5',
          activeProvider: 'p1',
        ).hashCode,
      );
      expect(base.toString(), 'ModelsResponse(defaultModel: gpt-5)');
      expect(
        const ModelsResponse().toString(),
        'ModelsResponse(defaultModel: null)',
      );

      expect(
        base ==
            build(
              groups: [
                {'provider_id': 'p2'},
              ],
              models: ['m1'],
              defaultModel: 'gpt-5',
              activeProvider: 'p1',
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              groups: [
                {'provider_id': 'p1'},
              ],
              models: ['m2'],
              defaultModel: 'gpt-5',
              activeProvider: 'p1',
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              groups: [
                {'provider_id': 'p1'},
              ],
              models: ['m1'],
              defaultModel: 'gpt-6',
              activeProvider: 'p1',
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              groups: [
                {'provider_id': 'p1'},
              ],
              models: ['m1'],
              defaultModel: 'gpt-5',
              activeProvider: 'p2',
            ),
        isFalse,
      );
      expect(base == const ModelsResponse(), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  group('ModelsRefreshResponse', () {
    test('fromJson：ok 默认 false + provider', () {
      expect(ModelsRefreshResponse.fromJson(const {}).ok, false);
      expect(ModelsRefreshResponse.fromJson(const {}).provider, isNull);

      final ok = ModelsRefreshResponse.fromJson({
        'ok': true,
        'provider': 'p1',
      });
      expect(ok.ok, true);
      expect(ok.provider, 'p1');
    });

    test('fromJson：ok 宽容（int / 字符串 / 不可转换回落 false）', () {
      expect(ModelsRefreshResponse.fromJson({'ok': 1}).ok, true);
      expect(ModelsRefreshResponse.fromJson({'ok': 0}).ok, false);
      expect(ModelsRefreshResponse.fromJson({'ok': 'yes'}).ok, true);
      expect(ModelsRefreshResponse.fromJson({'ok': 'no'}).ok, false);
      expect(ModelsRefreshResponse.fromJson({'ok': 2}).ok, false);
      expect(ModelsRefreshResponse.fromJson({'ok': 'maybe'}).ok, false);
      expect(ModelsRefreshResponse.fromJson({'ok': [true]}).ok, false);
      expect(ModelsRefreshResponse.fromJson({'ok': null}).ok, false);
    });

    test('fromJson：provider 类型不符 / 无 camelCase 回退', () {
      expect(ModelsRefreshResponse.fromJson({'provider': 7}).provider, '7');
      expect(
        ModelsRefreshResponse.fromJson({'provider': [1]}).provider,
        isNull,
      );
      expect(
        ModelsRefreshResponse.fromJson({'activeProvider': 'p'}).provider,
        isNull,
      );
    });

    test('== / hashCode / toString（阶梯式）', () {
      ModelsRefreshResponse build({bool? ok, String? provider}) =>
          ModelsRefreshResponse.fromJson({'ok': ok, 'provider': provider});

      final base = build(ok: true, provider: 'p1');
      expect(base, build(ok: true, provider: 'p1'));
      expect(base.hashCode, build(ok: true, provider: 'p1').hashCode);
      expect(base.toString(), 'ModelsRefreshResponse(ok: true, provider: p1)');
      expect(
        const ModelsRefreshResponse().toString(),
        'ModelsRefreshResponse(ok: false, provider: null)',
      );

      expect(base == build(ok: false, provider: 'p1'), isFalse);
      expect(base == build(ok: true, provider: 'p2'), isFalse);
      expect(base == const ModelsRefreshResponse(), isFalse);
      expect(base == Object(), isFalse);
      expect(const ModelsRefreshResponse().ok, false);
    });
  });

  group('ProvidersResponse', () {
    test('fromJson：providers 嵌套列表 + activeProvider', () {
      final response = ProvidersResponse.fromJson({
        'providers': [
          {'id': 'p1', 'display_name': 'P1', 'has_key': true},
          {'id': 'p2'},
        ],
        'active_provider': 'p1',
      });
      expect(response.providers, hasLength(2));
      expect(response.providers!.first.id, 'p1');
      expect(response.providers!.first.displayName, 'P1');
      expect(response.providers!.first.hasKey, true);
      expect(response.activeProvider, 'p1');
    });

    test('fromJson：缺失 / null / 非 List / 元素非对象 → null', () {
      expect(ProvidersResponse.fromJson(const {}).providers, isNull);
      expect(ProvidersResponse.fromJson({'providers': null}).providers, isNull);
      expect(ProvidersResponse.fromJson({'providers': 'bad'}).providers, isNull);
      expect(ProvidersResponse.fromJson({'providers': 3}).providers, isNull);
      expect(
        ProvidersResponse.fromJson({
          'providers': {'id': 'p'},
        }).providers,
        isNull,
      );
      expect(
        ProvidersResponse.fromJson(const {'providers': [1]}).providers,
        isNull,
      );
      expect(
        ProvidersResponse.fromJson({
          'active_provider': [1],
        }).activeProvider,
        isNull,
      );
      expect(
        ProvidersResponse.fromJson(const {'providers': <Object?>[]}).providers,
        isEmpty,
      );
    });

    test('fromJson：无 camelCase 回退（activeProvider 不认）', () {
      expect(
        ProvidersResponse.fromJson({'activeProvider': 'p'}).activeProvider,
        isNull,
      );
    });

    test('== / hashCode / toString（阶梯式）', () {
      ProvidersResponse build(List<Object?>? providers, String? active) =>
          ProvidersResponse.fromJson({
            'providers': providers,
            'active_provider': active,
          });

      final base = build([
        {'id': 'p1'},
      ], 'p1');
      expect(base, build([
        {'id': 'p1'},
      ], 'p1'));
      expect(
        base.hashCode,
        build([
          {'id': 'p1'},
        ], 'p1').hashCode,
      );
      expect(base.toString(), 'ProvidersResponse(activeProvider: p1)');
      expect(
        const ProvidersResponse().toString(),
        'ProvidersResponse(activeProvider: null)',
      );

      expect(base == const ProvidersResponse(), isFalse);
      expect(const ProvidersResponse() == build(const <Object?>[], null),
          isFalse);
      expect(
        base ==
            build([
              {'id': 'p2'},
            ], 'p1'),
        isFalse,
      );
      expect(
        base ==
            build([
              {'id': 'p1'},
              {'id': 'p2'},
            ], 'p1'),
        isFalse,
      );
      expect(base == build([
        {'id': 'p1'},
      ], 'p2'), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  group('ProviderSummary', () {
    test('fromJson：13 字段正常解析 + models_total 宽容', () {
      final summary = ProviderSummary.fromJson({
        'id': 'p1',
        'display_name': 'Provider One',
        'has_key': true,
        'configurable': false,
        'is_self_hosted': true,
        'base_url': 'https://x',
        'is_plugin_provider': false,
        'is_oauth': true,
        'is_custom': false,
        'key_source': 'env',
        'auth_error': 'expired',
        'models': [
          {'id': 'm1', 'label': 'M1'},
          {'id': 'm2', 'label': 'M2'},
        ],
        'models_total': 3,
      });
      expect(summary.id, 'p1');
      expect(summary.displayName, 'Provider One');
      expect(summary.hasKey, true);
      expect(summary.configurable, false);
      expect(summary.isSelfHosted, true);
      expect(summary.baseUrl, 'https://x');
      expect(summary.isPluginProvider, false);
      expect(summary.isOauth, true);
      expect(summary.isCustom, false);
      expect(summary.keySource, 'env');
      expect(summary.authError, 'expired');
      expect(summary.models, hasLength(2));
      expect(summary.models!.first.label, 'M1');
      expect(summary.models!.last.id, 'm2');
      expect(summary.modelsTotal, 3);
    });

    test('fromJson：models_total 宽容与溢出', () {
      expect(ProviderSummary.fromJson({'models_total': 3.9}).modelsTotal, 3);
      expect(ProviderSummary.fromJson({'models_total': '7'}).modelsTotal, 7);
      expect(ProviderSummary.fromJson({'models_total': ' 8 '}).modelsTotal, 8);
      expect(ProviderSummary.fromJson({'models_total': 'x'}).modelsTotal, isNull);
      expect(ProviderSummary.fromJson({'models_total': true}).modelsTotal,
          isNull);
      expect(
        ProviderSummary.fromJson({'models_total': 1e30}).modelsTotal,
        isNull,
      );
    });

    test('fromJson：缺失 / null / 类型不符 → null', () {
      final empty = ProviderSummary.fromJson(const {});
      expect(empty.id, isNull);
      expect(empty.displayName, isNull);
      expect(empty.hasKey, isNull);
      expect(empty.configurable, isNull);
      expect(empty.isSelfHosted, isNull);
      expect(empty.baseUrl, isNull);
      expect(empty.isPluginProvider, isNull);
      expect(empty.isOauth, isNull);
      expect(empty.isCustom, isNull);
      expect(empty.keySource, isNull);
      expect(empty.authError, isNull);
      expect(empty.models, isNull);
      expect(empty.modelsTotal, isNull);

      final wrong = ProviderSummary.fromJson({
        'id': [1],
        'display_name': {'a': 1},
        'has_key': 2,
        'configurable': 'maybe',
        'is_self_hosted': 3,
        'base_url': <Object?>[],
        'is_plugin_provider': 'nope',
        'is_oauth': -1,
        'is_custom': 5,
        'key_source': [1],
        'auth_error': {'a': 1},
        'models': 'bad',
        'models_total': 'x',
      });
      expect(wrong.id, isNull);
      expect(wrong.displayName, isNull);
      expect(wrong.hasKey, isNull);
      expect(wrong.configurable, isNull);
      expect(wrong.isSelfHosted, isNull);
      expect(wrong.baseUrl, isNull);
      expect(wrong.isPluginProvider, isNull);
      expect(wrong.isOauth, isNull);
      expect(wrong.isCustom, isNull);
      expect(wrong.keySource, isNull);
      expect(wrong.authError, isNull);
      expect(wrong.models, isNull);
      expect(wrong.modelsTotal, isNull);
    });

    test('fromJson：models 元素键类型不符 / 元素非 Map → 整数组 null', () {
      expect(
        ProviderSummary.fromJson({
          'models': [
            {1: 'bad-key'},
          ],
        }).models,
        isNull,
      );
      // 裸字符串元素不走 ProviderModel 的字符串容错（那只是单模型入口的兜底）。
      expect(
        ProviderSummary.fromJson(const {
          'models': <Object?>['m1'],
        }).models,
        isNull,
      );
      expect(
        ProviderSummary.fromJson({
          'models': [
            {'id': 'm1'},
            'm2',
          ],
        }).models,
        isNull,
      );
      expect(
        ProviderSummary.fromJson(const {'models': <Object?>[]}).models,
        isEmpty,
      );
    });

    test('== / hashCode / toString（13 字段逐个阶梯）', () {
      ProviderSummary build(Map<String, Object?> overrides) =>
          ProviderSummary.fromJson({
            'id': 'p1',
            'display_name': 'P1',
            'has_key': true,
            'configurable': true,
            'is_self_hosted': false,
            'base_url': 'u1',
            'is_plugin_provider': false,
            'is_oauth': false,
            'is_custom': false,
            'key_source': 'ks',
            'auth_error': 'ae',
            'models': [
              {'id': 'm1'},
            ],
            'models_total': 1,
            ...overrides,
          });

      final base = build(const {});
      expect(base, build(const {}));
      expect(base.hashCode, build(const {}).hashCode);
      expect(base.toString(), 'ProviderSummary(id: p1, displayName: P1)');
      expect(
        const ProviderSummary().toString(),
        'ProviderSummary(id: null, displayName: null)',
      );

      const diffs = <Map<String, Object?>>[
        {'id': 'p2'},
        {'display_name': 'P2'},
        {'has_key': false},
        {'configurable': false},
        {'is_self_hosted': true},
        {'base_url': 'u2'},
        {'is_plugin_provider': true},
        {'is_oauth': true},
        {'is_custom': true},
        {'key_source': 'ks2'},
        {'auth_error': 'ae2'},
        {
          'models': [
            {'id': 'm2'},
          ],
        },
        {'models_total': 2},
      ];
      for (final diff in diffs) {
        expect(base == build(diff), isFalse, reason: '$diff');
      }
      // models 的 null / 空 / 等值三个分支。
      expect(base == build(const {'models': null}), isFalse);
      expect(base == build(const {'models': <Object?>[]}), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  group('ProviderModel', () {
    test('fromJson：裸字符串 → id = label = 该字符串', () {
      final model = ProviderModel.fromJson('gpt-5');
      expect(model.id, 'gpt-5');
      expect(model.label, 'gpt-5');
    });

    test('fromJson：对象 → id / label', () {
      final model = ProviderModel.fromJson({'id': 'm1', 'label': 'M1'});
      expect(model.id, 'm1');
      expect(model.label, 'M1');

      final partial = ProviderModel.fromJson({'label': 'only-label'});
      expect(partial.id, isNull);
      expect(partial.label, 'only-label');
    });

    test('fromJson：非 Map / 非 String → 全空实例', () {
      expect(ProviderModel.fromJson(42).id, isNull);
      expect(ProviderModel.fromJson(42.5).label, isNull);
      expect(ProviderModel.fromJson(true).id, isNull);
      expect(ProviderModel.fromJson(null).id, isNull);
      expect(ProviderModel.fromJson(const [1, 2]).id, isNull);
      expect(ProviderModel.fromJson(const <String, Object?>{}).id, isNull);
      expect(ProviderModel.fromJson(42), const ProviderModel());
    });

    test('fromJson：对象内字段类型不符 → null / 宽容转换', () {
      final coerced = ProviderModel.fromJson({'id': 7, 'label': true});
      expect(coerced.id, '7');
      expect(coerced.label, 'true');

      final wrong = ProviderModel.fromJson({
        'id': [1],
        'label': {'a': 1},
      });
      expect(wrong.id, isNull);
      expect(wrong.label, isNull);
    });

    test('== / hashCode / toString（阶梯式）', () {
      ProviderModel build(Object? raw) => ProviderModel.fromJson(raw);

      final base = build('m1');
      expect(base, build('m1'));
      expect(base.hashCode, build('m1').hashCode);
      expect(base.toString(), 'ProviderModel(id: m1, label: m1)');
      expect(
        const ProviderModel().toString(),
        'ProviderModel(id: null, label: null)',
      );

      expect(base == build('m2'), isFalse);
      expect(base == build({'id': 'm1', 'label': 'other'}), isFalse);
      expect(base == const ProviderModel(), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  group('DefaultModelResponse', () {
    test('fromJson：ok / model 正常 + 宽容', () {
      final response = DefaultModelResponse.fromJson({
        'ok': true,
        'model': 'gpt-5',
      });
      expect(response.ok, true);
      expect(response.model, 'gpt-5');

      final coerced = DefaultModelResponse.fromJson({'ok': 1, 'model': 5});
      expect(coerced.ok, true);
      expect(coerced.model, '5');
    });

    test('fromJson：缺失 / null / 类型不符 → null', () {
      final empty = DefaultModelResponse.fromJson(const {});
      expect(empty.ok, isNull);
      expect(empty.model, isNull);

      final wrong = DefaultModelResponse.fromJson({
        'ok': 4,
        'model': [1],
      });
      expect(wrong.ok, isNull);
      expect(wrong.model, isNull);

      final nulls = DefaultModelResponse.fromJson({
        'ok': null,
        'model': null,
      });
      expect(nulls.ok, isNull);
      expect(nulls.model, isNull);
    });

    test('fromJson：无 camelCase 回退（defaultModel / modelId 不认）', () {
      expect(
        DefaultModelResponse.fromJson({'defaultModel': 'x'}).model,
        isNull,
      );
      expect(DefaultModelResponse.fromJson({'modelId': 'x'}).model, isNull);
    });

    test('== / hashCode / toString（阶梯式）', () {
      DefaultModelResponse build({bool? ok, String? model}) =>
          DefaultModelResponse.fromJson({'ok': ok, 'model': model});

      final base = build(ok: true, model: 'm1');
      expect(base, build(ok: true, model: 'm1'));
      expect(base.hashCode, build(ok: true, model: 'm1').hashCode);
      expect(base.toString(), 'DefaultModelResponse(ok: true, model: m1)');
      expect(
        const DefaultModelResponse().toString(),
        'DefaultModelResponse(ok: null, model: null)',
      );

      expect(base == build(ok: false, model: 'm1'), isFalse);
      expect(base == build(ok: true, model: 'm2'), isFalse);
      expect(base == const DefaultModelResponse(), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  group('ModelsLiveResponse', () {
    test('fromJson：provider / models / count', () {
      final response = ModelsLiveResponse.fromJson({
        'provider': 'p1',
        'models': [
          {'id': 'm1', 'name': 'M1'},
        ],
        'count': 1,
      });
      expect(response.provider, 'p1');
      expect(response.models, hasLength(1));
      expect(response.count, 1);
    });

    test('fromJson：缺失 / null / 类型不符', () {
      final empty = ModelsLiveResponse.fromJson(const {});
      expect(empty.provider, isNull);
      expect(empty.models, isNull);
      expect(empty.count, isNull);

      final wrong = ModelsLiveResponse.fromJson({
        'provider': [1],
        'models': 'bad',
        'count': 'x',
      });
      expect(wrong.provider, isNull);
      expect(wrong.models, isNull);
      expect(wrong.count, isNull);

      expect(ModelsLiveResponse.fromJson({'count': 2.7}).count, 2);
    });

    test('normalizedProvider：trim / 空白视为缺失', () {
      expect(ModelsLiveResponse.fromJson(const {}).normalizedProvider, isNull);
      expect(
        ModelsLiveResponse.fromJson({'provider': null}).normalizedProvider,
        isNull,
      );
      expect(
        ModelsLiveResponse.fromJson({'provider': ''}).normalizedProvider,
        isNull,
      );
      expect(
        ModelsLiveResponse.fromJson({'provider': '   '}).normalizedProvider,
        isNull,
      );
      expect(
        ModelsLiveResponse.fromJson({'provider': ' p1 '}).normalizedProvider,
        'p1',
      );
    });

    test('liveOptions：fallbackProvider 用归一化 provider', () {
      final live = ModelsLiveResponse.fromJson({
        'provider': ' p1 ',
        'models': [
          {'id': 'm1', 'name': 'M1'},
          {'id': 'm2'},
          {'id': 'm3', 'provider_id': ' px '},
          'not-an-object',
          {'name': 'no-id'},
        ],
      });
      final options = live.liveOptions;
      expect(options, hasLength(3));
      expect(options[0].id, 'm1');
      expect(options[0].displayName, 'M1');
      expect(options[0].providerID, 'p1');
      expect(options[1].displayName, 'm2');
      expect(options[1].providerID, 'p1');
      expect(options[2].providerID, 'px');
    });

    test('liveOptions：models 缺失 / 空 / 非 List → 空列表', () {
      expect(ModelsLiveResponse.fromJson(const {}).liveOptions, isEmpty);
      expect(
        ModelsLiveResponse.fromJson(const {'models': <Object?>[]}).liveOptions,
        isEmpty,
      );
      expect(
        ModelsLiveResponse.fromJson({'models': 'bad'}).liveOptions,
        isEmpty,
      );
      // provider 缺失时 providerID 为 null。
      final live = ModelsLiveResponse.fromJson({
        'models': [
          {'id': 'm1'},
        ],
      });
      expect(live.liveOptions.single.providerID, isNull);
    });

    test('== / hashCode / toString（阶梯式）', () {
      ModelsLiveResponse build({
        String? provider,
        List<Object?>? models,
        int? count,
      }) =>
          ModelsLiveResponse.fromJson({
            'provider': provider,
            'models': models,
            'count': count,
          });

      final base = build(
        provider: 'p1',
        models: [
          {'id': 'm1'},
        ],
        count: 1,
      );
      expect(
        base,
        build(
          provider: 'p1',
          models: [
            {'id': 'm1'},
          ],
          count: 1,
        ),
      );
      expect(
        base.hashCode,
        build(
          provider: 'p1',
          models: [
            {'id': 'm1'},
          ],
          count: 1,
        ).hashCode,
      );
      expect(base.toString(), 'ModelsLiveResponse(provider: p1, count: 1)');
      expect(
        const ModelsLiveResponse().toString(),
        'ModelsLiveResponse(provider: null, count: null)',
      );

      expect(
        base ==
            build(
              provider: 'p2',
              models: [
                {'id': 'm1'},
              ],
              count: 1,
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              provider: 'p1',
              models: [
                {'id': 'm2'},
              ],
              count: 1,
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              provider: 'p1',
              models: [
                {'id': 'm1'},
              ],
              count: 2,
            ),
        isFalse,
      );
      expect(base == const ModelsLiveResponse(), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  // ==========================================================================
  // 设置 / 更新
  // ==========================================================================
  group('SettingsResponse', () {
    test('fromJson：13 字段正常解析', () {
      final settings = SettingsResponse.fromJson({
        'bot_name': '柚子',
        'webui_version': '0.9.0',
        'agent_version': '1.0.0',
        'theme': 'dark',
        'check_for_updates': true,
        'show_cli_sessions': false,
        'show_claude_code_sessions': true,
        'max_tokens': 4096,
        'max_tokens_effective': 8192,
        'auth_enabled': true,
        'password_auth_enabled': false,
        'passkeys_enabled': true,
        'passwordless_enabled': false,
      });
      expect(settings.botName, '柚子');
      expect(settings.webuiVersion, '0.9.0');
      expect(settings.agentVersion, '1.0.0');
      expect(settings.theme, 'dark');
      expect(settings.checkForUpdates, true);
      expect(settings.showCliSessions, false);
      expect(settings.showClaudeCodeSessions, true);
      expect(settings.maxTokens, 4096);
      expect(settings.maxTokensEffective, 8192);
      expect(settings.authEnabled, true);
      expect(settings.passwordAuthEnabled, false);
      expect(settings.passkeysEnabled, true);
      expect(settings.passwordlessEnabled, false);
    });

    test('fromJson：缺失 / null / 类型不符 → null', () {
      final empty = SettingsResponse.fromJson(const {});
      expect(empty.botName, isNull);
      expect(empty.webuiVersion, isNull);
      expect(empty.agentVersion, isNull);
      expect(empty.theme, isNull);
      expect(empty.checkForUpdates, isNull);
      expect(empty.showCliSessions, isNull);
      expect(empty.showClaudeCodeSessions, isNull);
      expect(empty.maxTokens, isNull);
      expect(empty.maxTokensEffective, isNull);
      expect(empty.authEnabled, isNull);
      expect(empty.passwordAuthEnabled, isNull);
      expect(empty.passkeysEnabled, isNull);
      expect(empty.passwordlessEnabled, isNull);

      final wrong = SettingsResponse.fromJson({
        'bot_name': [1],
        'theme': 1,
        'check_for_updates': 2,
        'show_cli_sessions': 'maybe',
        'show_claude_code_sessions': 3,
        'max_tokens': 'x',
        'max_tokens_effective': true,
        'auth_enabled': 4,
        'password_auth_enabled': [true],
        'passkeys_enabled': 'nope',
        'passwordless_enabled': {'a': 1},
      });
      expect(wrong.botName, isNull);
      // lossyString 宽容：int → '1'。
      expect(wrong.theme, '1');
      expect(wrong.checkForUpdates, isNull);
      expect(wrong.showCliSessions, isNull);
      expect(wrong.showClaudeCodeSessions, isNull);
      expect(wrong.maxTokens, isNull);
      expect(wrong.maxTokensEffective, isNull);
      expect(wrong.authEnabled, isNull);
      expect(wrong.passwordAuthEnabled, isNull);
      expect(wrong.passkeysEnabled, isNull);
      expect(wrong.passwordlessEnabled, isNull);
    });

    test('fromJson：max_tokens 宽容（double 截断 / 字符串）', () {
      expect(SettingsResponse.fromJson({'max_tokens': 4096.8}).maxTokens, 4096);
      expect(SettingsResponse.fromJson({'max_tokens': '4096'}).maxTokens, 4096);
      expect(
        SettingsResponse.fromJson({'max_tokens': ' 2048 '}).maxTokens,
        2048,
      );
    });

    test('fromJson：无 camelCase 回退（botName / maxTokens 不认）', () {
      final camel = SettingsResponse.fromJson({
        'botName': 'x',
        'maxTokens': 1,
        'authEnabled': true,
      });
      expect(camel.botName, isNull);
      expect(camel.maxTokens, isNull);
      expect(camel.authEnabled, isNull);
    });

    test('== / hashCode / toString（13 字段逐个阶梯）', () {
      SettingsResponse build(Map<String, Object?> overrides) =>
          SettingsResponse.fromJson({
            'bot_name': 'b',
            'webui_version': 'w',
            'agent_version': 'a',
            'theme': 't',
            'check_for_updates': true,
            'show_cli_sessions': true,
            'show_claude_code_sessions': true,
            'max_tokens': 1,
            'max_tokens_effective': 2,
            'auth_enabled': true,
            'password_auth_enabled': true,
            'passkeys_enabled': true,
            'passwordless_enabled': true,
            ...overrides,
          });

      final base = build(const {});
      expect(base, build(const {}));
      expect(base.hashCode, build(const {}).hashCode);
      expect(base.toString(), 'SettingsResponse(botName: b)');
      expect(
        const SettingsResponse().toString(),
        'SettingsResponse(botName: null)',
      );

      const diffs = <Map<String, Object?>>[
        {'bot_name': 'b2'},
        {'webui_version': 'w2'},
        {'agent_version': 'a2'},
        {'theme': 't2'},
        {'check_for_updates': false},
        {'show_cli_sessions': false},
        {'show_claude_code_sessions': false},
        {'max_tokens': 9},
        {'max_tokens_effective': 9},
        {'auth_enabled': false},
        {'password_auth_enabled': false},
        {'passkeys_enabled': false},
        {'passwordless_enabled': false},
      ];
      for (final diff in diffs) {
        expect(base == build(diff), isFalse, reason: '$diff');
      }
      expect(base == const SettingsResponse(), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  group('UpdatesCheckResponse', () {
    test('fromJson：webui / agent 嵌套 + checkedAt 宽容', () {
      final response = UpdatesCheckResponse.fromJson({
        'webui': {'name': 'webui', 'behind': 2},
        'agent': {'name': 'agent'},
        'checked_at': 1723700000,
        'disabled': true,
      });
      expect(response.webui, isNotNull);
      expect(response.webui!.name, 'webui');
      expect(response.webui!.behind, 2);
      expect(response.agent!.name, 'agent');
      expect(response.checkedAt, 1723700000.0);
      expect(response.disabled, true);
    });

    test('fromJson：checkedAt 宽容与不可转换', () {
      expect(
        UpdatesCheckResponse.fromJson({'checked_at': ' 2.5 '}).checkedAt,
        2.5,
      );
      expect(UpdatesCheckResponse.fromJson({'checked_at': '3'}).checkedAt, 3.0);
      expect(
        UpdatesCheckResponse.fromJson({'checked_at': 'abc'}).checkedAt,
        isNull,
      );
      expect(
        UpdatesCheckResponse.fromJson({'checked_at': true}).checkedAt,
        isNull,
      );
      expect(
        UpdatesCheckResponse.fromJson({'checked_at': [1]}).checkedAt,
        isNull,
      );
    });

    test('fromJson：嵌套非 Map 保持 null / 空对象仍是合法实例', () {
      expect(UpdatesCheckResponse.fromJson(const {}).webui, isNull);
      expect(UpdatesCheckResponse.fromJson({'webui': 'bad'}).webui, isNull);
      expect(UpdatesCheckResponse.fromJson({'webui': 1}).webui, isNull);
      expect(
        UpdatesCheckResponse.fromJson(const {'webui': <Object?>[]}).webui,
        isNull,
      );
      final emptyTarget = UpdatesCheckResponse.fromJson(const {
        'agent': <String, Object?>{},
      }).agent;
      expect(emptyTarget, isNotNull);
      expect(emptyTarget!.name, isNull);
      expect(emptyTarget.behind, isNull);
    });

    test('== / hashCode / toString（阶梯式）', () {
      UpdatesCheckResponse build({
        Map<String, Object?>? webui,
        Map<String, Object?>? agent,
        double? checkedAt,
        bool? disabled,
      }) =>
          UpdatesCheckResponse.fromJson({
            'webui': webui,
            'agent': agent,
            'checked_at': checkedAt,
            'disabled': disabled,
          });

      final base = build(
        webui: {'name': 'w'},
        agent: {'name': 'a'},
        checkedAt: 1,
        disabled: false,
      );
      expect(
        base,
        build(
          webui: {'name': 'w'},
          agent: {'name': 'a'},
          checkedAt: 1,
          disabled: false,
        ),
      );
      expect(
        base.hashCode,
        build(
          webui: {'name': 'w'},
          agent: {'name': 'a'},
          checkedAt: 1,
          disabled: false,
        ).hashCode,
      );
      expect(base.toString(), 'UpdatesCheckResponse(disabled: false)');
      expect(
        const UpdatesCheckResponse().toString(),
        'UpdatesCheckResponse(disabled: null)',
      );

      expect(
        base ==
            build(
              webui: {'name': 'w2'},
              agent: {'name': 'a'},
              checkedAt: 1,
              disabled: false,
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              webui: {'name': 'w'},
              agent: {'name': 'a2'},
              checkedAt: 1,
              disabled: false,
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              webui: {'name': 'w'},
              agent: {'name': 'a'},
              checkedAt: 2,
              disabled: false,
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              webui: {'name': 'w'},
              agent: {'name': 'a'},
              checkedAt: 1,
              disabled: true,
            ),
        isFalse,
      );
      expect(base == const UpdatesCheckResponse(), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  group('UpdateTargetInfo', () {
    test('fromJson：9 字段正常解析 + behind 宽容', () {
      final info = UpdateTargetInfo.fromJson({
        'name': 'webui',
        'behind': 3,
        'current_sha': 'abc',
        'latest_sha': 'def',
        'branch': 'main',
        'repo_url': 'https://repo',
        'compare_url': 'https://compare',
        'error': null,
        'stale_check': true,
      });
      expect(info.name, 'webui');
      expect(info.behind, 3);
      expect(info.currentSha, 'abc');
      expect(info.latestSha, 'def');
      expect(info.branch, 'main');
      expect(info.repoUrl, 'https://repo');
      expect(info.compareUrl, 'https://compare');
      expect(info.error, isNull);
      expect(info.staleCheck, true);

      expect(UpdateTargetInfo.fromJson({'behind': 3.9}).behind, 3);
      expect(UpdateTargetInfo.fromJson({'behind': '4'}).behind, 4);
      expect(UpdateTargetInfo.fromJson({'behind': 'x'}).behind, isNull);
    });

    test('fromJson：缺失 / null / 类型不符 → null', () {
      final empty = UpdateTargetInfo.fromJson(const {});
      expect(empty.name, isNull);
      expect(empty.behind, isNull);
      expect(empty.currentSha, isNull);
      expect(empty.latestSha, isNull);
      expect(empty.branch, isNull);
      expect(empty.repoUrl, isNull);
      expect(empty.compareUrl, isNull);
      expect(empty.error, isNull);
      expect(empty.staleCheck, isNull);

      final wrong = UpdateTargetInfo.fromJson({
        'name': [1],
        'behind': 'x',
        'current_sha': 1,
        'latest_sha': <Object?>[],
        'branch': {'a': 1},
        'repo_url': 2.5,
        'compare_url': true,
        'error': [1],
        'stale_check': 2,
      });
      expect(wrong.name, isNull);
      expect(wrong.behind, isNull);
      // lossyString 宽容：int → '1'，double → '2.5'，bool → 'true'。
      expect(wrong.currentSha, '1');
      expect(wrong.latestSha, isNull);
      expect(wrong.branch, isNull);
      expect(wrong.repoUrl, '2.5');
      expect(wrong.compareUrl, 'true');
      expect(wrong.error, isNull);
      expect(wrong.staleCheck, isNull);
    });

    test('fromJson：无 camelCase 回退（currentSha / staleCheck 不认）', () {
      final camel = UpdateTargetInfo.fromJson({
        'currentSha': 'a',
        'latestSha': 'b',
        'compareUrl': 'c',
        'staleCheck': true,
      });
      expect(camel.currentSha, isNull);
      expect(camel.latestSha, isNull);
      expect(camel.compareUrl, isNull);
      expect(camel.staleCheck, isNull);
    });

    test('== / hashCode / toString（9 字段逐个阶梯）', () {
      UpdateTargetInfo build(Map<String, Object?> overrides) =>
          UpdateTargetInfo.fromJson({
            'name': 'n',
            'behind': 1,
            'current_sha': 'c',
            'latest_sha': 'l',
            'branch': 'b',
            'repo_url': 'r',
            'compare_url': 'cp',
            'error': 'e',
            'stale_check': false,
            ...overrides,
          });

      final base = build(const {});
      expect(base, build(const {}));
      expect(base.hashCode, build(const {}).hashCode);
      expect(base.toString(), 'UpdateTargetInfo(name: n, behind: 1)');
      expect(
        const UpdateTargetInfo().toString(),
        'UpdateTargetInfo(name: null, behind: null)',
      );

      const diffs = <Map<String, Object?>>[
        {'name': 'n2'},
        {'behind': 2},
        {'current_sha': 'c2'},
        {'latest_sha': 'l2'},
        {'branch': 'b2'},
        {'repo_url': 'r2'},
        {'compare_url': 'cp2'},
        {'error': 'e2'},
        {'stale_check': true},
      ];
      for (final diff in diffs) {
        expect(base == build(diff), isFalse, reason: '$diff');
      }
      expect(base == const UpdateTargetInfo(), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  group('UpdatesApplyResponse / UpdatesApplyOutcome', () {
    test('fromJson：10 字段正常解析', () {
      final response = UpdatesApplyResponse.fromJson({
        'ok': true,
        'message': 'applying',
        'target': 'webui',
        'conflict': false,
        'diverged': false,
        'restart_blocked': false,
        'restart_scheduled': true,
        'stash_conflict': false,
        'active_streams': 1,
        'active_runs': 2,
      });
      expect(response.ok, true);
      expect(response.message, 'applying');
      expect(response.target, 'webui');
      expect(response.conflict, false);
      expect(response.diverged, false);
      expect(response.restartBlocked, false);
      expect(response.restartScheduled, true);
      expect(response.stashConflict, false);
      expect(response.activeStreams, 1);
      expect(response.activeRuns, 2);
    });

    test('outcome：restartBlocked 优先于 ok，其余回落 failed', () {
      // 三态各成一例。
      expect(
        UpdatesApplyResponse.fromJson(const {'ok': true}).outcome,
        UpdatesApplyOutcome.applying,
      );
      expect(
        UpdatesApplyResponse.fromJson(const {'ok': true, 'restart_blocked': true})
            .outcome,
        UpdatesApplyOutcome.restartBlocked,
      );
      expect(
        UpdatesApplyResponse.fromJson(const {}).outcome,
        UpdatesApplyOutcome.failed,
      );
      expect(
        UpdatesApplyResponse.fromJson(const {'ok': false}).outcome,
        UpdatesApplyOutcome.failed,
      );
    });

    test('枚举：全部取值 + 未知值不会被产出（兜底到 failed）', () {
      expect(UpdatesApplyOutcome.values, hasLength(3));
      expect(UpdatesApplyOutcome.values, [
        UpdatesApplyOutcome.applying,
        UpdatesApplyOutcome.restartBlocked,
        UpdatesApplyOutcome.failed,
      ]);
      expect(UpdatesApplyOutcome.applying.name, 'applying');
      expect(UpdatesApplyOutcome.restartBlocked.index, 1);
      expect(UpdatesApplyOutcome.failed.toString(),
          'UpdatesApplyOutcome.failed');
      // 未知态（既非 ok 也非 restart_blocked，例如服务端返回字符串枚举）
      // 在 Dart 侧不存在对应常量 → outcome 兜底 failed。
      final unknown = UpdatesApplyResponse.fromJson({
        'ok': 'unknown-state',
        'restart_blocked': 'unknown-state',
      });
      expect(unknown.ok, isNull);
      expect(unknown.restartBlocked, isNull);
      expect(unknown.outcome, UpdatesApplyOutcome.failed);
    });

    test('fromJson：缺失 / null / 类型不符 → null', () {
      final empty = UpdatesApplyResponse.fromJson(const {});
      expect(empty.ok, isNull);
      expect(empty.message, isNull);
      expect(empty.target, isNull);
      expect(empty.conflict, isNull);
      expect(empty.diverged, isNull);
      expect(empty.restartBlocked, isNull);
      expect(empty.restartScheduled, isNull);
      expect(empty.stashConflict, isNull);
      expect(empty.activeStreams, isNull);
      expect(empty.activeRuns, isNull);

      final wrong = UpdatesApplyResponse.fromJson({
        'ok': 2,
        'message': [1],
        'target': {'a': 1},
        'conflict': 'maybe',
        'diverged': 3,
        'restart_blocked': 'nope',
        'restart_scheduled': 4,
        'stash_conflict': [true],
        'active_streams': 'x',
        'active_runs': true,
      });
      expect(wrong.ok, isNull);
      expect(wrong.message, isNull);
      expect(wrong.target, isNull);
      expect(wrong.conflict, isNull);
      expect(wrong.diverged, isNull);
      expect(wrong.restartBlocked, isNull);
      expect(wrong.restartScheduled, isNull);
      expect(wrong.stashConflict, isNull);
      expect(wrong.activeStreams, isNull);
      expect(wrong.activeRuns, isNull);
      expect(wrong.outcome, UpdatesApplyOutcome.failed);
    });

    test('fromJson：active_streams 宽容（double 截断 / 字符串）', () {
      expect(
        UpdatesApplyResponse.fromJson({'active_streams': 2.9}).activeStreams,
        2,
      );
      expect(
        UpdatesApplyResponse.fromJson({'active_streams': '5'}).activeStreams,
        5,
      );
    });

    test('fromJson：无 camelCase 回退（restartBlocked / activeStreams 不认）', () {
      final camel = UpdatesApplyResponse.fromJson({
        'restartBlocked': true,
        'restartScheduled': true,
        'stashConflict': true,
        'activeStreams': 1,
        'activeRuns': 1,
      });
      expect(camel.restartBlocked, isNull);
      expect(camel.restartScheduled, isNull);
      expect(camel.stashConflict, isNull);
      expect(camel.activeStreams, isNull);
      expect(camel.activeRuns, isNull);
      expect(camel.outcome, UpdatesApplyOutcome.failed);
    });

    test('== / hashCode / toString（10 字段逐个阶梯）', () {
      UpdatesApplyResponse build(Map<String, Object?> overrides) =>
          UpdatesApplyResponse.fromJson({
            'ok': true,
            'message': 'm',
            'target': 't',
            'conflict': false,
            'diverged': false,
            'restart_blocked': false,
            'restart_scheduled': false,
            'stash_conflict': false,
            'active_streams': 1,
            'active_runs': 1,
            ...overrides,
          });

      final base = build(const {});
      expect(base, build(const {}));
      expect(base.hashCode, build(const {}).hashCode);
      expect(base.toString(), 'UpdatesApplyResponse(ok: true)');
      expect(
        const UpdatesApplyResponse().toString(),
        'UpdatesApplyResponse(ok: null)',
      );

      const diffs = <Map<String, Object?>>[
        {'ok': false},
        {'message': 'm2'},
        {'target': 't2'},
        {'conflict': true},
        {'diverged': true},
        {'restart_blocked': true},
        {'restart_scheduled': true},
        {'stash_conflict': true},
        {'active_streams': 2},
        {'active_runs': 2},
      ];
      for (final diff in diffs) {
        expect(base == build(diff), isFalse, reason: '$diff');
      }
      expect(base == const UpdatesApplyResponse(), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  // ==========================================================================
  // 推理 / 人格 / 档案
  // ==========================================================================
  group('ReasoningStatusResponse', () {
    test('fromJson：7 字段正常解析', () {
      final response = ReasoningStatusResponse.fromJson({
        'ok': true,
        'show_reasoning': false,
        'reasoning_effort': 'high',
        'effort': 'low',
        'supported_efforts': ['low', 'high'],
        'supports_reasoning_effort': true,
        'error': null,
      });
      expect(response.ok, true);
      expect(response.showReasoning, false);
      expect(response.reasoningEffort, 'high');
      expect(response.effort, 'low');
      expect(response.supportedEfforts, ['low', 'high']);
      expect(response.supportsReasoningEffort, true);
      expect(response.error, isNull);
    });

    test('fromJson：缺失 / null / 类型不符 → null', () {
      final empty = ReasoningStatusResponse.fromJson(const {});
      expect(empty.ok, isNull);
      expect(empty.showReasoning, isNull);
      expect(empty.reasoningEffort, isNull);
      expect(empty.effort, isNull);
      expect(empty.supportedEfforts, isNull);
      expect(empty.supportsReasoningEffort, isNull);
      expect(empty.error, isNull);

      final wrong = ReasoningStatusResponse.fromJson({
        'ok': 2,
        'show_reasoning': 'maybe',
        'reasoning_effort': [1],
        'effort': {'a': 1},
        'supported_efforts': 'bad',
        'supports_reasoning_effort': 3,
        'error': [1],
      });
      expect(wrong.ok, isNull);
      expect(wrong.showReasoning, isNull);
      expect(wrong.reasoningEffort, isNull);
      expect(wrong.effort, isNull);
      expect(wrong.supportedEfforts, isNull);
      expect(wrong.supportsReasoningEffort, isNull);
      expect(wrong.error, isNull);
    });

    test('fromJson：supported_efforts 混合元素 → null，空数组 → 空', () {
      expect(
        ReasoningStatusResponse.fromJson(const {
          'supported_efforts': <Object?>['a', 1],
        }).supportedEfforts,
        isNull,
      );
      expect(
        ReasoningStatusResponse.fromJson(const {
          'supported_efforts': <Object?>[],
        }).supportedEfforts,
        isEmpty,
      );
    });

    test('effectiveEffort：reasoningEffort 优先，回落 effort', () {
      expect(
        ReasoningStatusResponse.fromJson(const {
          'reasoning_effort': 'high',
          'effort': 'low',
        }).effectiveEffort,
        'high',
      );
      expect(
        ReasoningStatusResponse.fromJson(const {'effort': 'low'})
            .effectiveEffort,
        'low',
      );
      expect(
        ReasoningStatusResponse.fromJson(const {}).effectiveEffort,
        isNull,
      );
    });

    test('normalizedSupportedEfforts：trim + lowercase + 去重保序 + 去空', () {
      final response = ReasoningStatusResponse.fromJson({
        'supported_efforts': [' High ', 'high', '   ', 'LOW', 'medium', ''],
      });
      expect(response.normalizedSupportedEfforts, ['high', 'low', 'medium']);

      expect(
        ReasoningStatusResponse.fromJson(const {}).normalizedSupportedEfforts,
        isEmpty,
      );
      expect(
        ReasoningStatusResponse.fromJson(const {
          'supported_efforts': <Object?>[],
        }).normalizedSupportedEfforts,
        isEmpty,
      );
    });

    test('== / hashCode / toString（含 _listEquals 全分支）', () {
      ReasoningStatusResponse build({
        bool? ok,
        bool? showReasoning,
        String? reasoningEffort,
        String? effort,
        List<Object?>? supportedEfforts,
        bool? supportsReasoningEffort,
        String? error,
      }) =>
          ReasoningStatusResponse.fromJson({
            'ok': ok,
            'show_reasoning': showReasoning,
            'reasoning_effort': reasoningEffort,
            'effort': effort,
            'supported_efforts': supportedEfforts,
            'supports_reasoning_effort': supportsReasoningEffort,
            'error': error,
          });

      final base = build(
        ok: true,
        showReasoning: true,
        reasoningEffort: 'high',
        effort: 'low',
        supportedEfforts: ['high'],
        supportsReasoningEffort: true,
        error: 'e',
      );
      expect(
        base,
        build(
          ok: true,
          showReasoning: true,
          reasoningEffort: 'high',
          effort: 'low',
          supportedEfforts: ['high'],
          supportsReasoningEffort: true,
          error: 'e',
        ),
      );
      expect(
        base.hashCode,
        build(
          ok: true,
          showReasoning: true,
          reasoningEffort: 'high',
          effort: 'low',
          supportedEfforts: ['high'],
          supportsReasoningEffort: true,
          error: 'e',
        ).hashCode,
      );
      expect(base.toString(), 'ReasoningStatusResponse(ok: true)');
      expect(
        const ReasoningStatusResponse().toString(),
        'ReasoningStatusResponse(ok: null)',
      );
      // 自身比较 → _listEquals 的 identical 分支。
      expect(base == base, isTrue);

      expect(base == build(ok: false), isFalse);
      expect(base == build(showReasoning: false), isFalse);
      expect(base == build(reasoningEffort: 'low'), isFalse);
      expect(base == build(effort: 'high'), isFalse);
      expect(base == build(supportedEfforts: ['low']), isFalse);
      expect(base == build(supportsReasoningEffort: false), isFalse);
      expect(base == build(error: 'e2'), isFalse);
      // supportedEfforts：null vs 空 / 长度不同 / 元素不同。
      expect(base == build(supportedEfforts: null), isFalse);
      expect(
        build(supportedEfforts: null) == build(supportedEfforts: const []),
        isFalse,
      );
      expect(
        build(supportedEfforts: ['a']) == build(supportedEfforts: ['a', 'b']),
        isFalse,
      );
      expect(
        build(supportedEfforts: ['a']) == build(supportedEfforts: ['b']),
        isFalse,
      );
      expect(
        build(supportedEfforts: ['a']) == build(supportedEfforts: ['a']),
        isTrue,
      );
      // hashCode 的 `?? const []` 分支。
      expect(build().hashCode, build().hashCode);
      expect(base == const ReasoningStatusResponse(), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  group('PersonalitiesResponse', () {
    test('fromJson：人格数组 + 空集合 + 类型不符', () {
      final response = PersonalitiesResponse.fromJson({
        'personalities': [
          {'name': 'p1', 'description': 'd1'},
          {'name': 'p2'},
        ],
      });
      expect(response.personalities, hasLength(2));
      expect(response.personalities!.first.name, 'p1');
      expect(response.personalities!.last.description, isNull);

      expect(
        PersonalitiesResponse.fromJson(const {
          'personalities': <Object?>[],
        }).personalities,
        isEmpty,
      );
      expect(PersonalitiesResponse.fromJson(const {}).personalities, isNull);
      expect(
        PersonalitiesResponse.fromJson({'personalities': null}).personalities,
        isNull,
      );
      expect(
        PersonalitiesResponse.fromJson({'personalities': 'bad'}).personalities,
        isNull,
      );
      expect(
        PersonalitiesResponse.fromJson(const {'personalities': [1]})
            .personalities,
        isNull,
      );
    });

    test('fromJson：无 camelCase 回退（personalities 无别名键）', () {
      expect(
        PersonalitiesResponse.fromJson(const {
          'Personalities': <Object?>[],
        }).personalities,
        isNull,
      );
    });

    test('== / hashCode / toString（阶梯式）', () {
      PersonalitiesResponse build(List<Object?>? personalities) =>
          PersonalitiesResponse.fromJson({'personalities': personalities});

      final base = build([
        {'name': 'p1'},
      ]);
      expect(base, build([
        {'name': 'p1'},
      ]));
      expect(
        base.hashCode,
        build([
          {'name': 'p1'},
        ]).hashCode,
      );
      expect(base.toString(), 'PersonalitiesResponse(personalities: 1)');
      expect(
        const PersonalitiesResponse().toString(),
        'PersonalitiesResponse(personalities: null)',
      );

      expect(base == const PersonalitiesResponse(), isFalse);
      expect(
        const PersonalitiesResponse() == build(const <Object?>[]),
        isFalse,
      );
      expect(
        base ==
            build([
              {'name': 'p1'},
              {'name': 'p2'},
            ]),
        isFalse,
      );
      expect(base == build([
        {'name': 'p2'},
      ]), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  group('PersonalitySummary', () {
    test('fromJson：正常 / 缺失 / 类型不符', () {
      final summary = PersonalitySummary.fromJson({
        'name': 'p1',
        'description': 'd1',
      });
      expect(summary.name, 'p1');
      expect(summary.description, 'd1');

      final empty = PersonalitySummary.fromJson(const {});
      expect(empty.name, isNull);
      expect(empty.description, isNull);

      final coerced = PersonalitySummary.fromJson({'name': 7, 'description': true});
      expect(coerced.name, '7');
      expect(coerced.description, 'true');

      final wrong = PersonalitySummary.fromJson({
        'name': [1],
        'description': {'a': 1},
      });
      expect(wrong.name, isNull);
      expect(wrong.description, isNull);
    });

    test('id：name 优先，缺失时回落 uuidV4', () {
      expect(PersonalitySummary.fromJson({'name': 'p1'}).id, 'p1');
      expect(PersonalitySummary.fromJson(const {}).id, matches(_uuidPattern));
      expect(
        PersonalitySummary.fromJson(const {'description': 'd'}).id,
        matches(_uuidPattern),
      );
    });

    test('== / hashCode / toString（阶梯式）', () {
      PersonalitySummary build({String? name, String? description}) =>
          PersonalitySummary.fromJson({'name': name, 'description': description});

      final base = build(name: 'p1', description: 'd1');
      expect(base, build(name: 'p1', description: 'd1'));
      expect(base.hashCode, build(name: 'p1', description: 'd1').hashCode);
      expect(base.toString(), 'PersonalitySummary(name: p1)');
      expect(
        const PersonalitySummary().toString(),
        'PersonalitySummary(name: null)',
      );

      expect(base == build(name: 'p2', description: 'd1'), isFalse);
      expect(base == build(name: 'p1', description: 'd2'), isFalse);
      expect(base == const PersonalitySummary(), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  group('PersonalitySetResponse', () {
    test('fromJson：4 字段正常 / 缺失 / 类型不符', () {
      final response = PersonalitySetResponse.fromJson({
        'ok': true,
        'personality': 'p1',
        'prompt': 'you are',
        'error': null,
      });
      expect(response.ok, true);
      expect(response.personality, 'p1');
      expect(response.prompt, 'you are');
      expect(response.error, isNull);

      final empty = PersonalitySetResponse.fromJson(const {});
      expect(empty.ok, isNull);
      expect(empty.personality, isNull);
      expect(empty.prompt, isNull);
      expect(empty.error, isNull);

      final wrong = PersonalitySetResponse.fromJson({
        'ok': 2,
        'personality': [1],
        'prompt': {'a': 1},
        'error': true,
      });
      expect(wrong.ok, isNull);
      expect(wrong.personality, isNull);
      expect(wrong.prompt, isNull);
      expect(wrong.error, 'true');
    });

    test('fromJson：无 camelCase 回退（prompt 无别名键）', () {
      expect(PersonalitySetResponse.fromJson({'Prompt': 'x'}).prompt, isNull);
    });

    test('== / hashCode / toString（阶梯式）', () {
      PersonalitySetResponse build({
        bool? ok,
        String? personality,
        String? prompt,
        String? error,
      }) =>
          PersonalitySetResponse.fromJson({
            'ok': ok,
            'personality': personality,
            'prompt': prompt,
            'error': error,
          });

      final base = build(ok: true, personality: 'p', prompt: 'x', error: 'e');
      expect(base, build(ok: true, personality: 'p', prompt: 'x', error: 'e'));
      expect(
        base.hashCode,
        build(ok: true, personality: 'p', prompt: 'x', error: 'e').hashCode,
      );
      expect(base.toString(), 'PersonalitySetResponse(ok: true)');
      expect(
        const PersonalitySetResponse().toString(),
        'PersonalitySetResponse(ok: null)',
      );

      expect(base == build(ok: false, personality: 'p', prompt: 'x', error: 'e'),
          isFalse);
      expect(base == build(ok: true, personality: 'q', prompt: 'x', error: 'e'),
          isFalse);
      expect(base == build(ok: true, personality: 'p', prompt: 'y', error: 'e'),
          isFalse);
      expect(base == build(ok: true, personality: 'p', prompt: 'x', error: 'f'),
          isFalse);
      expect(base == const PersonalitySetResponse(), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  group('ProfilesResponse', () {
    test('fromJson：profiles / active / singleProfileMode', () {
      final response = ProfilesResponse.fromJson({
        'profiles': [
          {'name': 'default'},
          {'name': 'work'},
        ],
        'active': 'work',
        'single_profile_mode': true,
      });
      expect(response.profiles, hasLength(2));
      expect(response.profiles!.first.name, 'default');
      expect(response.active, 'work');
      expect(response.singleProfileMode, true);
    });

    test('fromJson：缺失 / null / 类型不符', () {
      final empty = ProfilesResponse.fromJson(const {});
      expect(empty.profiles, isNull);
      expect(empty.active, isNull);
      expect(empty.singleProfileMode, isNull);

      final wrong = ProfilesResponse.fromJson({
        'profiles': 'bad',
        'active': [1],
        'single_profile_mode': 2,
      });
      expect(wrong.profiles, isNull);
      expect(wrong.active, isNull);
      expect(wrong.singleProfileMode, isNull);

      expect(
        ProfilesResponse.fromJson(const {'profiles': <Object?>[]}).profiles,
        isEmpty,
      );
    });

    test('fromJson：无 camelCase 回退（singleProfileMode 不认）', () {
      expect(
        ProfilesResponse.fromJson({'singleProfileMode': true}).singleProfileMode,
        isNull,
      );
    });

    test('== / hashCode / toString（阶梯式）', () {
      ProfilesResponse build({
        List<Object?>? profiles,
        String? active,
        bool? singleProfileMode,
      }) =>
          ProfilesResponse.fromJson({
            'profiles': profiles,
            'active': active,
            'single_profile_mode': singleProfileMode,
          });

      final base = build(
        profiles: [
          {'name': 'p1'},
        ],
        active: 'p1',
        singleProfileMode: false,
      );
      expect(
        base,
        build(
          profiles: [
            {'name': 'p1'},
          ],
          active: 'p1',
          singleProfileMode: false,
        ),
      );
      expect(
        base.hashCode,
        build(
          profiles: [
            {'name': 'p1'},
          ],
          active: 'p1',
          singleProfileMode: false,
        ).hashCode,
      );
      expect(base.toString(), 'ProfilesResponse(active: p1)');
      expect(
        const ProfilesResponse().toString(),
        'ProfilesResponse(active: null)',
      );

      expect(
        base ==
            build(
              profiles: [
                {'name': 'p2'},
              ],
              active: 'p1',
              singleProfileMode: false,
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              profiles: [
                {'name': 'p1'},
              ],
              active: 'p2',
              singleProfileMode: false,
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              profiles: [
                {'name': 'p1'},
              ],
              active: 'p1',
              singleProfileMode: true,
            ),
        isFalse,
      );
      expect(base == const ProfilesResponse(), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  group('ProfileCreateResponse', () {
    test('fromJson：profile 嵌套 + error', () {
      final response = ProfileCreateResponse.fromJson({
        'ok': true,
        'profile': {'name': 'p1'},
        'error': null,
      });
      expect(response.ok, true);
      expect(response.profile, const ProfileSummary(name: 'p1'));
      expect(response.error, isNull);
    });

    test('fromJson：profile 非 Map / 缺失 → null', () {
      expect(ProfileCreateResponse.fromJson(const {}).profile, isNull);
      expect(
        ProfileCreateResponse.fromJson({'profile': null}).profile,
        isNull,
      );
      expect(
        ProfileCreateResponse.fromJson({'profile': 'bad'}).profile,
        isNull,
      );
      expect(ProfileCreateResponse.fromJson({'profile': 1}).profile, isNull);
      expect(
        ProfileCreateResponse.fromJson(const {'profile': <Object?>[]}).profile,
        isNull,
      );
      final emptyProfile = ProfileCreateResponse.fromJson(const {
        'profile': <String, Object?>{},
      }).profile;
      expect(emptyProfile, isNotNull);
      expect(emptyProfile!.name, isNull);
    });

    test('fromJson：缺失 / 类型不符 → null', () {
      final empty = ProfileCreateResponse.fromJson(const {});
      expect(empty.ok, isNull);
      expect(empty.error, isNull);

      final wrong = ProfileCreateResponse.fromJson({
        'ok': 2,
        'error': [1],
      });
      expect(wrong.ok, isNull);
      expect(wrong.error, isNull);
    });

    test('== / hashCode / toString（阶梯式）', () {
      ProfileCreateResponse build({
        bool? ok,
        Map<String, Object?>? profile,
        String? error,
      }) =>
          ProfileCreateResponse.fromJson({
            'ok': ok,
            'profile': profile,
            'error': error,
          });

      final base = build(ok: true, profile: {'name': 'p'}, error: 'e');
      expect(base, build(ok: true, profile: {'name': 'p'}, error: 'e'));
      expect(
        base.hashCode,
        build(ok: true, profile: {'name': 'p'}, error: 'e').hashCode,
      );
      expect(base.toString(), 'ProfileCreateResponse(ok: true)');
      expect(
        const ProfileCreateResponse().toString(),
        'ProfileCreateResponse(ok: null)',
      );

      expect(base == build(ok: false, profile: {'name': 'p'}, error: 'e'),
          isFalse);
      expect(base == build(ok: true, profile: {'name': 'q'}, error: 'e'),
          isFalse);
      expect(base == build(ok: true, profile: {'name': 'p'}, error: 'f'),
          isFalse);
      expect(base == build(ok: true, profile: null, error: 'e'), isFalse);
      expect(base == const ProfileCreateResponse(), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  group('ProfileSwitchResponse', () {
    test('fromJson：5 字段正常解析', () {
      final response = ProfileSwitchResponse.fromJson({
        'profiles': [
          {'name': 'p1'},
        ],
        'active': 'p1',
        'default_model': 'gpt-5',
        'default_workspace': '/w',
        'error': null,
      });
      expect(response.profiles, hasLength(1));
      expect(response.active, 'p1');
      expect(response.defaultModel, 'gpt-5');
      expect(response.defaultWorkspace, '/w');
      expect(response.error, isNull);
    });

    test('fromJson：缺失 / null / 类型不符', () {
      final empty = ProfileSwitchResponse.fromJson(const {});
      expect(empty.profiles, isNull);
      expect(empty.active, isNull);
      expect(empty.defaultModel, isNull);
      expect(empty.defaultWorkspace, isNull);
      expect(empty.error, isNull);

      final wrong = ProfileSwitchResponse.fromJson({
        'profiles': 'bad',
        'active': [1],
        'default_model': {'a': 1},
        'default_workspace': 1,
        'error': [1],
      });
      expect(wrong.profiles, isNull);
      expect(wrong.active, isNull);
      expect(wrong.defaultModel, isNull);
      expect(wrong.defaultWorkspace, '1');
      expect(wrong.error, isNull);
    });

    test('fromJson：无 camelCase 回退（defaultModel 不认）', () {
      final camel = ProfileSwitchResponse.fromJson({
        'defaultModel': 'x',
        'defaultWorkspace': '/y',
      });
      expect(camel.defaultModel, isNull);
      expect(camel.defaultWorkspace, isNull);
    });

    test('== / hashCode / toString（5 字段逐个阶梯）', () {
      ProfileSwitchResponse build({
        List<Object?>? profiles,
        String? active,
        String? defaultModel,
        String? defaultWorkspace,
        String? error,
      }) =>
          ProfileSwitchResponse.fromJson({
            'profiles': profiles,
            'active': active,
            'default_model': defaultModel,
            'default_workspace': defaultWorkspace,
            'error': error,
          });

      final base = build(
        profiles: [
          {'name': 'p1'},
        ],
        active: 'p1',
        defaultModel: 'm',
        defaultWorkspace: '/w',
        error: 'e',
      );
      expect(
        base,
        build(
          profiles: [
            {'name': 'p1'},
          ],
          active: 'p1',
          defaultModel: 'm',
          defaultWorkspace: '/w',
          error: 'e',
        ),
      );
      expect(
        base.hashCode,
        build(
          profiles: [
            {'name': 'p1'},
          ],
          active: 'p1',
          defaultModel: 'm',
          defaultWorkspace: '/w',
          error: 'e',
        ).hashCode,
      );
      expect(base.toString(), 'ProfileSwitchResponse(active: p1)');
      expect(
        const ProfileSwitchResponse().toString(),
        'ProfileSwitchResponse(active: null)',
      );

      expect(
        base ==
            build(
              profiles: [
                {'name': 'p2'},
              ],
              active: 'p1',
              defaultModel: 'm',
              defaultWorkspace: '/w',
              error: 'e',
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              profiles: [
                {'name': 'p1'},
              ],
              active: 'p2',
              defaultModel: 'm',
              defaultWorkspace: '/w',
              error: 'e',
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              profiles: [
                {'name': 'p1'},
              ],
              active: 'p1',
              defaultModel: 'm2',
              defaultWorkspace: '/w',
              error: 'e',
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              profiles: [
                {'name': 'p1'},
              ],
              active: 'p1',
              defaultModel: 'm',
              defaultWorkspace: '/w2',
              error: 'e',
            ),
        isFalse,
      );
      expect(
        base ==
            build(
              profiles: [
                {'name': 'p1'},
              ],
              active: 'p1',
              defaultModel: 'm',
              defaultWorkspace: '/w',
              error: 'e2',
            ),
        isFalse,
      );
      expect(base == const ProfileSwitchResponse(), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  group('ProfileSummary', () {
    test('fromJson：9 字段正常解析', () {
      final summary = ProfileSummary.fromJson({
        'name': 'work',
        'path': '/p/work',
        'is_default': false,
        'is_active': true,
        'gateway_running': true,
        'model': 'gpt-5',
        'provider': 'openai',
        'has_env': true,
        'skill_count': 12,
      });
      expect(summary.name, 'work');
      expect(summary.path, '/p/work');
      expect(summary.isDefault, false);
      expect(summary.isActive, true);
      expect(summary.gatewayRunning, true);
      expect(summary.model, 'gpt-5');
      expect(summary.provider, 'openai');
      expect(summary.hasEnv, true);
      expect(summary.skillCount, 12);
    });

    test('fromJson：缺失 / null / 类型不符 → null', () {
      final empty = ProfileSummary.fromJson(const {});
      expect(empty.name, isNull);
      expect(empty.path, isNull);
      expect(empty.isDefault, isNull);
      expect(empty.isActive, isNull);
      expect(empty.gatewayRunning, isNull);
      expect(empty.model, isNull);
      expect(empty.provider, isNull);
      expect(empty.hasEnv, isNull);
      expect(empty.skillCount, isNull);

      final wrong = ProfileSummary.fromJson({
        'name': [1],
        'path': {'a': 1},
        'is_default': 2,
        'is_active': 'maybe',
        'gateway_running': 3,
        'model': [1],
        'provider': 4.5,
        'has_env': 'nope',
        'skill_count': 'x',
      });
      expect(wrong.name, isNull);
      expect(wrong.path, isNull);
      expect(wrong.isDefault, isNull);
      expect(wrong.isActive, isNull);
      expect(wrong.gatewayRunning, isNull);
      expect(wrong.model, isNull);
      expect(wrong.provider, '4.5');
      expect(wrong.hasEnv, isNull);
      expect(wrong.skillCount, isNull);
    });

    test('fromJson：skill_count 宽容（double 截断 / 字符串）', () {
      expect(ProfileSummary.fromJson({'skill_count': 12.9}).skillCount, 12);
      expect(ProfileSummary.fromJson({'skill_count': '12'}).skillCount, 12);
    });

    test('id：name → path → uuidV4 三级回落', () {
      expect(ProfileSummary.fromJson({'name': 'n'}).id, 'n');
      expect(ProfileSummary.fromJson({'path': '/p'}).id, '/p');
      expect(ProfileSummary.fromJson(const {}).id, matches(_uuidPattern));
      expect(
        ProfileSummary.fromJson({'name': 'n', 'path': '/p'}).id,
        'n',
      );
    });

    test('displayName：空 → Profile，default → Default，其余 trim 原样', () {
      expect(ProfileSummary.fromJson(const {}).displayName, 'Profile');
      expect(ProfileSummary.fromJson({'name': ''}).displayName, 'Profile');
      expect(ProfileSummary.fromJson({'name': '   '}).displayName, 'Profile');
      expect(ProfileSummary.fromJson({'name': 'default'}).displayName, 'Default');
      expect(
        ProfileSummary.fromJson({'name': ' default '}).displayName,
        'Default',
      );
      expect(ProfileSummary.fromJson({'name': ' work '}).displayName, 'work');
      expect(ProfileSummary.fromJson({'name': 'DEFAULT'}).displayName, 'DEFAULT');
    });

    test('normalizedName：trim + lowercase，缺失 → 空串', () {
      expect(ProfileSummary.fromJson({'name': ' Work '}).normalizedName, 'work');
      expect(ProfileSummary.fromJson({'name': 'WORK'}).normalizedName, 'work');
      expect(ProfileSummary.fromJson(const {}).normalizedName, '');
      expect(ProfileSummary.fromJson({'name': '   '}).normalizedName, '');
      expect(ProfileSummary.fromJson({'name': ''}).normalizedName, '');
    });

    test('== / hashCode / toString（9 字段逐个阶梯）', () {
      ProfileSummary build(Map<String, Object?> overrides) =>
          ProfileSummary.fromJson({
            'name': 'n',
            'path': '/p',
            'is_default': false,
            'is_active': false,
            'gateway_running': false,
            'model': 'm',
            'provider': 'pv',
            'has_env': false,
            'skill_count': 1,
            ...overrides,
          });

      final base = build(const {});
      expect(base, build(const {}));
      expect(base.hashCode, build(const {}).hashCode);
      expect(base.toString(), 'ProfileSummary(name: n)');
      expect(const ProfileSummary().toString(), 'ProfileSummary(name: null)');

      const diffs = <Map<String, Object?>>[
        {'name': 'n2'},
        {'path': '/p2'},
        {'is_default': true},
        {'is_active': true},
        {'gateway_running': true},
        {'model': 'm2'},
        {'provider': 'pv2'},
        {'has_env': true},
        {'skill_count': 2},
      ];
      for (final diff in diffs) {
        expect(base == build(diff), isFalse, reason: '$diff');
      }
      expect(base == const ProfileSummary(), isFalse);
      expect(base == Object(), isFalse);
    });
  });

  // ==========================================================================
  // ModelCatalog 纯客户端解析
  // ==========================================================================
  group('ModelCatalogGroup', () {
    test('构造：extraModels 默认空，字段只读', () {
      const group = ModelCatalogGroup(
        id: 'p1',
        name: 'P1',
        models: [ModelCatalogOption(id: 'm1', displayName: 'M1')],
      );
      expect(group.id, 'p1');
      expect(group.name, 'P1');
      expect(group.providerID, isNull);
      expect(group.models, hasLength(1));
      expect(group.extraModels, isEmpty);
    });

    test('== / hashCode / toString（5 字段逐个阶梯）', () {
      const base = ModelCatalogGroup(
        id: 'p1',
        name: 'P1',
        providerID: 'p1',
        models: [ModelCatalogOption(id: 'm1', displayName: 'M1')],
        extraModels: [ModelCatalogOption(id: 'x1', displayName: 'X1')],
      );
      expect(
        base,
        const ModelCatalogGroup(
          id: 'p1',
          name: 'P1',
          providerID: 'p1',
          models: [ModelCatalogOption(id: 'm1', displayName: 'M1')],
          extraModels: [ModelCatalogOption(id: 'x1', displayName: 'X1')],
        ),
      );
      expect(base.hashCode, base.hashCode);
      expect(base.toString(), 'ModelCatalogGroup(id: p1, name: P1)');

      expect(
        base ==
            const ModelCatalogGroup(
              id: 'p2',
              name: 'P1',
              providerID: 'p1',
              models: [ModelCatalogOption(id: 'm1', displayName: 'M1')],
              extraModels: [ModelCatalogOption(id: 'x1', displayName: 'X1')],
            ),
        isFalse,
      );
      expect(
        base ==
            const ModelCatalogGroup(
              id: 'p1',
              name: 'P2',
              providerID: 'p1',
              models: [ModelCatalogOption(id: 'm1', displayName: 'M1')],
              extraModels: [ModelCatalogOption(id: 'x1', displayName: 'X1')],
            ),
        isFalse,
      );
      expect(
        base ==
            const ModelCatalogGroup(
              id: 'p1',
              name: 'P1',
              providerID: 'p9',
              models: [ModelCatalogOption(id: 'm1', displayName: 'M1')],
              extraModels: [ModelCatalogOption(id: 'x1', displayName: 'X1')],
            ),
        isFalse,
      );
      expect(
        base ==
            const ModelCatalogGroup(
              id: 'p1',
              name: 'P1',
              providerID: 'p1',
              models: [ModelCatalogOption(id: 'm2', displayName: 'M1')],
              extraModels: [ModelCatalogOption(id: 'x1', displayName: 'X1')],
            ),
        isFalse,
      );
      expect(
        base ==
            const ModelCatalogGroup(
              id: 'p1',
              name: 'P1',
              providerID: 'p1',
              models: [
                ModelCatalogOption(id: 'm1', displayName: 'M1'),
                ModelCatalogOption(id: 'm2', displayName: 'M2'),
              ],
              extraModels: [ModelCatalogOption(id: 'x1', displayName: 'X1')],
            ),
        isFalse,
      );
      expect(
        base ==
            const ModelCatalogGroup(
              id: 'p1',
              name: 'P1',
              providerID: 'p1',
              models: [ModelCatalogOption(id: 'm1', displayName: 'M1')],
              extraModels: [ModelCatalogOption(id: 'x2', displayName: 'X1')],
            ),
        isFalse,
      );
      expect(base == Object(), isFalse);
    });
  });

  group('ModelCatalogOption', () {
    test('favoriteKey：(id, providerID)', () {
      const withProvider = ModelCatalogOption(
        id: 'm1',
        displayName: 'M1',
        providerID: 'p1',
      );
      expect(
        withProvider.favoriteKey,
        const ModelFavoriteKey(modelID: 'm1', providerID: 'p1'),
      );
      const withoutProvider = ModelCatalogOption(id: 'm2', displayName: 'M2');
      expect(
        withoutProvider.favoriteKey,
        const ModelFavoriteKey(modelID: 'm2'),
      );
      expect(withoutProvider.favoriteKey.providerID, isNull);
    });

    test('== / hashCode / toString（3 字段逐个阶梯）', () {
      const base = ModelCatalogOption(
        id: 'm1',
        displayName: 'M1',
        providerID: 'p1',
      );
      expect(
        base,
        const ModelCatalogOption(id: 'm1', displayName: 'M1', providerID: 'p1'),
      );
      expect(
        base.hashCode,
        const ModelCatalogOption(id: 'm1', displayName: 'M1', providerID: 'p1')
            .hashCode,
      );
      expect(base.toString(), 'ModelCatalogOption(id: m1)');

      expect(
        base == const ModelCatalogOption(id: 'm2', displayName: 'M1', providerID: 'p1'),
        isFalse,
      );
      expect(
        base == const ModelCatalogOption(id: 'm1', displayName: 'M2', providerID: 'p1'),
        isFalse,
      );
      expect(
        base == const ModelCatalogOption(id: 'm1', displayName: 'M1'),
        isFalse,
      );
      expect(base == const ModelCatalogOption(id: 'm1', displayName: 'M1'),
          isFalse);
      expect(base == Object(), isFalse);
    });
  });

  group('ModelCatalogParser.parseOptions', () {
    test('displayName 顺序：name → label → id（各自 trim）', () {
      final options = ModelCatalogParser.parseOptions([
        _obj({'id': '  m1  ', 'name': '  M1  '}),
        _obj({'id': 'm2', 'label': '  L2  '}),
        _obj({'id': 'm3'}),
        _obj({'id': 'm4', 'name': '   ', 'label': '  L4  '}),
      ]);
      expect(options, hasLength(4));
      expect(options[0].id, 'm1');
      expect(options[0].displayName, 'M1');
      expect(options[1].displayName, 'L2');
      expect(options[2].displayName, 'm3');
      // name 纯空白 → 视为缺失，落到 label。
      expect(options[3].displayName, 'L4');
    });

    test('provider_id 顺序：项内 trim 优先，回落 fallbackProvider', () {
      final options = ModelCatalogParser.parseOptions(
        [
          _obj({'id': 'm1', 'provider_id': ' px '}),
          _obj({'id': 'm2'}),
          _obj({'id': 'm3', 'provider_id': '   '}),
        ],
        fallbackProvider: 'pf',
      );
      expect(options[0].providerID, 'px');
      expect(options[1].providerID, 'pf');
      // 纯空白 provider_id → 回落 fallback。
      expect(options[2].providerID, 'pf');
    });

    test('归一去重：大小写 / 空格 / 下划线归一后相同者只留首项', () {
      final options = ModelCatalogParser.parseOptions([
        _obj({'id': 'A B'}),
        _obj({'id': 'a-b'}),
        _obj({'id': 'a_b'}),
        _obj({'id': 'other'}),
      ]);
      expect(options, hasLength(2));
      expect(options[0].id, 'A B');
      expect(options[1].id, 'other');
    });

    test('跳过项：非对象 / id 缺失 / id 纯空白 / id 非字符串型', () {
      final options = ModelCatalogParser.parseOptions([
        const JsonString('nope'),
        const JsonNumber(7),
        const JsonNull(),
        const JsonArray([]),
        _obj({'name': 'no-id'}),
        _obj({'id': '   '}),
        _obj({'id': 'ok'}),
      ]);
      expect(options, hasLength(1));
      expect(options.single.id, 'ok');
    });

    test('数字 / 布尔 id 经 stringValue 转换（JsonNumber 保 double 形态）', () {
      final options = ModelCatalogParser.parseOptions([
        _obj({'id': 42}),
        _obj({'id': true}),
      ]);
      expect(options, hasLength(2));
      expect(options[0].id, '42.0');
      expect(options[0].displayName, '42.0');
      expect(options[1].id, 'true');
    });

    test('空输入 → 空列表', () {
      expect(ModelCatalogParser.parseOptions(const []), isEmpty);
      expect(ModelCatalogParser.parseOptions(const [], fallbackProvider: 'p'),
          isEmpty);
    });
  });

  group('ModelCatalogParser.parseGroups', () {
    test('非对象组跳过；models 缺失 / 非数组 / 空 / 无合法项 → 整组丢弃', () {
      final groups = ModelCatalogParser.parseGroups([
        const JsonString('not-a-group'),
        const JsonNull(),
        _obj({'provider_id': 'p1'}),
        _obj({'provider_id': 'p2', 'models': 'bad'}),
        _obj({'provider_id': 'p3', 'models': <Object?>[]}),
        _obj({
          'provider_id': 'p4',
          'models': [<Object?>{}],
        }),
        _obj({
          'provider_id': 'p5',
          'models': [
            {'id': 'm5'},
          ],
        }),
      ]);
      // 前六组全部被丢弃，只有最后一组合法。
      expect(groups, hasLength(1));
      expect(groups.single.providerID, 'p5');
      expect(groups.single.id, 'p5');
      expect(groups.single.name, 'p5');
      expect(groups.single.models.single.id, 'm5');
    });

    test('name / id 兜底链：name → providerID → Models，id = providerID ?? name-index',
        () {
      final groups = ModelCatalogParser.parseGroups([
        _obj({
          'provider_id': 'p1',
          'models': [
            {'id': 'm1'},
          ],
        }),
        _obj({
          'models': [
            {'id': 'm2'},
          ],
        }),
        _obj({
          'name': 'Custom',
          'models': [
            {'id': 'm3'},
          ],
        }),
        _obj({
          'name': '   ',
          'provider_id': 'p3',
          'models': [
            {'id': 'm4'},
          ],
        }),
      ]);
      expect(groups, hasLength(4));
      // provider 有、name 无 → name 回落 providerID。
      expect(groups[0].id, 'p1');
      expect(groups[0].name, 'p1');
      // provider 无、name 无 → name 'Models'，id = name-index（下标 1）。
      expect(groups[1].id, 'Models-1');
      expect(groups[1].name, 'Models');
      expect(groups[1].providerID, isNull);
      // name 有、provider 无 → id = name-index。
      expect(groups[2].id, 'Custom-2');
      expect(groups[2].name, 'Custom');
      // name 纯空白 → 回落 providerID。
      expect(groups[3].name, 'p3');
      expect(groups[3].id, 'p3');
    });

    test('fallbackProvider 随组向下传给模型选项', () {
      final groups = ModelCatalogParser.parseGroups([
        _obj({
          'provider_id': 'p1',
          'models': [
            {'id': 'm1'},
            {'id': 'm2', 'provider_id': 'px'},
          ],
        }),
      ]);
      expect(groups.single.models[0].providerID, 'p1');
      expect(groups.single.models[1].providerID, 'px');
    });

    test('extra_models：独立解析并保留（缺失 → 空列表）', () {
      final groups = ModelCatalogParser.parseGroups([
        _obj({
          'provider_id': 'p1',
          'models': [
            {'id': 'm1'},
          ],
          'extra_models': [
            {'id': 'x1', 'name': 'X1'},
            'bad',
          ],
        }),
      ]);
      expect(groups.single.models, hasLength(1));
      expect(groups.single.extraModels, hasLength(1));
      expect(groups.single.extraModels.single.displayName, 'X1');
      expect(groups.single.extraModels.single.providerID, 'p1');
    });

    test('provider_id 非字符串型 → stringValue 归一（JsonNumber 保 double 形态）',
        () {
      final groups = ModelCatalogParser.parseGroups([
        _obj({
          'provider_id': 42,
          'models': [
            {'id': 'm1'},
          ],
        }),
      ]);
      expect(groups.single.providerID, '42.0');
      expect(groups.single.id, '42.0');
      expect(groups.single.name, '42.0');
    });

    test('空 groups / 全被过滤 → 空列表', () {
      expect(ModelCatalogParser.parseGroups(const []), isEmpty);
      expect(
        ModelCatalogParser.parseGroups([
          const JsonString('x'),
          _obj({'provider_id': 'p'}),
        ]),
        isEmpty,
      );
    });
  });

  group('mergingLiveModels', () {
    const groups = <ModelCatalogGroup>[
      ModelCatalogGroup(
        id: 'p1',
        name: 'P1',
        providerID: 'p1',
        models: [ModelCatalogOption(id: 'old', displayName: 'Old')],
        extraModels: [ModelCatalogOption(id: 'x1', displayName: 'X1')],
      ),
      ModelCatalogGroup(
        id: 'p2',
        name: 'P2',
        providerID: 'p2',
        models: [ModelCatalogOption(id: 'keep', displayName: 'Keep')],
      ),
    ];

    test('provider 缺失 / 纯空白 → 原样返回同一实例', () {
      expect(
        identical(groups.mergingLiveModels(const ModelsLiveResponse()), groups),
        isTrue,
      );
      expect(
        identical(
          groups.mergingLiveModels(
            ModelsLiveResponse.fromJson({'provider': '   '}),
          ),
          groups,
        ),
        isTrue,
      );
    });

    test('liveOptions 为空 → 原样返回同一实例', () {
      final noModels = ModelsLiveResponse.fromJson({'provider': 'p1'});
      expect(noModels.liveOptions, isEmpty);
      expect(identical(groups.mergingLiveModels(noModels), groups), isTrue);

      final emptyModels = ModelsLiveResponse.fromJson({
        'provider': 'p1',
        'models': <Object?>[],
      });
      expect(identical(groups.mergingLiveModels(emptyModels), groups), isTrue);

      final badModels = ModelsLiveResponse.fromJson({
        'provider': 'p1',
        'models': 'bad',
      });
      expect(identical(groups.mergingLiveModels(badModels), groups), isTrue);
    });

    test('命中组：替换 models，保留 id / name / providerID / extraModels', () {
      final merged = groups.mergingLiveModels(ModelsLiveResponse.fromJson({
        'provider': ' p1 ',
        'models': [
          {'id': 'new1', 'name': 'New 1'},
          {'id': 'new2'},
        ],
      }));

      expect(identical(merged, groups), isFalse);
      expect(merged, hasLength(2));
      expect(merged[0].id, 'p1');
      expect(merged[0].name, 'P1');
      expect(merged[0].providerID, 'p1');
      expect(merged[0].models, hasLength(2));
      expect(merged[0].models.first.id, 'new1');
      expect(merged[0].models.first.displayName, 'New 1');
      expect(merged[0].models.first.providerID, 'p1');
      expect(merged[0].models.last.displayName, 'new2');
      // extraModels 保留原值（同实例）。
      expect(
        identical(merged[0].extraModels, groups[0].extraModels),
        isTrue,
      );
    });

    test('未命中组：原样返回同一 group 实例', () {
      final merged = groups.mergingLiveModels(ModelsLiveResponse.fromJson({
        'provider': 'p1',
        'models': [
          {'id': 'new1'},
        ],
      }));
      expect(identical(merged[0], groups[0]), isFalse);
      expect(identical(merged[1], groups[1]), isTrue);
      expect(merged[1].models.single.id, 'keep');
    });

    test('provider 无匹配组 / 空列表 → 不抛错', () {
      final merged = groups.mergingLiveModels(ModelsLiveResponse.fromJson({
        'provider': 'nope',
        'models': [
          {'id': 'new1'},
        ],
      }));
      expect(merged, hasLength(2));
      expect(identical(merged[0], groups[0]), isTrue);
      expect(identical(merged[1], groups[1]), isTrue);
      expect(
        const <ModelCatalogGroup>[]
            .mergingLiveModels(ModelsLiveResponse.fromJson({
          'provider': 'p1',
          'models': [
            {'id': 'new1'},
          ],
        })),
        isEmpty,
      );
    });
  });
}
