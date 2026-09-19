#!/usr/bin/env python3
"""One-step release automation for Hermes UI.

Pre-flight checks -> git tag & push -> gh release create -> verify (read-back 3 items).

Usage:
  python tools/release.py --apk <path> --exe <path>          # dry-run by default
  python tools/release.py --apk <path> --exe <path> --yes    # execute release
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path


DEFAULT_REPO = "silent-reader-cn/hermes-keep"
PUBSPEC_REL = Path("pubspec.yaml")
VERSION_INFO_REL = Path("lib/core/update/version_info.dart")

RE_PUBSPEC_VERSION = re.compile(
    r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?",
    re.MULTILINE,
)
RE_DART_APP_VERSION = re.compile(
    r"^const\s+String\s+appVersion\s*=\s*'([0-9]+\.[0-9]+\.[0-9]+)';",
    re.MULTILINE,
)


def resolve_root(custom_root: str | None) -> Path:
    if custom_root:
        return Path(custom_root).resolve()
    if (Path.cwd() / PUBSPEC_REL).is_file():
        return Path.cwd().resolve()
    return Path(__file__).resolve().parent.parent


def to_native_posix(path: Path | str) -> str:
    """Format path with forward slashes for native tools on Windows/MSYS."""
    return str(Path(path).resolve()).replace("\\", "/")


def run_cmd(
    cmd: list[str],
    cwd: Path | None = None,
    capture: bool = True,
    check: bool = False,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=cwd,
        capture_output=capture,
        text=True,
        check=check,
    )


def check_version_consistency(root: Path) -> tuple[bool, str, str]:
    """Check consistency between pubspec.yaml and version_info.dart.

    Returns: (is_ok, app_version, error_detail)
    """
    pubspec_path = root / PUBSPEC_REL
    dart_path = root / VERSION_INFO_REL

    if not pubspec_path.is_file():
        return False, "", f"Missing {pubspec_path}"
    if not dart_path.is_file():
        return False, "", f"Missing {dart_path}"

    pubspec_text = pubspec_path.read_text(encoding="utf-8")
    dart_text = dart_path.read_text(encoding="utf-8")

    m_pub = RE_PUBSPEC_VERSION.search(pubspec_text)
    m_dart = RE_DART_APP_VERSION.search(dart_text)

    if not m_pub:
        return False, "", f"Failed to parse '^version:' from {pubspec_path}"
    if not m_dart:
        return False, "", f"Failed to parse 'const String appVersion' from {dart_path}"

    pub_ver = m_pub.group(1)
    dart_ver = m_dart.group(1)

    if pub_ver != dart_ver:
        return (
            False,
            dart_ver,
            f"pubspec.yaml ({pub_ver}) != version_info.dart ({dart_ver})",
        )

    return True, dart_ver, ""


def query_latest_release_tag(repo: str) -> str | None:
    """Query GitHub API for the latest release tag name using curl or urllib."""
    url = f"https://api.github.com/repos/{repo}/releases/latest"
    curl_bin = shutil.which("curl.exe") or shutil.which("curl")

    if curl_bin:
        try:
            res = run_cmd([curl_bin, "-s", "--connect-timeout", "10", url])
            if res.returncode == 0 and res.stdout.strip():
                data = json.loads(res.stdout)
                return data.get("tag_name")
        except Exception:
            pass

    # Fallback to urllib
    try:
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "hermes-release-tool", "Accept": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data.get("tag_name")
    except Exception:
        return None


def main() -> int:
    parser = argparse.ArgumentParser(
        description="One-step release automation for Hermes UI.",
    )
    parser.add_argument(
        "--apk",
        required=True,
        type=str,
        help="Path to release APK (must match *-app-release.apk pattern)",
    )
    parser.add_argument(
        "--exe",
        required=True,
        type=str,
        help="Path to Windows installer EXE (must match *-setup.exe pattern)",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="Actually execute destructive actions (default is dry-run)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Explicitly request dry-run mode (default behavior)",
    )
    parser.add_argument(
        "--title",
        type=str,
        default=None,
        help="Release title (defaults to 'Hermes UI v<version>')",
    )
    parser.add_argument(
        "--notes",
        type=str,
        default=None,
        help="Release notes markdown content",
    )
    parser.add_argument(
        "--notes-file",
        type=str,
        default=None,
        help="Path to file containing release notes",
    )
    parser.add_argument(
        "--repo",
        type=str,
        default=DEFAULT_REPO,
        help=f"GitHub repository (default: {DEFAULT_REPO})",
    )
    parser.add_argument(
        "--root",
        type=str,
        default=None,
        help="Custom project root directory (defaults to repository root)",
    )
    parser.add_argument(
        "--skip-clean-check",
        action="store_true",
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--skip-branch-check",
        action="store_true",
        help=argparse.SUPPRESS,
    )

    args = parser.parse_args()
    root = resolve_root(args.root)
    is_dry_run = not args.yes

    apk_path = Path(args.apk)
    exe_path = Path(args.exe)

    # --------------------------------------------------------------------------
    # Pre-flight Checks (Collect all failures, execute nothing if any fail)
    # --------------------------------------------------------------------------
    errors: list[str] = []

    # 1. Version consistency check
    is_consistent, app_ver, ver_err = check_version_consistency(root)
    if not is_consistent:
        errors.append(f"Version consistency check failed: {ver_err}")
    tag_name = f"v{app_ver}" if app_ver else ""

    # 2. Working tree cleanliness
    if not args.skip_clean_check:
        res_status = run_cmd(["git", "status", "--porcelain"], cwd=root)
        if res_status.returncode != 0:
            errors.append(f"Failed to check git status: {res_status.stderr.strip()}")
        elif res_status.stdout.strip():
            errors.append(
                "Git working directory is not clean (uncommitted or untracked changes present)"
            )

    # 3. Branch is main and in sync with origin/main
    if not args.skip_branch_check:
        res_branch = run_cmd(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=root)
        cur_branch = res_branch.stdout.strip()
        if cur_branch != "main":
            errors.append(f"Current branch is '{cur_branch}', expected 'main'")
        else:
            res_head = run_cmd(["git", "rev-parse", "HEAD"], cwd=root)
            res_origin = run_cmd(["git", "rev-parse", "origin/main"], cwd=root)
            if res_head.returncode != 0 or res_origin.returncode != 0:
                errors.append("Failed to resolve HEAD or origin/main commit hash")
            elif res_head.stdout.strip() != res_origin.stdout.strip():
                errors.append(
                    f"Branch 'main' is not in sync with 'origin/main' "
                    f"({res_head.stdout.strip()[:8]} vs {res_origin.stdout.strip()[:8]})"
                )

    # 4. Local tag does not exist
    if tag_name:
        res_tag = run_cmd(["git", "tag", "-l", tag_name], cwd=root)
        if res_tag.returncode == 0 and tag_name in res_tag.stdout.split():
            errors.append(f"Git tag '{tag_name}' already exists locally")

    # 5. Asset existence and size
    if not apk_path.is_file():
        errors.append(f"APK asset not found or not a file: {apk_path}")
    else:
        apk_size = apk_path.stat().st_size
        if apk_size <= 0:
            errors.append(f"APK asset is empty (size = {apk_size} bytes): {apk_path}")

    if not exe_path.is_file():
        errors.append(f"EXE asset not found or not a file: {exe_path}")
    else:
        exe_size = exe_path.stat().st_size
        if exe_size <= 0:
            errors.append(f"EXE asset is empty (size = {exe_size} bytes): {exe_path}")

    # 6. Asset naming conventions required by findPlatformAsset
    apk_name = apk_path.name.lower()
    if not (apk_name.endswith(".apk") and "app-release" in apk_name):
        errors.append(
            f"APK filename '{apk_path.name}' does not match pattern '*-app-release.apk' "
            "(required by in-app updater findPlatformAsset)"
        )

    exe_name = exe_path.name.lower()
    if not (exe_name.endswith("-setup.exe") or (exe_name.endswith(".exe") and "setup" in exe_name)):
        errors.append(
            f"EXE filename '{exe_path.name}' does not match pattern '*-setup.exe' "
            "(required by in-app updater findPlatformAsset)"
        )

    # 7. gh CLI authentication
    res_auth = run_cmd(["gh", "auth", "status"])
    if res_auth.returncode != 0:
        errors.append(
            f"'gh auth status' failed: GitHub CLI is not authenticated.\n{res_auth.stderr.strip()}"
        )

    # 8. GitHub Release does not exist for this tag
    if tag_name:
        res_view = run_cmd(["gh", "release", "view", tag_name, "--repo", args.repo])
        if res_view.returncode == 0:
            errors.append(f"GitHub Release for '{tag_name}' already exists on {args.repo}")

    # If any pre-flight check failed, abort immediately with no side effects
    if errors:
        print("=" * 60, file=sys.stderr)
        print("[ERROR] Pre-flight validation failed:", file=sys.stderr)
        print("-" * 60, file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        print("=" * 60, file=sys.stderr)
        print("Release aborted. No git tags or GitHub releases were created.", file=sys.stderr)
        return 1

    # --------------------------------------------------------------------------
    # Prepare details
    # --------------------------------------------------------------------------
    apk_native_path = to_native_posix(apk_path)
    exe_native_path = to_native_posix(exe_path)
    apk_byte_size = apk_path.stat().st_size
    exe_byte_size = exe_path.stat().st_size
    title = args.title or f"Hermes UI {tag_name}"

    if args.notes:
        notes_content = args.notes
    elif args.notes_file:
        notes_content = Path(args.notes_file).read_text(encoding="utf-8")
    else:
        notes_content = (
            f"## Hermes UI {tag_name}\n\n"
            f"### 安装\n"
            f"- **Android**：`{apk_path.name}` ({apk_byte_size:,} bytes)\n"
            f"- **Windows**：`{exe_path.name}` ({exe_byte_size:,} bytes)\n"
        )

    # --------------------------------------------------------------------------
    # Dry-run Mode (Default)
    # --------------------------------------------------------------------------
    if is_dry_run:
        print("=" * 60)
        print("[DRY-RUN] Pre-flight validation PASSED!")
        print("-" * 60)
        print(f"Target Tag:   {tag_name} (version: {app_ver})")
        print(f"Repository:   {args.repo}")
        print(f"Release Title: {title}")
        print(f"Assets:")
        print(f"  - Android: {apk_native_path} ({apk_byte_size:,} bytes)")
        print(f"  - Windows: {exe_native_path} ({exe_byte_size:,} bytes)")
        print("-" * 60)
        print("The following operations WOULD be executed (run with --yes to execute):")
        print(f"  1. git tag -a {tag_name} -m \"Hermes UI {tag_name}\"")
        print(f"  2. git push origin {tag_name}")
        print(
            f"  3. gh release create {tag_name} \\\n"
            f"       \"{apk_native_path}\" \\\n"
            f"       \"{exe_native_path}\" \\\n"
            f"       --repo {args.repo} \\\n"
            f"       --title \"{title}\" \\\n"
            f"       --notes \"...\""
        )
        print("  4. Verification (read-back 3 items):")
        print(f"     - gh release view {tag_name} --repo {args.repo} --json assets")
        print("       (verify each asset state=uploaded and byte-for-byte size matches local file)")
        print(f"     - gh release list --repo {args.repo}")
        print(f"       (verify {tag_name} is marked 'Latest')")
        print(f"     - curl -s https://api.github.com/repos/{args.repo}/releases/latest")
        print(f"       (verify tag_name == {tag_name})")
        print("=" * 60)
        print("[DRY-RUN] Completed. No remote actions taken.")
        return 0

    # --------------------------------------------------------------------------
    # Destructive Execution (--yes)
    # --------------------------------------------------------------------------
    print("=" * 60)
    print(f"[RELEASE] Starting release execution for {tag_name}...")
    print("=" * 60)

    # Step 1: git tag & push
    tag_cmd = ["git", "tag", "-a", tag_name, "-m", f"Hermes UI {tag_name}"]
    print(f"[EXEC] {' '.join(tag_cmd)}")
    res_tag = run_cmd(tag_cmd, cwd=root)
    if res_tag.returncode != 0:
        print(f"[ERROR] Failed to create git tag: {res_tag.stderr.strip()}", file=sys.stderr)
        return 1

    push_cmd = ["git", "push", "origin", tag_name]
    print(f"[EXEC] {' '.join(push_cmd)}")
    res_push = run_cmd(push_cmd, cwd=root)
    if res_push.returncode != 0:
        print(f"[ERROR] Failed to push git tag: {res_push.stderr.strip()}", file=sys.stderr)
        return 1

    # Step 2: gh release create
    gh_cmd = [
        "gh",
        "release",
        "create",
        tag_name,
        apk_native_path,
        exe_native_path,
        "--repo",
        args.repo,
        "--title",
        title,
        "--notes",
        notes_content,
    ]
    print(f"[EXEC] gh release create {tag_name} {apk_native_path} {exe_native_path} --repo {args.repo} --title \"{title}\"")
    res_gh = run_cmd(gh_cmd, cwd=root)
    if res_gh.returncode != 0:
        print(f"[ERROR] 'gh release create' failed: {res_gh.stderr.strip()}", file=sys.stderr)
        return 1

    print("[OK] Release created successfully. Beginning read-back verification...")

    # Step 3: Read-back Verification (3 items, with retries)
    checklist: dict[str, tuple[bool, str]] = {
        "assets": (False, "Pending verification"),
        "latest_list": (False, "Pending verification"),
        "latest_api": (False, "Pending verification"),
    }

    max_attempts = 5
    for attempt in range(1, max_attempts + 1):
        # 3.1 Verify assets
        if not checklist["assets"][0]:
            view_res = run_cmd(
                ["gh", "release", "view", tag_name, "--repo", args.repo, "--json", "assets"]
            )
            if view_res.returncode == 0:
                try:
                    payload = json.loads(view_res.stdout)
                    remote_assets = {a.get("name"): a for a in payload.get("assets", [])}
                    apk_rem = remote_assets.get(apk_path.name)
                    exe_rem = remote_assets.get(exe_path.name)

                    apk_ok = (
                        apk_rem is not None
                        and apk_rem.get("state") == "uploaded"
                        and apk_rem.get("size") == apk_byte_size
                    )
                    exe_ok = (
                        exe_rem is not None
                        and exe_rem.get("state") == "uploaded"
                        and exe_rem.get("size") == exe_byte_size
                    )

                    if apk_ok and exe_ok:
                        detail = (
                            f"{apk_path.name} ({apk_byte_size} B, state=uploaded), "
                            f"{exe_path.name} ({exe_byte_size} B, state=uploaded)"
                        )
                        checklist["assets"] = (True, detail)
                except Exception as ex:
                    checklist["assets"] = (False, f"JSON parse error: {ex}")

        # 3.2 Verify gh release list has 'Latest'
        if not checklist["latest_list"][0]:
            list_res = run_cmd(["gh", "release", "list", "--repo", args.repo])
            if list_res.returncode == 0:
                for line in list_res.stdout.splitlines():
                    if tag_name in line and "Latest" in line:
                        checklist["latest_list"] = (True, f"Tag {tag_name} is marked Latest")
                        break

        # 3.3 Verify /releases/latest endpoint tag_name
        if not checklist["latest_api"][0]:
            latest_tag = query_latest_release_tag(args.repo)
            if latest_tag == tag_name:
                checklist["latest_api"] = (True, f"Endpoint tag_name == {tag_name}")

        # Check if all 3 passed
        if all(v[0] for v in checklist.values()):
            break

        if attempt < max_attempts:
            time.sleep(2)

    # Print Verification Report
    print("=" * 60)
    print("Release Read-back Verification Checklist:")
    print("-" * 60)
    for key, (ok, msg) in checklist.items():
        status_tag = "[OK] " if ok else "[FAIL]"
        label = {
            "assets": "Assets uploaded & byte-for-byte size verified",
            "latest_list": f"Release marked Latest in 'gh release list'",
            "latest_api": f"API endpoint {args.repo}/releases/latest",
        }.get(key, key)
        print(f"  {status_tag} {label}: {msg}")
    print("=" * 60)

    if not all(v[0] for v in checklist.values()):
        print("[ERROR] Release read-back verification failed!", file=sys.stderr)
        return 1

    print(f"[SUCCESS] Release {tag_name} successfully created, uploaded, and verified!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
