#!/usr/bin/env python3
"""Manage git hooks configuration for hermes-ui repository.

Why this exists:
CI pipelines in this repository enforce strict static analysis (failing even on
'info'-level lint warnings) and run tests. Finding these failures after pushing
wastes CI worker minutes and delays PRs. The local pre-push hook runs fast
formatting checks on changed files, repository-wide analysis, and impacted tests.

This utility manages git's `core.hooksPath` configuration so all developers and
agents can enable the pre-push gate idempotently.

Usage:
    python tools/install_git_hooks.py             # Install / ensure hooks are configured
    python tools/install_git_hooks.py --status    # Check current hook configuration
    python tools/install_git_hooks.py --uninstall # Unset core.hooksPath
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOOKS_DIR = ROOT / ".githooks"
PRE_PUSH_HOOK = HOOKS_DIR / "pre-push"


def is_git_repo() -> bool:
    """Check if current directory is inside a valid git repository."""
    try:
        res = subprocess.run(
            ["git", "rev-parse", "--is-inside-work-tree"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        return res.returncode == 0 and res.stdout.strip() == "true"
    except (FileNotFoundError, PermissionError):
        return False


def get_core_hooks_path() -> str | None:
    """Retrieve currently configured core.hooksPath, or None if not set."""
    res = subprocess.run(
        ["git", "config", "--get", "core.hooksPath"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if res.returncode == 0:
        val = res.stdout.strip()
        return val if val else None
    return None


def is_hook_executable(hook_path: Path) -> bool:
    """Check if the hook script has executable permissions."""
    if not hook_path.is_file():
        return False
    if os.name == "nt":
        # On Windows, check git index permissions if tracked, or os.access
        try:
            rel = hook_path.relative_to(ROOT).as_posix()
            res = subprocess.run(
                ["git", "ls-files", "--stage", rel],
                cwd=ROOT,
                capture_output=True,
                text=True,
                check=False,
            )
            if res.returncode == 0 and res.stdout.startswith("100755"):
                return True
        except Exception:
            pass
        return os.access(hook_path, os.X_OK)
    return os.access(hook_path, os.X_OK)


def ensure_executable(hook_path: Path) -> None:
    """Ensure executable bit is set on hook file."""
    if not hook_path.is_file():
        return
    try:
        mode = hook_path.stat().st_mode
        hook_path.chmod(mode | 0o755)
    except Exception:
        pass


def install_hooks() -> int:
    """Configure core.hooksPath to .githooks (idempotent)."""
    ensure_executable(PRE_PUSH_HOOK)
    res = subprocess.run(
        ["git", "config", "core.hooksPath", ".githooks"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if res.returncode != 0:
        print(f"[install_git_hooks] 错误: 设置 core.hooksPath 失败: {res.stderr.strip()}", file=sys.stderr)
        return 1

    print("[install_git_hooks] core.hooksPath 已配置为 .githooks")
    print(f"[install_git_hooks] pre-push 闸门脚本已就绪: {PRE_PUSH_HOOK.relative_to(ROOT).as_posix()}")
    return 0


def uninstall_hooks() -> int:
    """Unset core.hooksPath. Does not error if not set."""
    current = get_core_hooks_path()
    if current is None:
        print("[install_git_hooks] core.hooksPath 当前未设置，无需卸载。")
        return 0

    res = subprocess.run(
        ["git", "config", "--unset", "core.hooksPath"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    # git config --unset returns 5 if key did not exist
    if res.returncode != 0 and res.returncode != 5:
        print(f"[install_git_hooks] 错误: 卸载 core.hooksPath 失败: {res.stderr.strip()}", file=sys.stderr)
        return 1

    print(f"[install_git_hooks] 已清除 core.hooksPath（原配置: {current}）。")
    return 0


def check_status() -> int:
    """Print status of core.hooksPath and pre-push hook."""
    hooks_path = get_core_hooks_path()
    hook_exists = PRE_PUSH_HOOK.is_file()
    executable = is_hook_executable(PRE_PUSH_HOOK)

    print("[install_git_hooks] 当前 Git Hooks 状态:")
    print(f"  - core.hooksPath: {hooks_path if hooks_path is not None else '(未设置)'}")
    print(f"  - pre-push 脚本存在: {hook_exists} ({PRE_PUSH_HOOK.relative_to(ROOT).as_posix()})")
    print(f"  - pre-push 脚本可执行: {executable}")
    if hooks_path == ".githooks" and hook_exists:
        print("  - 状态: [已启用] 本地推前闸门处于激活状态。")
    else:
        print("  - 状态: [未启用] 请运行 python tools/install_git_hooks.py 安装。")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="管理 hermes-ui 的 Git Hooks（本地推前闸门配置工具）"
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "--status",
        action="store_true",
        help="检查当前 core.hooksPath 配置与 hook 脚本状态",
    )
    group.add_argument(
        "--uninstall",
        action="store_true",
        help="卸载 core.hooksPath 配置（还原为 git 默认 .git/hooks）",
    )
    args = parser.parse_args()

    # 校验 1: 必须在 git 仓库中运行
    if not is_git_repo():
        print("[install_git_hooks] 错误: 当前目录不是有效的 git 仓库或未检测到 git 命令。", file=sys.stderr)
        print("[install_git_hooks] 修复建议: 请在 hermes-ui 仓库根目录下执行，并确保系统已安装 git。", file=sys.stderr)
        return 1

    # 校验 2: .githooks/pre-push 必须存在
    if not PRE_PUSH_HOOK.is_file():
        print(f"[install_git_hooks] 错误: 预期的 hook 脚本缺失: {PRE_PUSH_HOOK}", file=sys.stderr)
        print("[install_git_hooks] 修复建议: 请确保仓库中的 .githooks/pre-push 文件已正确创建或检出。", file=sys.stderr)
        return 1

    if args.status:
        return check_status()
    elif args.uninstall:
        return uninstall_hooks()
    else:
        return install_hooks()


if __name__ == "__main__":
    sys.exit(main())
