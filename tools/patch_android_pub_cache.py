#!/usr/bin/env python3
"""把 pub cache 里「停维护插件」的构建脚本补成可构建态（幂等，CI 与本地共用）。

背景
----
``super_clipboard`` 0.1.7 家族（``irondash_engine_context`` 0.1.1 /
``super_native_extensions`` 0.1.8）已停维护，在 AGP 8+ / Gradle 9 下有两类硬伤，
干净 pub cache 上必然构建失败：

1. **未声明 AGP 8+ 必需的 ``namespace``** —— Gradle *配置期*即报：

       A problem occurred configuring project ':irondash_engine_context'.
       > Namespace not specified. Specify a namespace in the module's build file: ...

2. **``cargokit/gradle/plugin.gradle`` 用了 Gradle 9 已移除的 ``childProjects``**：

       A problem occurred evaluating script.
       > Failed to apply plugin class 'CargoKitPlugin'.
          > No such property: childProjects for class: java.util.HashMap$Node

本机 2026-08-24 曾**手工改过 pub cache** 绕过这两处（三个文件 mtime 比同包其它
文件晚约 10 小时；镜像副本 ``pub.flutter-io.cn`` 同版本没有这些改动）。那属于
仓库外状态，换机器 / CI / 清 cache 即失效——本脚本把它收敛为入仓、幂等、可复现
的一步，CI 与本地共用。

补什么
------
- ``namespace``：注入 ``android/build.gradle``；取值优先
  ``android/src/main/AndroidManifest.xml`` 的 ``package`` 属性（与本机手工补丁
  的值逐一核对一致），缺失时退回内置映射。
- ``compileSdkVersion``：干净副本写死 **31**，与 app 的 ``compileSdk``（当前 37）
  不一致会构建失败；手工补丁把它抬成了 36。这里**对齐 app 的值**（从
  ``android/app/build.gradle(.kts)`` 读取），避免两处长期漂移。
- **CargoKit**：缓存副本缺 Gradle 9 兼容改动时，用
  ``tools/vendor/cargokit_gradle9_plugin.gradle``（MIT，派生自
  super_native_extensions 0.1.8+2）整体替换。

用法
----
    python tools/patch_android_pub_cache.py            # 补 cache（幂等）
    python tools/patch_android_pub_cache.py --dry-run  # 只报告

可删条件
--------
``super_clipboard`` 升到 0.9+（依赖 irondash 0.5+，自带 namespace 与新版
CargoKit）后，删除本脚本、``tools/vendor/cargokit_gradle9_plugin.gradle``，
以及 CI / AGENTS.md 中对本脚本的引用。
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

# 目标包 → 内置 namespace 兜底（manifest 的 package 属性缺失时使用）。
TARGET_FALLBACK_NAMESPACE = {
    "irondash_engine_context": "dev.irondash.engine_context",
    "super_native_extensions": "com.superlist.super_native_extensions",
}

# 项目根（本脚本所在 tools/ 的上一级），用于定位 vendored 文件。
PROJECT_ROOT = Path(__file__).resolve().parents[1]
VENDORED_CARGOKIT = PROJECT_ROOT / "tools" / "vendor" / "cargokit_gradle9_plugin.gradle"

# CargoKit 缓存副本「已含 Gradle 9 兼容改动」的判定标记。
CARGOKIT_PATCHED_MARKER = "_findFlutterPluginLegacy"

MANIFEST_PACKAGE_RE = re.compile(r'package\s*=\s*"([^"]+)"')
GRADLE_ANDROID_BLOCK_RE = re.compile(r"^(\s*android\s*\{\s*)$", re.MULTILINE)
APP_COMPILE_SDK_RE = re.compile(r"compileSdk(?:Version)?\s*=?\s*(\d+)")
PLUGIN_COMPILE_SDK_RE = re.compile(r"(compileSdkVersion\s+)(\d+)")

# app 侧构建脚本（用于取权威 compileSdk）。
APP_GRADLE_CANDIDATES = (
    PROJECT_ROOT / "android" / "app" / "build.gradle.kts",
    PROJECT_ROOT / "android" / "app" / "build.gradle",
)


def app_compile_sdk() -> int | None:
    """从 app 构建脚本读权威 compileSdk；读不到返回 None。"""
    for path in APP_GRADLE_CANDIDATES:
        if path.is_file():
            match = APP_COMPILE_SDK_RE.search(
                path.read_text(encoding="utf-8", errors="replace")
            )
            if match:
                return int(match.group(1))
    return None


def align_compile_sdk(text: str) -> tuple[str, str | None]:
    """把插件侧 compileSdkVersion 抬到 app 的值；返回 (新文本, 变更说明)。"""
    target = app_compile_sdk()
    if target is None:
        return text, None

    changes: list[str] = []

    def _bump(match: re.Match) -> str:
        current = int(match.group(2))
        if current >= target:
            return match.group(0)
        changes.append(f"{current}→{target}")
        return f"{match.group(1)}{target}"

    return PLUGIN_COMPILE_SDK_RE.sub(_bump, text), ("、".join(changes) or None)


def pub_cache_roots() -> list[Path]:
    """返回候选 pub cache 根目录（按优先级）。"""
    roots: list[Path] = []
    env = os.environ.get("PUB_CACHE")
    if env:
        roots.append(Path(env))
    roots.append(Path.home() / ".pub-cache")
    local_appdata = os.environ.get("LOCALAPPDATA")
    if local_appdata:
        roots.append(Path(local_appdata) / "Pub" / "Cache")
    return [r for r in roots if r.is_dir()]


def package_dirs() -> list[Path]:
    """枚举 cache 内所有目标包目录（任意版本、任意 hosted 镜像）。"""
    found: list[Path] = []
    for root in pub_cache_roots():
        hosted = root / "hosted"
        if not hosted.is_dir():
            continue
        for mirror in hosted.iterdir():
            if not mirror.is_dir():
                continue
            for entry in mirror.iterdir():
                if not entry.is_dir():
                    continue
                name = entry.name.rsplit("-", 1)[0]
                if name in TARGET_FALLBACK_NAMESPACE:
                    found.append(entry)
    return sorted(found)


def namespace_for(pkg: Path) -> str:
    """取该包的 namespace：manifest 的 package 属性优先，否则用兜底映射。"""
    manifest = pkg / "android" / "src" / "main" / "AndroidManifest.xml"
    if manifest.is_file():
        match = MANIFEST_PACKAGE_RE.search(
            manifest.read_text(encoding="utf-8", errors="replace")
        )
        if match:
            return match.group(1)
    return TARGET_FALLBACK_NAMESPACE[pkg.name.rsplit("-", 1)[0]]


def patch_gradle_module(pkg: Path, dry_run: bool) -> list[str]:
    """补 android/build.gradle(.kts) 的 namespace 与 compileSdkVersion。

    字节级读写：只用 ``read_bytes``/``write_bytes``，避免 ``Path.write_text`` 在
    Windows 上把整份文件的 LF 翻译成 CRLF（会污染与上游的比对）。
    """
    g = pkg / "android" / "build.gradle"
    gk = pkg / "android" / "build.gradle.kts"
    target = g if g.is_file() else (gk if gk.is_file() else None)
    if target is None:
        return ["gradle: skip（无 android/build.gradle）"]

    raw = target.read_bytes()
    text = raw.decode("utf-8")
    newline = "\r\n" if "\r\n" in text else "\n"
    notes: list[str] = []

    # --- namespace ---
    if "namespace" in text:
        notes.append("namespace: ok（已有）")
    else:
        ns = namespace_for(pkg)
        line = (
            f'    namespace = "{ns}"'
            if target.suffix == ".kts"
            else f"    namespace '{ns}'"
        )
        match = GRADLE_ANDROID_BLOCK_RE.search(text)
        if not match:
            notes.append("namespace: FAIL（找不到 `android {` 块，需人工处理）")
        else:
            text = text[: match.end()] + newline + line + text[match.end():]
            notes.append(f"namespace: patched → {ns!r}")

    # --- compileSdkVersion 对齐 app ---
    text, sdk_change = align_compile_sdk(text)
    if sdk_change is None:
        notes.append(f"compileSdkVersion: ok（已 ≥ app 的 {app_compile_sdk()}）")
    else:
        notes.append(f"compileSdkVersion: patched → {sdk_change}")

    if not dry_run and text.encode("utf-8") != raw:
        target.write_bytes(text.encode("utf-8"))
    return notes


def patch_cargokit(pkg: Path, dry_run: bool) -> str:
    """缓存副本的 cargokit plugin.gradle 缺 Gradle 9 兼容时，用 vendored 版替换。"""
    target = pkg / "cargokit" / "gradle" / "plugin.gradle"
    if not target.is_file():
        return "cargokit: skip（无 cargokit）"

    text = target.read_text(encoding="utf-8", errors="replace")
    if CARGOKIT_PATCHED_MARKER in text:
        return "cargokit: ok（已含 Gradle 9 兼容）"

    if not VENDORED_CARGOKIT.is_file():
        return f"cargokit: FAIL（缺 vendored 文件 {VENDORED_CARGOKIT}）"

    if not dry_run:
        target.write_text(VENDORED_CARGOKIT.read_text(encoding="utf-8"), encoding="utf-8")
    return "cargokit: patched ← tools/vendor/cargokit_gradle9_plugin.gradle"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="只报告，不写盘")
    args = parser.parse_args()

    roots = pub_cache_roots()
    if not roots:
        print("FAIL: 找不到 pub cache（设 PUB_CACHE 或先跑 flutter pub get）")
        return 1

    pkgs = package_dirs()
    print(f"pub cache: {', '.join(str(r) for r in roots)}")
    if not pkgs:
        print("FAIL: cache 内没有目标包（先跑 flutter pub get）")
        return 1

    failures = 0
    for pkg in pkgs:
        label = f"{pkg.parent.name}/{pkg.name}"
        results = patch_gradle_module(pkg, args.dry_run)
        results.append(patch_cargokit(pkg, args.dry_run))
        for result in results:
            print(f"  {label}: {result}")
            if result.split(":", 1)[1].strip().startswith("FAIL"):
                failures += 1

    if args.dry_run:
        print("\n(--dry-run：未写盘)")
    if failures:
        print(f"\n失败 {failures} 项：需人工处理")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())