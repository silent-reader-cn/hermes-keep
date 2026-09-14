#!/usr/bin/env python3
"""Generate docs/REPO_MAP.md — a live snapshot of the repository layout.

AGENTS.md deliberately does NOT hand-copy the file tree any more: a hand-copied
tree rots within a few iterations (it had drifted to 17 features / ~80 test
files while the repo actually held 20 / ~290). Layout facts live here and are
regenerated from disk on demand:

    python tools/gen_repo_map.py

Output is deterministic (sorted, no timestamps) so the file diffs cleanly.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "REPO_MAP.md"

SKIP_DIRS = {
    ".git", ".dart_tool", "build", ".reference", "__pycache__",
    "node_modules", ".idea", "ephemeral",
}


def dart_files(path: Path) -> list[Path]:
    return sorted(p for p in path.rglob("*.dart") if p.is_file())


def count_files(path: Path, pattern: str = "*") -> int:
    return sum(1 for p in path.rglob(pattern) if p.is_file())


def relative_dirs(path: Path) -> list[Path]:
    if not path.is_dir():
        return []
    return sorted(p for p in path.iterdir() if p.is_dir() and p.name not in SKIP_DIRS)


def main() -> int:
    lines: list[str] = []
    add = lines.append

    add("# REPO_MAP.md — 仓库实盘快照（自动生成）")
    add("")
    add("> **本文件自动生成，请勿手工修改。** 重生成：`python tools/gen_repo_map.py`")
    add(">")
    add("> AGENTS.md §3 只钉目录约定与边界，明细清单以本文件为准，避免手工清单随迭代漂移。")
    add("")

    # --- lib/ -------------------------------------------------------------
    add(f"## `lib/` — 共 {len(dart_files(ROOT / 'lib'))} 个 dart 文件")
    add("")
    add("| 目录 | dart 文件 |")
    add("|---|---:|")
    for top in sorted(p for p in (ROOT / "lib").iterdir() if p.is_dir()):
        add(f"| `lib/{top.name}/` | {len(dart_files(top))} |")
    for f in sorted(p for p in (ROOT / "lib").iterdir() if p.is_file()):
        add(f"| `lib/{f.name}` | 入口 |")
    add("")

    add("### `lib/features/`（每个 feature 自成目录，Provider 与页面同目录）")
    add("")
    add(f"共 {len(relative_dirs(ROOT / 'lib' / 'features'))} 个 feature：")
    add("")
    add("| feature | dart 文件 |")
    add("|---|---:|")
    for d in relative_dirs(ROOT / "lib" / "features"):
        add(f"| `{d.name}/` | {len(dart_files(d))} |")
    add("")

    for sub in ["app", "core"]:
        add(f"### `lib/{sub}/`")
        add("")
        add("| 子目录 | dart 文件 |")
        add("|---|---:|")
        for d in relative_dirs(ROOT / "lib" / sub):
            add(f"| `{sub}/{d.name}/` | {len(dart_files(d))} |")
        add("")

    # --- test/ ------------------------------------------------------------
    test = ROOT / "test"
    add(f"## `test/` — 共 {len(dart_files(test))} 个 dart 文件")
    add("")
    add("| 目录 | dart 文件 |")
    add("|---|---:|")
    for d in relative_dirs(test):
        add(f"| `test/{d.name}/` | {len(dart_files(d))} |")
    for f in sorted(p for p in test.iterdir() if p.is_file()):
        add(f"| `test/{f.name}` | |")
    golden = test / "golden"
    if golden.is_dir():
        add("")
        add(f"金照基线：`test/golden/` 下 {count_files(golden, '*.png')} 张 PNG")
    add("")

    # --- 顶层与辅助目录 -----------------------------------------------------
    add("## 顶层与辅助目录")
    add("")
    add("| 路径 | 内容 |")
    add("|---|---|")
    for name in ["assets", "docs", "tools", "third_party", "android", "windows",
                 "linux", "macos", "web", "ios", ".github"]:
        p = ROOT / name
        if p.is_dir():
            add(f"| `{name}/` | {len(list(p.iterdir()))} 个直接子项 |")
    add("")
    for name in ["assets", "tools", "third_party"]:
        p = ROOT / name
        if not p.is_dir():
            continue
        add(f"### `{name}/`")
        add("")
        for sub in sorted(p.rglob("*")):
            if any(part in SKIP_DIRS for part in sub.parts):
                continue
            rel = sub.relative_to(ROOT)
            depth = len(rel.parts) - 1
            if sub.is_dir():
                add(f"- {'  ' * (depth - 1)}`{rel.as_posix()}/`")
            elif depth <= 2:
                add(f"- {'  ' * (depth - 1)}`{rel.as_posix()}`")
        add("")

    docs = ROOT / "docs"
    if docs.is_dir():
        add("### `docs/`")
        add("")
        for f in sorted(p for p in docs.iterdir() if p.is_file()):
            add(f"- `docs/{f.name}`")
        specs = docs / "specs"
        if specs.is_dir():
            add("")
            add(f"- `docs/specs/` — {len([p for p in specs.iterdir() if p.is_file()])} 份规格：")
            for f in sorted(p for p in specs.iterdir() if p.is_file()):
                add(f"  - `{f.name}`")
            for d in relative_dirs(specs):
                add(f"  - `{d.name}/`")
        shots = docs / "screenshots"
        if shots.is_dir():
            add("")
            add(f"- `docs/screenshots/` — README 截图 {count_files(shots, '*.png')} 张")
        add("")

    add("### 仓库根文件")
    add("")
    for f in sorted(p for p in ROOT.iterdir() if p.is_file()):
        add(f"- `{f.name}`")
    add("")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines).rstrip() + "\n")
    print(f"wrote {OUT.relative_to(ROOT)} ({len(lines)} lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main())