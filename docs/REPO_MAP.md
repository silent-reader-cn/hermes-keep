# REPO_MAP.md — 仓库实盘快照（自动生成）

> **本文件自动生成，请勿手工修改。** 重生成：`python tools/gen_repo_map.py`
>
> AGENTS.md §3 只钉目录约定与边界，明细清单以本文件为准，避免手工清单随迭代漂移。

## `lib/` — 共 238 个 dart 文件

| 目录 | dart 文件 |
|---|---:|
| `lib/app/` | 23 |
| `lib/core/` | 81 |
| `lib/features/` | 131 |
| `lib/l10n/` | 1 |
| `lib/driver_main.dart` | 入口 |
| `lib/main.dart` | 入口 |

### `lib/features/`（每个 feature 自成目录，Provider 与页面同目录）

共 20 个 feature：

| feature | dart 文件 |
|---|---:|
| `chat/` | 33 |
| `desktop/` | 7 |
| `diagnostics/` | 6 |
| `downloads/` | 7 |
| `git/` | 4 |
| `insights/` | 3 |
| `kanban/` | 3 |
| `memory/` | 3 |
| `notifications/` | 7 |
| `onboarding/` | 7 |
| `projects/` | 2 |
| `prompts/` | 2 |
| `session_list/` | 9 |
| `settings/` | 16 |
| `shared/` | 2 |
| `skills/` | 3 |
| `tasks/` | 3 |
| `webui_sidecar/` | 4 |
| `workspace/` | 3 |
| `workspace_manager/` | 7 |

### `lib/app/`

| 子目录 | dart 文件 |
|---|---:|
| `app/locale/` | 2 |
| `app/shell/` | 6 |
| `app/theme/` | 4 |
| `app/widgets/` | 8 |

### `lib/core/`

| 子目录 | dart 文件 |
|---|---:|
| `core/api/` | 19 |
| `core/cache/` | 8 |
| `core/connections/` | 3 |
| `core/install/` | 4 |
| `core/models/` | 29 |
| `core/providers/` | 2 |
| `core/update/` | 5 |
| `core/utils/` | 11 |

## `test/` — 共 292 个 dart 文件

| 目录 | dart 文件 |
|---|---:|
| `test/app/` | 15 |
| `test/core/` | 58 |
| `test/features/` | 193 |
| `test/fixtures/` | 0 |
| `test/golden/` | 3 |
| `test/helpers/` | 18 |
| `test/l10n/` | 1 |
| `test/screenshots/` | 1 |
| `test/flutter_test_config.dart` | |
| `test/main_error_card_test.dart` | |
| `test/widget_test.dart` | |

金照基线：`test/golden/` 下 102 张 PNG

## 顶层与辅助目录

| 路径 | 内容 |
|---|---|
| `assets/` | 2 个直接子项 |
| `docs/` | 12 个直接子项 |
| `tools/` | 5 个直接子项 |
| `third_party/` | 1 个直接子项 |
| `android/` | 13 个直接子项 |
| `windows/` | 4 个直接子项 |
| `linux/` | 4 个直接子项 |
| `macos/` | 6 个直接子项 |
| `web/` | 5 个直接子项 |
| `ios/` | 6 个直接子项 |
| `.github/` | 1 个直接子项 |

### `assets/`

- `assets/branding/`
-   `assets/branding/hermes-agent-icon-1024.png`
-   `assets/branding/notification_logo.png`
-   `assets/branding/tray_icon.ico`
-   `assets/branding/tray_icon_16.png`
-   `assets/branding/tray_icon_32.png`
- `assets/fonts/`
-   `assets/fonts/LICENSE.txt`
-   `assets/fonts/MiSans-Medium.ttf`
-   `assets/fonts/MiSans-Regular.ttf`
-   `assets/fonts/OFL.txt`

### `tools/`

- `tools/fake_gateway/`
-   `tools/fake_gateway/main.py`
-   `tools/fake_gateway/README.md`
-   `tools/fake_gateway/requirements.txt`
-   `tools/fake_gateway/smoke_test.py`
- `tools/gen_repo_map.py`
- `tools/icon_pipeline/`
-   `tools/icon_pipeline/generate_icons.py`
- `tools/light_theme_contrast.py`
- `tools/patch_windows_irondash.py`

### `third_party/`

- `third_party/flutter_markdown/`
-   `third_party/flutter_markdown/CHANGELOG.md`
-   `third_party/flutter_markdown/lib/`
-     `third_party/flutter_markdown/lib/src/`
-   `third_party/flutter_markdown/LICENSE`
-   `third_party/flutter_markdown/PATCH_NOTES.md`
-   `third_party/flutter_markdown/pubspec.yaml`
-   `third_party/flutter_markdown/README.md`

### `docs/`

- `docs/auto_reauth_spec.md`
- `docs/cache_audit_report.md`
- `docs/PLAN-session-gaps-phase2-2026-08.md`
- `docs/PROTOCOL_NOTES.md`
- `docs/QA.md`
- `docs/RELEASE.md`
- `docs/REPO_MAP.md`
- `docs/results-sep02-46-install-guide.md`
- `docs/results-sep02-50-keepalive-notify.md`
- `docs/results-sep02-52-status-line.md`

- `docs/specs/` — 16 份规格：
  - `agent-injected-message-cards-spec.md`
  - `api_spec.md`
  - `app_shell_spec.md`
  - `backend-api-catalog.md`
  - `chat_spec.md`
  - `l10n-exemptions.md`
  - `light-theme-audit-2026-09-12.md`
  - `metering-frequency-finding.md`
  - `models_spec.md`
  - `saved-prompts-spec.md`
  - `selected-context-spec.md`
  - `session-auto-refresh-spec.md`
  - `settings-extensions-mcp-aux-spec.md`
  - `webui-sidecar-integration-acceptance.md`
  - `webui-sidecar-packaging.md`
  - `workspace_manager_spec.md`
  - `backend-api-details/`

- `docs/screenshots/` — README 截图 28 张

### 仓库根文件

- `.flutter-plugins-dependencies`
- `.gitignore`
- `.metadata`
- `AGENTS.md`
- `analysis_options.yaml`
- `CHANGELOG.md`
- `DESIGN.md`
- `devtools_options.yaml`
- `HERMES.md`
- `hermex_flutter.iml`
- `LICENSE`
- `pubspec.lock`
- `pubspec.yaml`
- `README.md`
- `README.zh-CN.md`
- `THIRD-PARTY-NOTICES.md`
