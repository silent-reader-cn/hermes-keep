#!/usr/bin/env python3
"""Synchronize and bump Hermes UI version across pubspec.yaml and version_info.dart.

Usage:
  python tools/bump_version.py 0.1.52         # build number = current + 1
  python tools/bump_version.py 0.1.52+60      # explicit build number
  python tools/bump_version.py --dry-run 0.1.52
  python tools/bump_version.py --check        # verify consistency (for CI)
  python tools/bump_version.py --no-verify 0.1.52
  python tools/bump_version.py --force 0.1.50 # allow downgrade
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


PUBSPEC_REL = Path("pubspec.yaml")
VERSION_INFO_REL = Path("lib/core/update/version_info.dart")
TEST_REL = Path("test/core/update/version_info_test.dart")

# Regex to match version line in pubspec.yaml: e.g. "version: 0.1.51+57"
RE_PUBSPEC_VERSION = re.compile(
    r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?",
    re.MULTILINE,
)

# Regex to match appVersion constant in lib/core/update/version_info.dart
RE_DART_APP_VERSION = re.compile(
    r"^const\s+String\s+appVersion\s*=\s*'([0-9]+\.[0-9]+\.[0-9]+)';",
    re.MULTILINE,
)

# Regex to parse input version argument
RE_INPUT_VERSION = re.compile(
    r"^([0-9]+)\.([0-9]+)\.([0-9]+)(?:\+([0-9]+))?$",
)


def parse_semver(v_str: str) -> tuple[int, int, int]:
    parts = v_str.strip().split(".")
    if len(parts) != 3:
        raise ValueError(f"Invalid semver: {v_str}")
    return int(parts[0]), int(parts[1]), int(parts[2])


def detect_newline(content: str) -> str:
    if "\r\n" in content:
        return "\r\n"
    return "\n"


def atomic_write(path: Path, content: str, newline: str) -> None:
    temp_path = path.with_suffix(path.suffix + ".tmp")
    try:
        with open(temp_path, "w", encoding="utf-8", newline=newline) as f:
            f.write(content)
        os.replace(temp_path, path)
    except Exception:
        if temp_path.exists():
            try:
                temp_path.unlink()
            except OSError:
                pass
        raise


def resolve_root(custom_root: str | None) -> Path:
    if custom_root:
        return Path(custom_root).resolve()
    # If pubspec.yaml exists in current working directory, use it
    if (Path.cwd() / PUBSPEC_REL).is_file():
        return Path.cwd().resolve()
    # Otherwise fallback to repository root based on script location
    return Path(__file__).resolve().parent.parent


def read_current_versions(root: Path) -> tuple[str, str, int | None, str, str, str]:
    """Read versions from pubspec.yaml and version_info.dart.

    Returns:
      (pubspec_content, pubspec_semver, pubspec_build, pubspec_full,
       dart_content, dart_semver)
    """
    pubspec_path = root / PUBSPEC_REL
    dart_path = root / VERSION_INFO_REL

    if not pubspec_path.is_file():
        print(f"[ERROR] pubspec.yaml not found at: {pubspec_path}", file=sys.stderr)
        sys.exit(1)

    if not dart_path.is_file():
        print(f"[ERROR] version_info.dart not found at: {dart_path}", file=sys.stderr)
        sys.exit(1)

    pubspec_content = pubspec_path.read_text(encoding="utf-8")
    dart_content = dart_path.read_text(encoding="utf-8")

    m_pubspec = RE_PUBSPEC_VERSION.search(pubspec_content)
    if not m_pubspec:
        print(
            f"[ERROR] Failed to parse '^version:' line from {pubspec_path}",
            file=sys.stderr,
        )
        sys.exit(1)

    pubspec_semver = m_pubspec.group(1)
    pubspec_build = int(m_pubspec.group(2)) if m_pubspec.group(2) else None
    pubspec_full = m_pubspec.group(0).split(":", 1)[1].strip()

    m_dart = RE_DART_APP_VERSION.search(dart_content)
    if not m_dart:
        print(
            f"[ERROR] Failed to parse \"const String appVersion = '...';\" from {dart_path}",
            file=sys.stderr,
        )
        sys.exit(1)

    dart_semver = m_dart.group(1)

    return (
        pubspec_content,
        pubspec_semver,
        pubspec_build,
        pubspec_full,
        dart_content,
        dart_semver,
    )


def run_check(root: Path) -> int:
    pubspec_path = root / PUBSPEC_REL
    dart_path = root / VERSION_INFO_REL

    if not pubspec_path.is_file():
        print(f"[ERROR] pubspec.yaml not found at: {pubspec_path}", file=sys.stderr)
        return 1

    if not dart_path.is_file():
        print(f"[ERROR] version_info.dart not found at: {dart_path}", file=sys.stderr)
        return 1

    pubspec_content = pubspec_path.read_text(encoding="utf-8")
    m_pubspec = RE_PUBSPEC_VERSION.search(pubspec_content)
    if not m_pubspec:
        print(
            f"[ERROR] Failed to parse '^version:' line from {pubspec_path}",
            file=sys.stderr,
        )
        return 1

    dart_content = dart_path.read_text(encoding="utf-8")
    m_dart = RE_DART_APP_VERSION.search(dart_content)
    if not m_dart:
        print(
            f"[ERROR] Failed to parse \"const String appVersion = '...';\" from {dart_path}",
            file=sys.stderr,
        )
        return 1

    pubspec_semver = m_pubspec.group(1)
    pubspec_full = m_pubspec.group(0).split(":", 1)[1].strip()
    dart_semver = m_dart.group(1)

    if pubspec_semver == dart_semver:
        print(
            f"[OK] Versions are consistent: pubspec.yaml ({pubspec_full}) == "
            f"version_info.dart ({dart_semver})"
        )
        return 0
    else:
        print("[ERROR] Version mismatch detected!", file=sys.stderr)
        print(
            f"  pubspec.yaml:                       {pubspec_semver} (raw: {pubspec_full})",
            file=sys.stderr,
        )
        print(
            f"  lib/core/update/version_info.dart:  {dart_semver}",
            file=sys.stderr,
        )
        print("\nTo fix, run:", file=sys.stderr)
        print(f"  python tools/bump_version.py {pubspec_full} --force", file=sys.stderr)
        return 1


def resolve_flutter_bin() -> str | None:
    """定位 flutter 可执行文件：`FLUTTER_BIN` > PATH > 常见安装位置。

    刻意**不**把某个人的本地封装脚本（如 `C:/tmp/f.bat`）写成默认值：这个脚本要在
    别人的机器与 CI 上跑（CI 的 guard job 走 `--check` 不需要它，但本地 bump 需要），
    写死绝对路径就会在别处静默失效。
    """
    env_bin = os.environ.get("FLUTTER_BIN")
    if env_bin:
        return env_bin
    for name in ("flutter", "flutter.bat"):
        found = shutil.which(name)
        if found:
            return found
    home = Path.home()
    candidates = (
        home / "flutter" / "bin" / "flutter.bat",
        home / "flutter" / "bin" / "flutter",
        Path("C:/tmp/f.bat"),
    )
    for cand in candidates:
        if cand.is_file():
            return str(cand)
    return None


def main() -> int:
    parser = argparse.ArgumentParser(
        description="One-step version bumper and consistency validator for Hermes UI.",
    )
    parser.add_argument(
        "version",
        nargs="?",
        help="Target version in X.Y.Z or X.Y.Z+BUILD format (e.g. 0.1.52 or 0.1.52+60)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Verify consistency between pubspec.yaml and version_info.dart (exit 0 if consistent, 1 otherwise)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without writing files",
    )
    parser.add_argument(
        "--no-verify",
        action="store_true",
        help="Skip running flutter test verification after bumping",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Allow version downgrade or same version without increasing",
    )
    parser.add_argument(
        "--root",
        type=str,
        default=None,
        help="Custom project root directory (defaults to repository root)",
    )

    args = parser.parse_args()
    root = resolve_root(args.root)

    if args.check:
        return run_check(root)

    if not args.version:
        parser.print_help(sys.stderr)
        print("\n[ERROR] Target version is required unless --check is specified.", file=sys.stderr)
        return 1

    # Parse input target version
    m_input = RE_INPUT_VERSION.match(args.version.strip())
    if not m_input:
        print(
            f"[ERROR] Invalid version format: '{args.version}'. Expected X.Y.Z or X.Y.Z+BUILD (e.g. 0.1.52 or 0.1.52+60)",
            file=sys.stderr,
        )
        return 1

    target_semver = f"{m_input.group(1)}.{m_input.group(2)}.{m_input.group(3)}"
    target_build = int(m_input.group(4)) if m_input.group(4) else None

    # Read current state
    (
        pubspec_content,
        cur_pubspec_semver,
        cur_pubspec_build,
        cur_pubspec_full,
        dart_content,
        cur_dart_semver,
    ) = read_current_versions(root)

    # Determine final new build number
    if target_build is not None:
        new_build = target_build
    else:
        new_build = (cur_pubspec_build + 1) if cur_pubspec_build is not None else 1

    new_pubspec_full = f"{target_semver}+{new_build}"
    new_dart_semver = target_semver

    # Compare versions for downgrade check
    cur_tuple = parse_semver(cur_pubspec_semver)
    target_tuple = parse_semver(target_semver)

    if not args.force:
        if target_tuple < cur_tuple:
            print(
                f"[ERROR] New version '{target_semver}' is lower than current '{cur_pubspec_semver}'.",
                file=sys.stderr,
            )
            print("Use --force to allow version downgrade.", file=sys.stderr)
            return 1
        elif target_tuple == cur_tuple:
            # Same semver: check if build number increases or if build was not specified
            if target_build is None:
                print(
                    f"[ERROR] New version '{target_semver}' is identical to current '{cur_pubspec_semver}'.",
                    file=sys.stderr,
                )
                print(
                    "To bump build number only, specify build explicitly (e.g. "
                    f"{target_semver}+{new_build}) or use --force.",
                    file=sys.stderr,
                )
                return 1
            elif cur_pubspec_build is not None and target_build <= cur_pubspec_build:
                print(
                    f"[ERROR] New version '{target_semver}+{target_build}' <= current '{cur_pubspec_full}'.",
                    file=sys.stderr,
                )
                print("Use --force to allow override.", file=sys.stderr)
                return 1

    # Extract exact before lines
    pubspec_line_match = re.search(r"^version:\s*\S+.*$", pubspec_content, re.MULTILINE)
    pubspec_before_line = pubspec_line_match.group(0) if pubspec_line_match else f"version: {cur_pubspec_full}"
    pubspec_after_line = f"version: {new_pubspec_full}"

    dart_line_match = re.search(r"^const\s+String\s+appVersion\s*=\s*'[^']+';", dart_content, re.MULTILINE)
    dart_before_line = dart_line_match.group(0) if dart_line_match else f"const String appVersion = '{cur_dart_semver}';"
    dart_after_line = f"const String appVersion = '{new_dart_semver}';"

    # Compute updated contents
    new_pubspec_content = re.sub(
        r"^(version:\s*)\S+",
        rf"\g<1>{new_pubspec_full}",
        pubspec_content,
        count=1,
        flags=re.MULTILINE,
    )

    new_dart_content = re.sub(
        r"^(const\s+String\s+appVersion\s*=\s*')[^']+(';)",
        rf"\g<1>{new_dart_semver}\g<2>",
        dart_content,
        count=1,
        flags=re.MULTILINE,
    )

    # Print before / after comparison
    mode_tag = "[DRY-RUN] " if args.dry_run else ""
    print("=" * 60)
    print(f"{mode_tag}Version Bump Summary:")
    print("-" * 60)
    print("pubspec.yaml:")
    print(f"  - {pubspec_before_line}")
    print(f"  + {pubspec_after_line}")
    print("lib/core/update/version_info.dart:")
    print(f"  - {dart_before_line}")
    print(f"  + {dart_after_line}")
    print("=" * 60)

    if args.dry_run:
        print("[DRY-RUN] No files were modified.")
        return 0

    # Write files atomically
    pubspec_path = root / PUBSPEC_REL
    dart_path = root / VERSION_INFO_REL

    pubspec_nl = detect_newline(pubspec_content)
    dart_nl = detect_newline(dart_content)

    atomic_write(pubspec_path, new_pubspec_content, pubspec_nl)
    atomic_write(dart_path, new_dart_content, dart_nl)
    print("[OK] Files updated successfully.")

    # Verification test
    if not args.no_verify:
        flutter_bin = os.environ.get("FLUTTER_BIN", "C:/tmp/f.bat")
        test_file = TEST_REL.as_posix()
        cmd = [flutter_bin, "test", test_file]
        print(f"[VERIFY] Running verification test: {' '.join(cmd)}")
        result = subprocess.run(cmd, cwd=root)
        if result.returncode != 0:
            print(
                "\n[ERROR] Verification test failed! Files have been modified.\n"
                f"Please manually fix or run:\n"
                f"  git restore {PUBSPEC_REL} {VERSION_INFO_REL}",
                file=sys.stderr,
            )
            return 1
        print("[OK] Verification test passed.")

    # Next steps output
    print("\nNext steps:")
    print(f"  git add {PUBSPEC_REL} {VERSION_INFO_REL}")
    print(f'  git commit -m "chore(release): bump to {target_semver}"')

    return 0


if __name__ == "__main__":
    sys.exit(main())
