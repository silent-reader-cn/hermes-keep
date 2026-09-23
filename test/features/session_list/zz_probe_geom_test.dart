import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/shell/session_sidebar.dart';
import 'package:hermes_ui/app/shell/sidebar_brand_bar.dart';
import 'package:hermes_ui/app/shell/sidebar_tools_list.dart';

void main() {
  testWidgets('probe: 侧栏各区块几何', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const ProviderScope(
        child: CupertinoApp(
          home: CupertinoPageScaffold(
            child: SizedBox(width: 340, child: SessionSidebar(currentLocation: '/')),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    debugPrint('PROBE brand rect = ${tester.getRect(find.byType(SidebarBrandBar))}');
    debugPrint('PROBE tools rect = ${tester.getRect(find.byType(SidebarToolsList))}');

    final items = <(double, String)>[];
    for (final e in find.byType(Text).evaluate()) {
      final t = (e.widget as Text).data;
      if (t == null || t.trim().isEmpty) continue;
      final box = e.renderObject as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final pos = box.localToGlobal(Offset.zero);
      if (pos.dx > 350) continue;
      items.add((pos.dy, t.length > 22 ? '${t.substring(0, 22)}…' : t));
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));
    debugPrint('PROBE 侧栏内文本 y（共 ${items.length} 条）:');
    for (final i in items.take(16)) {
      debugPrint('PROBE   y=${i.$1.toStringAsFixed(1)}  「${i.$2}」');
    }
  });
}
