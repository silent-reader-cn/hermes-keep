#!/usr/bin/env python3
"""APK 原生库护栏：确认关键 .so 真的进了包（缺库时构建不会报错，线上却是静默连坐）。

背景（#119，2026-09-14）
----------------------
``super_native_extensions`` 是 Rust/cargokit 插件，它的 Java 类静态块里写着
``System.loadLibrary("super_native_extensions")``。这个 .so 一旦没被打进 APK：

* 构造插件实例时抛 ``UnsatisfiedLinkError``（**Error**）；
* 而 ``GeneratedPluginRegistrant`` 逐插件只 ``catch (Exception)`` → 整条注册循环
  自该插件起中断，**其后所有插件静默失联**（本仓为 url_launcher / wakelock_plus /
  workmanager）；
* 引擎又是用反射调用注册器并 catch Exception 的（``GeneratedPluginRegistrar``
  的 ``InvocationTargetException`` 被吞），所以**应用不闪退**，只在 logcat 留一行
  「Received exception while registering」。

用户侧看到的是「某些功能莫名不可用」：打不开外部链接、后台保活报 channel-error。
当年为了这条线索误修了 WorkManager 初始化（#110），白花一轮——所以把「产物在不在」
固化成可执行的检查，本地发布与 CI 共用。

用法
----
    python tools/verify_apk_native_libs.py <apk 路径> [--abi arm64-v8a]

退出码 0 = 全部就位；1 = 有缺失（会打印缺哪个库、缺哪个 ABI，以及它来自哪个插件）。
"""
from __future__ import annotations

import argparse
import sys
import zipfile
from pathlib import Path

# 必须出现在 APK 里的原生库（cargokit Rust 插件产物）。
# 新增同类插件（Rust/C++，静态块 loadLibrary）时追加到这张表。
REQUIRED_NATIVE_LIBS: dict[str, str] = {
    "libsuper_native_extensions.so": "super_native_extensions（super_clipboard/irondash 家族）",
}


def apk_native_libs(apk: Path) -> dict[str, set[str]]:
    """返回 {库名: {ABI, ...}}。"""
    found: dict[str, set[str]] = {}
    with zipfile.ZipFile(apk) as zf:
        for name in zf.namelist():
            parts = name.split("/")
            # lib/<abi>/<libname>
            if len(parts) == 3 and parts[0] == "lib":
                found.setdefault(parts[2], set()).add(parts[1])
    return found


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("apk", type=Path, help="待检查的 APK 路径")
    parser.add_argument(
        "--abi",
        default=None,
        help="要求该 ABI 必须有（默认：任一 ABI 有即可）",
    )
    args = parser.parse_args()

    if not args.apk.is_file():
        print(f"FAIL: APK 不存在 → {args.apk}")
        return 1

    libs = apk_native_libs(args.apk)
    missing: list[str] = []
    for lib, owner in REQUIRED_NATIVE_LIBS.items():
        abis = libs.get(lib, set())
        if args.abi:
            ok = args.abi in abis
        else:
            ok = bool(abis)
        if ok:
            print(f"  ok    {lib}  ← {owner}（ABI: {', '.join(sorted(abis)) or '—'}）")
        else:
            detail = f"应有 ABI {args.abi}" if args.abi else "任何 ABI 都没有"
            print(f"  MISS  {lib}  ← {owner}（{detail}）")
            missing.append(lib)

    # 顺带列出全部原生库，便于人工核对（不参与判定）。
    print(f"\nAPK 内原生库共 {len(libs)} 个：")
    for lib in sorted(libs):
        print(f"  {lib}  [{', '.join(sorted(libs[lib]))}]")

    if missing:
        print(
            f"\nFAIL: 缺 {len(missing)} 个必需原生库 → {' '.join(missing)}\n"
            "  缺库不会让构建失败，但会让该插件注册期抛 Error 并截断整条"
            " GeneratedPluginRegistrant（其后插件静默失联、应用不闪退）。\n"
            "  排查方向：cargokit 的 jniLibs 接线是否被 AGP 变体源集采纳"
            "（见 android/app/build.gradle.kts 的 #119 说明）。"
        )
        return 1

    print("\nOK: 必需原生库全部就位。")
    return 0


if __name__ == "__main__":
    sys.exit(main())