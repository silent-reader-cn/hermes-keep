#!/usr/bin/env python3
"""Linux 金照基线再生成：一条命令在 ubuntu runner 上重生成 goldens/linux/ 并取回本地。

何时**必须**跑它
----------------
**任何会改变界面的改动，在本机（Windows）跑完 `flutter test --update-goldens`
之后，必须再跑一次本脚本刷新 Linux 基线，否则 CI 会红。**

理由：金照（golden）基线是**渲染环境的产物**，按平台分目录存放
（`test/golden/goldens/<windows|linux|macos>/`），ubuntu runner 只与
`goldens/linux/` 比对（见 `test/golden/golden_platform.dart`）。本机
`--update-goldens` 只写 `goldens/windows/`，linux 那份于是停在旧版本 ——
此后 ubuntu 上的金照测试长期红（2026-09-19 → 2026-09-26 实测：
`analyze-test` 与 `coverage` 两个 job 各倒 6 例，session_list / chat / settings
× light/dark 全中）。Windows 基线绿不代表 CI 绿，两者是两份**独立的**基线。

为什么不能在本地生成
--------------------
金照必须在**目标平台**上生成（字体度量、CJK 字形回退、抗锯齿都随宿主平台变），
而本机只有 Windows：没有 Linux 环境，且主人禁用 WSL 与 Docker，故本地无论怎么
跑都写不出可信的 `goldens/linux/`。唯一可行路径是在 GitHub Actions 的 ubuntu
runner 上生成（复用 ci.yml 既有的 workflow_dispatch 输入 `update_goldens=true`，
不再另建 workflow —— 少一条产线要维护），
再把产物拉回本地覆盖 —— 也就是本脚本。

它做了什么（五步，任一步失败即非 0 退出）
----------------------------------------
1. `gh workflow run ci.yml -f update_goldens=true` 派发（目标 ref 默认当前分支）；
2. 轮询 `gh run list` / `gh run view` 直到该次运行结束；失败则回显失败日志尾部；
3. `gh run download <run-id> --name goldens-Linux` 取回 artifact（该 artifact 打的是
   整个 goldens/，脚本只取其中 linux/ 那批 PNG）；
4. 用产物里的 PNG 覆盖 `test/golden/goldens/linux/`，逐文件打印新增/变更/未变，
   并**警告**「本地有、产物里没有」的陈旧文件（只警告不删，避免误删真基线）；
5. 提示 `git status` 复核后由你自行提交（本脚本不 commit、不 push）。

用法
----
    python tools/refresh_linux_goldens.py                  # 派发 → 等待 → 取回 → 覆盖
    python tools/refresh_linux_goldens.py --dry-run        # 只打印计划，完全不碰远端
    python tools/refresh_linux_goldens.py --run-id 123456  # 复用已有运行（不派发）
    python tools/refresh_linux_goldens.py --ref my-branch --repo owner/name
    python tools/refresh_linux_goldens.py --timeout 3600 --keep-workdir

前置条件：`gh` 已登录；ci.yml 在目标分支上（本来就在）。
**用法纪律（重要）**：ci.yml 的 `concurrency` 是 `按 ref 分组 + cancel-in-progress`，
所以这次派发会掐掉同 ref 上正在跑的 CI，而派发之后你再 push 也会掐掉这次重生成。
正确顺序：**推完最后一次 → 派发重生成 → 等它跑完取回 → 再提交推送基线**。

退出码：0 = 基线已成功覆盖本地；1 = 任一步失败（含运行红、artifact 缺失、文件名
集合与 windows 基线不一致）；2 = 参数错误。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

# Windows 控制台默认 cp936/GBK，日志里的中文与路径可能直接抛
# UnicodeEncodeError 把脚本打死（或被替换成 '?' 让人误读）。钉死 UTF-8。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

DEFAULT_WORKFLOW = "ci.yml"
DEFAULT_ARTIFACT = "goldens-Linux"
DEFAULT_DEST = "test/golden/goldens/linux"
# 各平台基线文件名集合必须一致（同一批用例、同一批名字）；用它校验取回的
# artifact 确实是本仓的 linux 基线，而不是抓错 artifact / 名字被改了一半。
REFERENCE_PLATFORM_DIR = "test/golden/goldens/windows"
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


class RefreshError(RuntimeError):
    """可预期失败：打印根因后以非 0 退出（绝不静默成功）。"""


def repo_root() -> Path:
    """本脚本所在仓的根目录（tools/ 的上一级）。"""
    return Path(__file__).resolve().parents[1]


def run(
    cmd: list[str],
    *,
    cwd: Path,
    check: bool = True,
) -> subprocess.CompletedProcess:
    """跑一条命令并回显；check 为真时非 0 退出码转 RefreshError。"""
    pretty = " ".join(cmd)
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(cwd),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except FileNotFoundError as exc:
        raise RefreshError(f"命令不存在：{pretty}（{exc}）") from exc
    if check and proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip()
        raise RefreshError(f"命令失败（exit {proc.returncode}）：{pretty}\n{detail}")
    return proc


def ensure_gh_ready() -> None:
    proc = run(["gh", "--version"], cwd=repo_root(), check=False)
    if proc.returncode != 0:
        raise RefreshError(
            "找不到 gh CLI（GitHub CLI）。安装后再跑：https://cli.github.com/"
        )
    auth = run(["gh", "auth", "status"], cwd=repo_root(), check=False)
    if auth.returncode != 0:
        detail = (auth.stderr or auth.stdout or "").strip()
        raise RefreshError(f"gh 未登录（先跑 `gh auth login`）：\n{detail}")


def resolve_repo(explicit: str | None) -> str:
    """owner/name：优先 --repo，其次 git remote origin，最后 gh repo view。"""
    if explicit:
        return explicit
    root = repo_root()
    url = run(["git", "remote", "get-url", "origin"], cwd=root, check=False)
    raw = (url.stdout or "").strip()
    if url.returncode == 0 and raw:
        # https://github.com/owner/name.git / git@github.com:owner/name.git
        cleaned = raw.removesuffix(".git")
        if cleaned.startswith("git@") and ":" in cleaned:
            cleaned = cleaned.split(":", 1)[1]
        elif "github.com/" in cleaned:
            cleaned = cleaned.split("github.com/", 1)[1]
        if cleaned.count("/") == 1:
            return cleaned
    view = run(
        ["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"],
        cwd=root,
        check=False,
    )
    name = (view.stdout or "").strip()
    if view.returncode == 0 and name:
        return name
    raise RefreshError("无法确定仓库（--repo owner/name 显式指定，或检查 git remote）")


def resolve_ref(explicit: str | None) -> str:
    if explicit:
        return explicit
    root = repo_root()
    proc = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=root)
    ref = (proc.stdout or "").strip()
    if not ref or ref == "HEAD":
        raise RefreshError(
            "当前处于 detached HEAD，无法推断要派发的分支；用 --ref <branch> 指定"
        )
    return ref


def list_runs(repo: str, workflow: str) -> list[dict]:
    proc = run(
        [
            "gh",
            "run",
            "list",
            "--repo",
            repo,
            "--workflow",
            workflow,
            "--limit",
            "30",
            "--json",
            "databaseId,status,conclusion,headSha,event,createdAt,url",
        ],
        cwd=repo_root(),
    )
    try:
        data = json.loads(proc.stdout or "[]")
    except json.JSONDecodeError as exc:
        raise RefreshError(f"gh run list 输出不是合法 JSON：{exc}") from exc
    if not isinstance(data, list):
        raise RefreshError("gh run list 输出不是 JSON 数组")
    return [item for item in data if isinstance(item, dict)]


def dispatch(repo: str, workflow: str, ref: str) -> None:
    proc = run(
        [
            "gh",
            "workflow",
            "run",
            workflow,
            "--repo",
            repo,
            "--ref",
            ref,
            "-f",
            "update_goldens=true",
        ],
        cwd=repo_root(),
        check=False,
    )
    if proc.returncode == 0:
        print(f"[dispatch] 已派发 {workflow} @ {ref}（repo={repo}）")
        return
    detail = ((proc.stderr or "") + (proc.stdout or "")).strip()
    lowered = detail.lower()
    if "could not find any workflows" in lowered or "no workflows" in lowered:
        raise RefreshError(
            f"远端 {repo}@{ref} 上找不到 workflow `{workflow}`。\n"
            "workflow_dispatch 只能触发**已提交并推送**的 workflow —— "
            "确认 --workflow 的值与本仓 .github/workflows/ 下的文件名一致。\n"
            f"原始输出：{detail}"
        )
    raise RefreshError(f"派发失败：{detail or '（gh 未给出输出）'}")


def wait_for_new_run(
    repo: str, workflow: str, previous_ids: set[int], timeout_s: int, interval_s: int
) -> dict:
    """等派发出来的那次运行出现在列表里（id 比派发前见过的都大）。"""
    deadline = time.monotonic() + timeout_s
    while True:
        for item in list_runs(repo, workflow):
            try:
                rid = int(item.get("databaseId") or 0)
            except (TypeError, ValueError):
                continue
            if rid > 0 and rid not in previous_ids and rid > max(previous_ids, default=0):
                return item
        if time.monotonic() >= deadline:
            raise RefreshError(
                f"派发后 {timeout_s}s 内没在 `gh run list` 里看到新运行。\n"
                "常见原因：工作流文件不在目标分支 / Actions 被禁用 / 触发的是别的 ref。\n"
                f"手动查看：gh run list --repo {repo} --workflow {workflow}"
            )
        time.sleep(interval_s)


def wait_for_completion(repo: str, run_id: int, timeout_s: int, interval_s: int) -> dict:
    deadline = time.monotonic() + timeout_s
    started = time.monotonic()
    while True:
        proc = run(
            [
                "gh",
                "run",
                "view",
                str(run_id),
                "--repo",
                repo,
                "--json",
                "databaseId,status,conclusion,headSha,url",
            ],
            cwd=repo_root(),
        )
        try:
            info = json.loads(proc.stdout or "{}")
        except json.JSONDecodeError as exc:
            raise RefreshError(f"gh run view 输出不是合法 JSON：{exc}") from exc
        status = info.get("status") or "unknown"
        elapsed = int(time.monotonic() - started)
        print(
            f"[wait] run {run_id} status={status} 已等待 {elapsed}s "
            f"{info.get('url') or ''}".rstrip()
        )
        if status == "completed":
            return info
        if time.monotonic() >= deadline:
            raise RefreshError(
                f"等运行结束超时（{timeout_s}s，当前 status={status}）。\n"
                f"运行页：{info.get('url') or f'gh run view {run_id} --repo {repo}'}\n"
                "它仍可能在跑：稍后可用 --run-id 直接取artifact，例如\n"
                f"  python tools/refresh_linux_goldens.py --run-id {run_id}"
            )
        time.sleep(interval_s)


def dump_failure_log(repo: str, run_id: int) -> None:
    proc = run(
        ["gh", "run", "view", str(run_id), "--repo", repo, "--log-failed"],
        cwd=repo_root(),
        check=False,
    )
    text = (proc.stdout or proc.stderr or "").strip()
    if not text:
        print("[log] （gh 未给出失败日志，去运行页看完整日志）")
        return
    lines = text.splitlines()
    tail = lines[-200:]
    if len(lines) > len(tail):
        print(f"[log] 失败日志共 {len(lines)} 行，以下为末 {len(tail)} 行：")
    for line in tail:
        print(f"    {line}")


def download_artifact(repo: str, run_id: int, artifact: str, target: Path) -> None:
    proc = run(
        [
            "gh",
            "run",
            "download",
            str(run_id),
            "--repo",
            repo,
            "--name",
            artifact,
            "--dir",
            str(target),
        ],
        cwd=repo_root(),
        check=False,
    )
    if proc.returncode != 0:
        detail = ((proc.stderr or "") + (proc.stdout or "")).strip()
        raise RefreshError(
            f"下载 artifact `{artifact}` 失败：{detail or '（gh 未给出输出）'}\n"
            f"确认该运行确实产出了这个 artifact：gh run view {run_id} --repo {repo}"
        )


def collect_artifact_pngs(extract_dir: Path) -> list[Path]:
    """收集 artifact 里的 **Linux** 金照 PNG。

    ci.yml 的 artifact（`goldens-Linux`）打包的是整个 `goldens/` 目录，里面**同时含
    windows/ 与 linux/ 两份**；只取 parent 目录名为 linux 的那些，否则 windows 的 PNG
    会被当成 linux 基线写进去（文件名集合校验会挡下来，但别等它挡）。
    兼容「直接平铺 PNG」的布局（无平台子目录时全取）。
    """
    all_pngs = sorted(p for p in extract_dir.rglob("*.png") if p.is_file())
    nested = [p for p in all_pngs if p.parent.name == "linux"]
    pngs = nested or all_pngs
    if not pngs:
        entries = [p for p in extract_dir.iterdir()] if extract_dir.is_dir() else []
        raise RefreshError(
            f"artifact 解压后没有 PNG：{extract_dir}\n"
            f"目录内容：{[p.name for p in entries]}"
        )
    for path in pngs:
        with path.open("rb") as handle:
            magic = handle.read(len(PNG_MAGIC))
        if magic != PNG_MAGIC:
            raise RefreshError(
                f"{path} 不是合法 PNG（magic={magic!r}）—— artifact 可能抓错或损坏"
            )
    return pngs


def sha256_of(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_names_against_reference(pngs: list[Path], root: Path) -> None:
    """文件名集合必须与 windows 基线一致（同一批用例、同一批名字）。"""
    reference_dir = root / REFERENCE_PLATFORM_DIR
    if not reference_dir.is_dir():
        print(f"[check] 跳过文件名集合校验：{reference_dir} 不存在")
        return
    expected = {p.name for p in reference_dir.glob("*.png")}
    actual = {p.name for p in pngs}
    if expected == actual:
        print(f"[check] 文件名集合与 windows 基线一致（{len(actual)} 个）")
        return
    missing = sorted(expected - actual)
    extra = sorted(actual - expected)
    reasons = []
    if extra:
        reasons.append(
            f"  产物多出的名字：{extra}\n"
            "    → 多半是抓错了 artifact（不是本仓的 linux 基线）或名字被改过一半"
        )
    if missing:
        reasons.append(
            f"  windows 有而产物没生成的：{missing}\n"
            "    → 该用例在 Linux 上未产出基线（平台跳过？）或 artifact 不完整"
        )
    raise RefreshError(
        "artifact 里的文件名集合与 windows 基线不一致（各平台名字集合本应完全相同）：\n"
        + "\n".join(reasons)
        + "\n  确认无误时可用 --allow-name-mismatch 强行覆盖。"
    )


def install_goldens(pngs: list[Path], dest_dir: Path) -> dict[str, list[str]]:
    dest_dir.mkdir(parents=True, exist_ok=True)
    result: dict[str, list[str]] = {"added": [], "changed": [], "unchanged": []}
    for src in pngs:
        dest = dest_dir / src.name
        if not dest.exists():
            dest.write_bytes(src.read_bytes())
            result["added"].append(src.name)
            continue
        before = sha256_of(dest)
        payload = src.read_bytes()
        after = hashlib.sha256(payload).hexdigest()
        if before == after:
            result["unchanged"].append(src.name)
            continue
        dest.write_bytes(payload)
        result["changed"].append(src.name)
    return result


def report(name: str, items: list[str]) -> None:
    if not items:
        return
    print(f"  {name}（{len(items)}）：")
    for item in items:
        print(f"    {item}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="refresh_linux_goldens.py",
        description=(
            "在 ubuntu runner 上重生成 test/golden/goldens/linux/ 并自动取回覆盖本地。"
            "改变界面的改动在 Windows 上跑完 --update-goldens 之后必须再跑本脚本，"
            "否则 CI 的金照测试会因 Linux 基线陈旧而红。"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "示例：\n"
            "  python tools/refresh_linux_goldens.py\n"
            "  python tools/refresh_linux_goldens.py --dry-run\n"
            "  python tools/refresh_linux_goldens.py --run-id 123456\n"
            "本脚本只改工作区文件，不 commit / 不 push —— 复核 git status 后自行提交。"
        ),
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="只打印将要执行的计划与命令，不派发、不下载、不改文件",
    )
    parser.add_argument("--repo", help="owner/name（默认取 git remote origin）")
    parser.add_argument("--ref", help="派发到哪个分支（默认当前分支）")
    parser.add_argument(
        "--workflow",
        default=DEFAULT_WORKFLOW,
        help=f"workflow 文件名（默认 {DEFAULT_WORKFLOW}）",
    )
    parser.add_argument(
        "--artifact",
        default=DEFAULT_ARTIFACT,
        help=f"artifact 名（默认 {DEFAULT_ARTIFACT}）",
    )
    parser.add_argument(
        "--dest",
        default=DEFAULT_DEST,
        help=f"覆盖到哪个目录，仓内相对路径（默认 {DEFAULT_DEST}）",
    )
    parser.add_argument(
        "--run-id",
        type=int,
        help="复用已有的一次运行（不派发；配合 --timeout 超时后手动取回）",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=1800,
        help="等运行结束的最长秒数（默认 1800）",
    )
    parser.add_argument(
        "--dispatch-timeout",
        type=int,
        default=180,
        help="派发后等新运行出现的最长秒数（默认 180）",
    )
    parser.add_argument(
        "--poll-interval",
        type=int,
        default=10,
        help="轮询间隔秒数（默认 10）",
    )
    parser.add_argument(
        "--allow-name-mismatch",
        action="store_true",
        help="跳过「文件名集合须与 windows 基线一致」的校验（默认不跳过）",
    )
    parser.add_argument(
        "--keep-workdir",
        action="store_true",
        help="保留下载 artifact 的临时目录（排障用）",
    )
    args = parser.parse_args(argv)

    root = repo_root()
    dest_dir = (root / args.dest).resolve()

    try:
        # resolve_repo / resolve_ref 只读本地（git remote / 当前分支），dry-run 也安全。
        repo = resolve_repo(args.repo)
        ref = resolve_ref(args.ref)

        print("=" * 72)
        print("Linux 金照基线再生成")
        print(f"  repo     : {repo}")
        print(f"  ref      : {ref}")
        print(f"  workflow : {args.workflow}  (workflow_dispatch)")
        print(f"  artifact : {args.artifact}")
        print(f"  dest     : {dest_dir}")
        if args.run_id:
            print(f"  run-id   : {args.run_id}（复用已有运行，不派发）")
        print("=" * 72)

        if args.dry_run:
            existing = sorted(p.name for p in dest_dir.glob("*.png")) if dest_dir.is_dir() else []
            reference_dir = root / REFERENCE_PLATFORM_DIR
            reference = (
                sorted(p.name for p in reference_dir.glob("*.png"))
                if reference_dir.is_dir()
                else []
            )
            print(f"[dry-run] 本地 {args.dest} 现有 {len(existing)} 个 PNG")
            print(f"[dry-run] windows 基线 {len(reference)} 个 PNG")
            print("[dry-run] 将要执行的命令：")
            if not args.run_id:
                print(
                    f"    gh workflow run {args.workflow} --repo {repo} "
                    f"--ref {ref} -f update_goldens=true"
                )
                print(
                    f"    gh run list --repo {repo} --workflow {args.workflow} "
                    "--limit 30 --json databaseId,status,conclusion,headSha,event,createdAt,url"
                )
                print(
                    "    gh run view <run-id> --repo "
                    f"{repo} --json databaseId,status,conclusion,headSha,url"
                )
            print(
                f"    gh run download <run-id> --repo {repo} --name {args.artifact} "
                "--dir <tmp>"
            )
            print(f"[dry-run] 随后把产物 PNG 覆盖进 {args.dest}（新增/变更逐条打印）")
            print("[dry-run] 未派发、未下载、未改动任何文件")
            return 0

        ensure_gh_ready()

        if args.run_id:
            run_id = args.run_id
        else:
            previous = {
                int(item.get("databaseId") or 0) for item in list_runs(repo, args.workflow)
            }
            previous.discard(0)
            dispatch(repo, args.workflow, ref)
            fresh = wait_for_new_run(
                repo,
                args.workflow,
                previous,
                args.dispatch_timeout,
                args.poll_interval,
            )
            run_id = int(fresh["databaseId"])
            print(f"[dispatch] 新运行 id={run_id} url={fresh.get('url') or ''}".rstrip())

        info = wait_for_completion(repo, run_id, args.timeout, args.poll_interval)
        conclusion = (info.get("conclusion") or "").strip()
        if conclusion != "success":
            print(f"[fail] 运行 {run_id} conclusion={conclusion or 'unknown'}", file=sys.stderr)
            dump_failure_log(repo, run_id)
            raise RefreshError(
                f"运行未成功（conclusion={conclusion or 'unknown'}）："
                f"{info.get('url') or run_id}。基线未被覆盖。"
            )

        with tempfile.TemporaryDirectory(prefix="linux-goldens-") as tmp:
            extract_dir = Path(tmp) / "artifact"
            download_artifact(repo, run_id, args.artifact, extract_dir)
            pngs = collect_artifact_pngs(extract_dir)
            if not args.allow_name_mismatch:
                verify_names_against_reference(pngs, root)
            else:
                print("[check] 已按要求跳过文件名集合校验（--allow-name-mismatch）")

            print(f"[get] artifact 内 PNG {len(pngs)} 个，开始覆盖 {args.dest}")
            diff = install_goldens(pngs, dest_dir)

            if args.keep_workdir:
                # 保留到系统临时目录（不进仓，避免留下未跟踪文件干扰 git status / 提交纪律）。
                keep = Path(tempfile.gettempdir()) / f"linux-goldens-{run_id}"
                if keep.exists():
                    shutil.rmtree(keep)
                shutil.copytree(extract_dir, keep)
                print(f"[keep] 已保留解压产物：{keep}")

        print("-" * 72)
        print(f"覆盖完成：共 {len(pngs)} 个基线")
        report("变更", diff["changed"])
        report("新增", diff["added"])
        report("未变", diff["unchanged"])

        stale = sorted(
            p.name for p in dest_dir.glob("*.png") if p.name not in {s.name for s in pngs}
        )
        if stale:
            print(f"  ⚠ 本地有而产物里没有（未删除，请人工确认是否已废弃）：")
            for name in stale:
                print(f"    {name}")

        if not diff["changed"] and not diff["added"]:
            print("注意：产物与本地逐字节相同 —— 说明 Linux 基线本来就是最新的。")
        print("-" * 72)
        print("下一步（本脚本不 commit / 不 push）：")
        print(f"  git status --short {args.dest}")
        print(f"  git diff --stat {args.dest}")
        print("复核无误后自行提交，例如：")
        print(f'  git add {args.dest}/*.png')
        print('  git commit -m "test(golden): refresh linux baseline"')
        return 0
    except RefreshError as exc:
        # stderr 无缓冲、stdout 有缓冲：先 flush 免得错误行插到日志中间。
        sys.stdout.flush()
        print(f"\n错误：{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
