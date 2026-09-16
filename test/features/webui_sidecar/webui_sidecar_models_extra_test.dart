// WebUI Sidecar 模型与配置持久化补测：
// - SidecarState 的 copyWith / 相等性（含 runtimeType 比较）/ hashCode / toString；
// - WebuiSidecarConfigStorage 未注入 prefs 时的 SharedPreferences 回落路径。
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/webui_sidecar/webui_sidecar_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 刻意子类化：用于打通 `runtimeType` 比较分支。
class _SidecarStateSubclass extends SidecarState {
  const _SidecarStateSubclass({
    super.status,
    super.reason,
    super.pid,
    super.detail,
  });
}

class _FakeSecureStorage implements SidecarSecureStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  group('SidecarState copyWith', () {
    const base = SidecarState(
      status: SidecarStatus.starting,
      reason: SidecarFailureReason.none,
      pid: 10,
      detail: 'detail-10',
    );

    test('无参调用保持全部字段', () {
      final copy = base.copyWith();

      expect(copy, equals(base));
      expect(copy.hashCode, equals(base.hashCode));
    });

    test('逐键覆盖：只改给定字段，其余保持原值', () {
      final byStatus = base.copyWith(status: SidecarStatus.running);
      expect(byStatus.status, SidecarStatus.running);
      expect(byStatus.reason, SidecarFailureReason.none);
      expect(byStatus.pid, 10);
      expect(byStatus.detail, 'detail-10');

      final byReason = base.copyWith(
        reason: SidecarFailureReason.healthTimeout,
      );
      expect(byReason.reason, SidecarFailureReason.healthTimeout);
      expect(byReason.status, SidecarStatus.starting);

      final byPid = base.copyWith(pid: 42);
      expect(byPid.pid, 42);
      expect(byPid.detail, 'detail-10');

      final byDetail = base.copyWith(detail: 'other');
      expect(byDetail.detail, 'other');
      expect(byDetail.pid, 10);
    });

    test('clearPid / clearDetail 显式清空，且优先级高于同时传入的新值', () {
      const filled = SidecarState(
        status: SidecarStatus.running,
        pid: 7,
        detail: 'takeover',
      );

      expect(filled.copyWith(clearPid: true).pid, isNull);
      expect(filled.copyWith(clearDetail: true).detail, isNull);
      expect(filled.copyWith(pid: 9, clearPid: true).pid, isNull);
      expect(filled.copyWith(detail: 'z', clearDetail: true).detail, isNull);

      // 只清一项时另一项保持
      final onlyPidCleared = filled.copyWith(clearPid: true);
      expect(onlyPidCleared.detail, 'takeover');
      expect(onlyPidCleared.status, SidecarStatus.running);
    });
  });

  group('SidecarState 相等性 / hashCode / toString', () {
    const a = SidecarState(
      status: SidecarStatus.running,
      reason: SidecarFailureReason.none,
      pid: 5,
      detail: 'd',
    );
    const sameAsA = SidecarState(
      status: SidecarStatus.running,
      reason: SidecarFailureReason.none,
      pid: 5,
      detail: 'd',
    );

    test('同值相等、hashCode 一致；自反；与 Object 不等', () {
      expect(a, equals(sameAsA));
      expect(a.hashCode, equals(sameAsA.hashCode));
      expect(a == a, isTrue);
      expect(a == Object(), isFalse);
    });

    test('逐字段不等都能识别（status / reason / pid / detail）', () {
      expect(
        a,
        isNot(
          equals(a.copyWith(status: SidecarStatus.failed)),
        ),
      );
      expect(
        a,
        isNot(
          equals(a.copyWith(reason: SidecarFailureReason.portOccupied)),
        ),
      );
      expect(a, isNot(equals(a.copyWith(pid: 6))));
      expect(a, isNot(equals(a.copyWith(detail: 'other'))));
      expect(a.copyWith(pid: 7).hashCode, isNot(equals(a.hashCode)));
    });

    test('runtimeType 不同的子类即使字段相同也不相等', () {
      const subclass = _SidecarStateSubclass(
        status: SidecarStatus.running,
        reason: SidecarFailureReason.none,
        pid: 5,
        detail: 'd',
      );

      expect(subclass, isA<SidecarState>());
      expect(subclass.status, a.status);
      expect(subclass, isNot(equals(a)));
      expect(a, isNot(equals(subclass)));
    });

    test('toString 暴露四个字段', () {
      final text = a.toString();

      expect(text, contains('SidecarState('));
      expect(text, contains('status: SidecarStatus.running'));
      expect(text, contains('reason: SidecarFailureReason.none'));
      expect(text, contains('pid: 5'));
      expect(text, contains('detail: d'));
    });
  });

  group('WebuiSidecarConfigStorage 未注入 prefs 的回落路径', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('未注入 prefs → 走 SharedPreferences.getInstance()，首读生成并落盘密码', () async {
      final secure = _FakeSecureStorage();
      final storage = WebuiSidecarConfigStorage(secureStorage: secure);

      final config = await storage.load();

      expect(config.enabled, isFalse);
      expect(config.host, SidecarConfig.defaultHost);
      expect(config.port, SidecarConfig.defaultPort);
      expect(config.password.length, SidecarConfig.defaultPasswordLength);
      expect(
        await secure.read(WebuiSidecarConfigStorage.keyPassword),
        config.password,
      );

      // 同一实例二次 load 复用同一个 SharedPreferences 单例
      final again = await storage.load();
      expect(again, equals(config));
    });

    test('未注入 prefs 时 save 也走回落路径并只落非秘密字段', () async {
      final secure = _FakeSecureStorage();
      final storage = WebuiSidecarConfigStorage(secureStorage: secure);

      const toSave = SidecarConfig(
        enabled: true,
        host: '0.0.0.0',
        port: 9009,
        password: 'fallback_pwd',
      );
      await storage.save(toSave);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(WebuiSidecarConfigStorage.keyEnabled), isTrue);
      expect(prefs.getString(WebuiSidecarConfigStorage.keyHost), '0.0.0.0');
      expect(prefs.getInt(WebuiSidecarConfigStorage.keyPort), 9009);
      expect(
        prefs.containsKey(WebuiSidecarConfigStorage.keyPassword),
        isFalse,
      );
      expect(
        await secure.read(WebuiSidecarConfigStorage.keyPassword),
        'fallback_pwd',
      );
    });

    test('键位类型不符：SharedPreferences 取值不做类型容错（load 抛出类型错误）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        WebuiSidecarConfigStorage.keyEnabled: 'not-a-bool',
      });
      final secure = _FakeSecureStorage();
      final storage = WebuiSidecarConfigStorage(secureStorage: secure);

      await expectLater(storage.load(), throwsA(isA<TypeError>()));
      // 类型不符在读取阶段即失败，不生成也不落盘密码。
      expect(secure.values, isEmpty);
    });

    test('密码为空串（已存空值）→ 重新生成并落盘', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        WebuiSidecarConfigStorage.keyHost: '127.0.0.1',
      });
      final secure = _FakeSecureStorage();
      await secure.write(WebuiSidecarConfigStorage.keyPassword, '   ');
      final storage = WebuiSidecarConfigStorage(secureStorage: secure);

      final config = await storage.load();

      expect(config.password, isNot('   '));
      expect(config.password.length, SidecarConfig.defaultPasswordLength);
      expect(
        await secure.read(WebuiSidecarConfigStorage.keyPassword),
        config.password,
      );
    });
  });
}
