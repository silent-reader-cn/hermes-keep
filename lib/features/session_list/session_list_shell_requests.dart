import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 会话列表筛选弹层的「打开请求」信号（#149 品牌行 → 列表页单向通知）。
///
/// 背景：侧栏顶部品牌行（`SidebarBrandBar`）与筛选弹层（`_SessionFilterSheet`）
/// 分处不同层级 —— 弹层依赖列表页私有状态与私有方法，直接搬迁成本高、风险大。
/// 故采用信号式中转：品牌行的筛选按钮 bump 计数，列表页 `ref.listen` 到变化后
/// 用**自己已有的** `_showFilterSheet` 打开弹层（零搬迁）。
///
/// 用自增计数而非 bool：连续点击两次筛选（第一次关掉弹层后立刻再点）也能触发，
/// 不会被去重掉。
final sessionListFilterRequestProvider = NotifierProvider<
    SessionListFilterRequestController, int>(
  SessionListFilterRequestController.new,
);

/// 筛选打开请求控制器：`bump()` 自增即发起一次打开请求。
class SessionListFilterRequestController extends Notifier<int> {
  @override
  int build() => 0;

  /// 发起一次「打开筛选弹层」请求。
  void bump() => state = state + 1;
}