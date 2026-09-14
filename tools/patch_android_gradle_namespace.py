#!/usr/bin/env python3
"""给缺少 namespace 的 Android 插件补 namespace（AGP 8+ 强制要求）。

背景
----
super_clipboard 0.1.7（同一插件家族的 irondash_engine_context 0.1.1 /
super_native_extensions 0.1.8）已停止维护，其 ``android/build.gradle`` 未声明
``namespace``，AGP 8+ 在**配置期**直接失败：

    A problem occurred configuring project ':irondash_engine_context'.
    > Namespace not specified. Specify a namespace in the module's build file:
      .../irondash_engine_context-0.1.1/android/build.gradle

本仓库的 APK 构建长期依赖一份**仓库外的手改 pub-cache**（2026-08-24 手工补上，
无脚本、无文档、无法复现）：本机 ``~/.pub-cache`` 里这两个包的 ``build.gradle``
mtime 比同包其它文件晚 10 小时即其痕迹。于是 CI 的 ``android-debug`` 一旦真正
执行（历史上被 analyze-test 连坐跳过 129 次）必然失败。

本脚本把这份补丁收敛为**幂等、可复现、入仓**的一步，CI 与本地共用。

namespace 取值
--------------
优先取 ``android/src/main/AndroidManifest.xml`` 的 ``package`` 属性（权威来源，
与本机手改值逐一核对一致），缺失时退回内置映射。

用法
----
    python tools/patch_android_gradle_namespace.py            # 补 pub cache（幂等）
    python tools/patch_android_gradle_namespace.py --dry-run  # 只报告

可删条件：super_clipboard 升到 0.9+（依赖 irondash 0.5+，自带 namespace）后，
删除本脚本、CI 中调用它的步骤，以及 AGENTS.md §8.2 的相关说明。
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

MANIFEST_PACKAGE_RE = re.compile(r'package\s*=\s*"([^"]+)"')
GRADLE_ANDROID_BLOCK_RE = re.compile(r"^(\s*android\s*\{\s*)$", re.MULTILINE)


def pub_cache_roots() -> list[Path]:
    """返回候选 pub cache 根目录（按优先级）。"""
    roots: list[Path] = []
    env = os.environ.get("PUB_CACHE")
    if env:
        roots.append(Path(env))
    home = Path.home()
    roots.append(home / ".pub-cache")
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
        match = MANIFEST_PACKAGE_RE.search(manifest.read_text(encoding="utf-8", errors="replace"))
        if match:
            return match.group(1)
    return TARGET_FALLBACK_NAMESPACE[pkg.name.rsplit("-", 1)[0]]


def patch_module(pkg: Path, dry_run: bool) -> str:
    """给单个包的 android/build.gradle(.kts) 补 namespace；返回结果描述。"""
    g = pkg / "android" / "build.gradle"
    gk = pkg / "android" / "build.gradle.kts"
    target = g if g.is_file() else (gk if gk.is_file() else None)
    if target is None:
        return "skip（无 android/build.gradle）"

    text = target.read_text(encoding="utf-8")
    if "namespace" in text:
        return "ok（已有 namespace）"

    ns = namespace_for(pkg)
    is_kts = target.suffix == ".kts"
    line = f'    namespace = "{ns}"' if is_kts else f"    namespace '{ns}'"

    match = GRADLE_ANDROID_BLOCK_RE.search(text)
    if not match:
        return "FAIL（找不到 `android {` 块，需人工处理）"

    patched = text[: match.end()] + "\n" + line + text[match.end() :]
    if not dry_run:
        target.write_text(patched, encoding="utf-8")
    return f'patched → namespace {ns!r}'


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

    failures = []
    for pkg in pkgs:
        result = patch_module(pkg, args.dry_run)
        print(f"  {pkg.parent.name}/{pkg.name}: {result}")
        if result.startswith("FAIL"):
            failures.append(pkg)

    if args.dry_run:
        print("\n(--dry-run：未写盘)")
    if failures:
        print(f"\n失败 {len(failures)} 个：需人工在 android/build.gradle 里声明 namespace")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())