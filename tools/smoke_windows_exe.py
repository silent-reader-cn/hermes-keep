#!/usr/bin/env python3
"""Windows 产物启动冒烟：把「构建绿、装上崩」变成 CI 判据。

为什么存在（.todo/active.md #133）
----------------------------------
CI 的 windows job 过去只 `flutter build windows --release` 就打包上传，**从不启动
产物**；而 #119 那类故障（插件注册期抛 Error、启动即 abort）恰恰只在运行时暴露：
构建全绿、装上就崩。于是流水线上没有任何一步能发现它。

判据为什么不是「存活 N 秒」
--------------------------
本机实测（2026-09-15）：安装版在跑时，新起的 exe 会在 1s 内**干净退出（exit 0）**
——那是单实例保护，不是崩溃。反过来「存活」也不等于健康（窗口没起来也可能活着）。
故判定改为看**退出码 + 崩溃特征**：

  * 跳出非 0                                  → 失败
  * 输出命中 abort / UnsatisfiedLinkError 等   → 失败
  * 干净退出 0                                → 通过（多半是单实例保护）
  * 观察窗结束仍存活                          → 通过，随后终止

另顺带校验产物完整性（exe 旁的 DLL 与 data/ 资产在不在）——比「进程能不能起」
更早一步给出根因。

本地已装版在跑时默认报 `SKIPPED` 且不算失败；CI 传 `--strict`，让 skipped 也算失败，
免得「其实没启动」被当成通过。

用法：
    python tools/smoke_windows_exe.py build/windows/x64/runner/Release/hermes_ui.exe
    python tools/smoke_windows_exe.py <exe> --seconds 25 --strict
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time
from pathlib import Path

# 崩溃特征：覆盖 native abort、Dart 未捕获异常、缺库、Windows 结构化异常。
CRASH_MARKERS = re.compile(
    r"(abort|UnsatisfiedLinkError|Access violation|EXCEPTION_|Failed to load|"
    r"Cannot open file|Unhandled exception|Dart_?Error|"
    r"CreateProcess failed|side-by-side configuration)",
    re.IGNORECASE,
)

# 产物完整性：缺一个就说明构建/打包链断了一环。
REQUIRED_SIBLINGS = ("flutter_windows.dll", "data", "data/flutter_assets")


def check_artifacts(exe: Path) -> list[str]:
    problems: list[str] = []
    if not exe.is_file():
        return [f"exe 不存在：{exe}"]
    if exe.stat().st_size == 0:
        problems.append(f"exe 体积为 0：{exe}")
    for rel in REQUIRED_SIBLINGS:
        if not (exe.parent / rel).exists():
            problems.append(f"产物缺失 {rel}（预期在 {exe.parent}）")
    return problems


def running_instances(image_name: str) -> list[str]:
    """同名进程 PID 列表（Windows 用 tasklist；其它平台无从判断，返回空）。"""
    if sys.platform != "win32":
        return []
    try:
        proc = subprocess.run(
            ["tasklist", "/FI", f"IMAGENAME eq {image_name}", "/NH"],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (OSError, subprocess.SubprocessError):
        return []
    text = proc.stdout or ""
    if "No tasks are running" in text:
        return []
    pids: list[str] = []
    for line in text.splitlines():
        match = re.match(r"^(\S+?)\s+(\d+)\s", line)
        if match and match.group(1).lower() == image_name.lower():
            pids.append(match.group(2))
    return pids


def _drain(proc: subprocess.Popen) -> str:
    try:
        out, _ = proc.communicate(timeout=15)
    except subprocess.TimeoutExpired:  # 理论上不会：进程已退出或已被 kill
        proc.kill()
        out, _ = proc.communicate()
    return out or ""


def main() -> int:
    parser = argparse.ArgumentParser(description="启动 Windows 产物并判定是否崩溃")
    parser.add_argument("exe", help="被测 exe 路径")
    parser.add_argument("--seconds", type=float, default=20.0, help="观察窗秒数（默认 20）")
    parser.add_argument("--strict", action="store_true", help="SKIPPED 也判失败（CI 用）")
    args = parser.parse_args()

    exe = Path(args.exe).resolve()
    problems = check_artifacts(exe)
    if problems:
        for problem in problems:
            print(f"FAIL: {problem}")
        return 1
    print(f"产物完整：{exe}（{exe.stat().st_size} B）")

    others = running_instances(exe.name)
    if others:
        message = (
            f"another instance of {exe.name} is already running "
            f"(pids={','.join(others)}) —— 单实例保护会让新实例立刻干净退出，本判据无法取证"
        )
        print(("FAIL: " if args.strict else "SKIPPED: ") + message)
        return 1 if args.strict else 0

    try:
        proc = subprocess.Popen(  # noqa: S603 - 被测目标由调用方显式给出
            [str(exe)],
            cwd=str(exe.parent),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
        )
    except OSError as exc:
        # 「起不来」和「起来后崩」是同一类交付缺陷（缺 DLL、side-by-side 配置错、
        # 需要提升权限…），必须报失败而不是抛裸异常——否则 CI 里只看到 traceback。
        print(f"FAIL: 无法启动 {exe.name}：{exc}")
        return 1

    deadline = time.monotonic() + args.seconds
    exited = False
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            exited = True
            break
        time.sleep(0.25)

    if exited:
        output = _drain(proc)
        print(f"进程在 {args.seconds:.0f}s 窗内退出：exit={proc.returncode}")
        alive = False
    else:
        proc.terminate()
        output = _drain(proc)
        print(f"进程存活满 {args.seconds:.0f}s（已终止，属正常：托盘常驻型应用）")
        alive = True

    if output.strip():
        print("--- 进程输出 ---")
        print(output.strip()[-2000:])

    hit = CRASH_MARKERS.search(output)
    if hit:
        print(f"FAIL: 进程输出命中崩溃特征 {hit.group(0)!r}")
        return 1

    if alive:
        print("PASS: 启动后持续存活且无崩溃输出")
        return 0

    if proc.returncode != 0:
        print(f"FAIL: 非零退出 exit={proc.returncode}")
        return 1

    print("PASS: 干净退出（exit 0，通常是单实例保护）且无崩溃输出")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
