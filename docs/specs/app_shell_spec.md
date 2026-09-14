# App Shell 规格（app_shell_spec）— Phase 2 编码依据

> 版本：v1.0 ｜ 领头人：柚子 ｜ 供 Phase 2 编码子代理直接使用
> 相关文档：AGENTS.md（强制规范）、api_spec.md（§2 ApiClient 设计）、chat_spec.md（chat 模块）

## 1. 目标

实现 App 壳：入口、路由、Cupertino 主题、服务器连接管理、onboarding 向导。
这是 UI 层的地基，后续 session_list / chat / tasks 等 feature 都在此之上搭建。

## 2. 入口与全局结构

### 2.1 main.dart
```
void main() {
  runApp(ProviderScope(child: HermexApp()));
}
```
- 平台分支：桌面（Windows/macOS/Linux）与移动端共用同一套 Cupertino UI，无需分支
- 初始化顺序：ProviderScope → 读取持久化连接 → 若存在已选服务器则进入 SessionList，否则 Onboarding

### 2.2 根 Widget：HermexApp
- 用 `CupertinoApp`（**不是 MaterialApp**——业务 UI 全 Cupertino，AGENTS.md §2 硬约束）
- `theme: CupertinoThemeData`（深色 + 浅色，见 §4）
- `router: go_router` 路由表（见 §3）
- `localizationsDelegates`：默认 + flutter_localizations（中文/英文）
- 桌面端：窗口标题 "Hermes"；移动端：状态栏样式

## 3. 路由表（go_router）

| 路径 | 页面 | 说明 |
|---|---|---|
| `/onboarding` | OnboardingPage | 无连接时进入 |
| `/` | SessionListPage | 主列表（有连接时默认） |
| `/chat/:sessionId` | ChatPage | 聊天（sessionId 为空=新会话） |
| `/settings` | SettingsPage | 设置（模型/外观/服务器） |
| `/workspace/:sessionId` | WorkspacePage | 文件浏览（后置） |

- 路由守卫：未配置服务器 → 重定向 `/onboarding`
- 路由变化时同步 Provider（如当前会话 ID）

## 4. 主题（CupertinoThemeData）

- **主色**：Hermex 风格 iOS 蓝（`Color(0xFF007AFF)`）——与 Hermex 原生一致
- **深色模式**：`CupertinoThemeData(brightness: Brightness.dark, primaryColor: ..., scaffoldBackgroundColor: Color(0xFF000000))`
- **浅色模式**：`scaffoldBackgroundColor: CupertinoColors.systemGroupedBackground`
- 跟随系统：`MediaQuery.platformBrightnessOf(context)`
- 全局字体：选用 MiSans（`assets/fonts/`，包含 Regular 400 + Medium 500/600/700），兼顾中文美感与西文/数字协调度
- 全局文字样式：正文 17pt（iOS 默认）、大标题 34pt Bold、代码块用 monospace

## 5. 连接管理（core/connections/）

### 5.1 ServerConnection 模型（lib/core/connections/server_connection.dart）
```
class ServerConnection {
  final String id;            // 本地生成 uuid
  final String name;          // 用户命名，如 "Home"
  final String baseUrl;       // 如 https://hermes.example.com:30002
  final String? username;     // dashboard 登录用户名（可空）
  final String? password;     // 仅内存/secure storage，不进状态
  final Map<String, String> customHeaders;  // 反向代理自定义头
  final DateTime createdAt;
}
```

### 5.2 存储服务（lib/core/connections/connection_store.dart）
- **持久化**：`flutter_secure_storage` 存 `connections`（JSON 数组，密码字段单独加密） + `active_connection_id`
- 接口：`loadAll()` / `save(connection)` / `delete(id)` / `setActive(id)` / `getActive()`
- 多服务器支持（Hermex 支持多 server 切换）

### 5.3 连接 Provider（lib/core/connections/connection_providers.dart）
```
final connectionsProvider = NotifierProvider<ConnectionsController, List<ServerConnection>>(...);
final activeConnectionProvider = NotifierProvider<ActiveConnectionController, ServerConnection?>(...);
final apiClientProvider = Provider<ApiClient>((ref) {
  final conn = ref.watch(activeConnectionProvider);
  return ApiClient(baseUrl: conn!.baseUrl, customHeaders: conn.customHeaders);
});
```
- 切换连接时重建 ApiClient（Provider 依赖 activeConnection 自动重建）
- **安全**：密码和 header 值只在内存与 secure storage，禁止进日志/状态快照

## 6. Onboarding 向导（features/onboarding/）

三步式（Cupertino 风格）：

### 6.1 步骤 1：服务器地址
- CupertinoTextField 输入 baseUrl
- "连接测试"：调用 `GET /api/health`（api_spec §1.1 server.health），成功显示 ✅

### 6.2 步骤 2：认证
- 两种模式：
  - **无密码**（webui 未开 auth）：跳过
  - **密码登录**：用户名 + 密码 → `POST /api/auth/login`（api_spec §1.1 server.login）→ 成功后 cookie 由 dio cookie 管理（api_client 内部处理）
- 登录失败显示 CupertinoAlertDialog

### 6.3 步骤 3：自定义 Headers（可选，展开式）
- 反向代理场景：添加 `Authorization: Bearer xxx` 等（key/value 行，支持多行）
- 校验：header 名合法 token、值无换行（RFC 7230，对齐 api_spec §2.2）

### 6.4 完成
- 保存 ServerConnection → setActive → 路由跳 `/`（SessionListPage）
- "跳过向导"入口：高级模式直接填 URL + headers（给已有 API key 场景）

## 7. 完成定义（Phase 2 验收标准）

- [ ] `/c/tmp/f.bat analyze lib/app/ lib/core/connections/ lib/features/onboarding/` 零告警
- [ ] `/c/tmp/f.bat test test/core/connections/ test/features/onboarding/` 全绿
- [ ] 无 Material widget 混入业务 UI（除必要桥接）
- [ ] `flutter run -d windows` 可启动：无连接 → onboarding 向导；配置后 → SessionList 空态
- [ ] 主题深浅色跟随系统切换生效
- [ ] 连接增删改 + 切换 + 持久化（重启后保留）

## 8. 依赖（已在 pubspec）

flutter_riverpod / go_router / dio / flutter_secure_storage / flutter_markdown（后置）
