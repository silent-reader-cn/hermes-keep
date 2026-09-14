"""fake_gateway 冒烟测试 — 验证各端点形状正确。

用法:
    python smoke_test.py            # 自动起一个临时进程并测试
    python smoke_test.py --no-start # 假设 main.py 已在 30003 运行，只测

可从任意 cwd 调用（CI 即从仓库根跑 `python tools/fake_gateway/smoke_test.py`）：
被拉起的 main.py 一律按**脚本所在目录**解析，不依赖当前工作目录。
"""
from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import httpx

# 脚本自身所在目录：main.py 必须相对它解析（见模块 docstring）。
SCRIPT_DIR = Path(__file__).resolve().parent
MAIN_PY = SCRIPT_DIR / "main.py"
# 就绪探活预算：循环次数 × 0.25s。
READY_ATTEMPTS = 40
READY_INTERVAL_S = 0.25

PORT = os.environ.get("FAKE_GATEWAY_PORT", "30003")
BASE = f"http://127.0.0.1:{PORT}"


def check(name: str, cond: bool, detail: str = "") -> None:
    status = "PASS" if cond else "FAIL"
    print(f"[{status}] {name}" + (f" — {detail}" if detail else ""))
    if not cond:
        raise SystemExit(1)


def main(no_start: bool = False) -> None:
    proc = None
    log_file = None
    port = PORT
    if not no_start:
        # 自动选择可用端口，避免本机已有 30003 服务污染结果。
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = str(sock.getsockname()[1])
        global BASE
        BASE = f"http://127.0.0.1:{port}"
        # 输出落临时文件而不是 DEVNULL：子进程起不来时能回显根因
        # （DEVNULL 会把 "can't open file ..." / ImportError 全部吞掉，
        #  这正是该 job 长期只报「未就绪」、无法定位的原因）。
        log_file = tempfile.TemporaryFile()
        proc = subprocess.Popen(
            [sys.executable, str(MAIN_PY)],
            cwd=str(SCRIPT_DIR),
            env={**os.environ, "FAKE_GATEWAY_PORT": port},
            stdout=log_file,
            stderr=subprocess.STDOUT,
        )
        # 等待端口就绪：只认 200，避免把 404/500 误判成就绪。
        for _ in range(READY_ATTEMPTS):
            try:
                if httpx.get(f"{BASE}/api/health", timeout=0.5).status_code == 200:
                    break
            except Exception:
                pass
            time.sleep(READY_INTERVAL_S)
        else:
            budget = READY_ATTEMPTS * READY_INTERVAL_S
            print(f"FAIL: fake gateway 未在 {budget:.0f}s 内就绪（{MAIN_PY}）")
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except Exception:
                pass
            log_file.seek(0)
            child_out = log_file.read().decode("utf-8", "replace").strip()
            print("--- 子进程输出（stdout+stderr）---")
            print(child_out[-2000:] if child_out else "(无输出：进程可能已被信号终止)")
            log_file.close()
            sys.exit(1)

    try:
        with httpx.Client(base_url=BASE, timeout=5.0) as client:
            # 1. 登录
            r = client.post("/api/auth/login", json={"password": "test"})
            check("POST /api/auth/login", r.status_code == 200 and r.json().get("ok"))

            # 2. 会话列表
            r = client.get("/api/sessions")
            data = r.json().get("data")
            check("GET /api/sessions", r.status_code == 200 and isinstance(data, list) and len(data) > 0)

            # 3. 会话详情
            sid = data[0]["id"]
            r = client.get(f"/api/sessions/{sid}")
            check("GET /api/sessions/{id}", r.status_code == 200 and r.json().get("data", {}).get("id") == sid)

            # 4. 开始聊天
            r = client.post("/api/chat/start", json={"session_id": sid})
            check("POST /api/chat/start", r.status_code == 200 and "session_id" in r.json().get("data", {}))

            # 5. SSE 流
            with client.stream("GET", f"/api/chat/stream/{sid}") as resp:
                chunks = [line for line in resp.iter_lines() if line.startswith("data: ")]
            check(
                "GET /api/chat/stream/{id} (SSE)",
                len(chunks) >= 2,
                f"收到 {len(chunks)} 个 data chunk",
            )

            # 6. crons
            r = client.get("/api/crons")
            check("GET /api/crons", r.status_code == 200 and isinstance(r.json().get("data"), list))

            # 7. memory / skills / workspaces
            for ep in ("/api/memory", "/api/skills", "/api/workspaces", "/api/profiles"):
                r = client.get(ep)
                check(f"GET {ep}", r.status_code == 200 and isinstance(r.json().get("data"), list))

            # 8. upload（multipart）
            files = {"file": ("test.txt", b"hello world", "text/plain")}
            r = client.post("/api/upload", files=files, data={"session_id": sid})
            up = r.json().get("data", {})
            check(
                "POST /api/upload",
                r.status_code == 200 and up.get("filename") == "test.txt" and up.get("size") == len(b"hello world"),
            )

            # 8b. 文件操作（delete / rename）
            r = client.post("/api/file/delete", json={"session_id": sid, "path": "a.txt", "recursive": True})
            check(
                "POST /api/file/delete",
                r.status_code == 200 and r.json().get("ok") is True and r.json().get("path") == "a.txt",
            )
            r = client.post("/api/file/rename", json={"session_id": sid, "path": "a.txt", "new_name": "b.txt"})
            check(
                "POST /api/file/rename",
                r.status_code == 200 and r.json().get("old_path") == "a.txt" and r.json().get("new_path") == "b.txt",
            )

            # 9. insights / profile switch
            r = client.get("/api/insights")
            check("GET /api/insights", r.status_code == 200 and "total_sessions" in r.json().get("data", {}))
            r = client.post("/api/profiles/switch", json={"profile": "research"})
            check("POST /api/profiles/switch", r.status_code == 200 and r.json().get("data", {}).get("current") == "research")

        print("\n全部 PASS — fake_gateway 端点形状正确。")
    finally:
        if proc is not None:
            proc.terminate()
            proc.wait(timeout=5)
            if log_file is not None:
                log_file.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-start", action="store_true", help="假设已有实例在跑")
    args = parser.parse_args()
    main(no_start=args.no_start)