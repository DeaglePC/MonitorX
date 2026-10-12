#!/usr/bin/env python3
"""Run manually in Terminal, outside the sandboxed app. Uses only the official CLI RPC.

    python3 Scripts/export_codex_quota.py ~/Documents/codex-quota.json

No credential files are read or exported. Run again to update the same snapshot.
"""
import argparse
import json
import math
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import tempfile
import time


def query(binary):
    process = subprocess.Popen([binary, "app-server"], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    deadline, buffer, received = time.monotonic() + 20, b"", 0

    def send(value):
        process.stdin.write(json.dumps(value).encode() + b"\n")
        process.stdin.flush()

    try:
        send({"id": 1, "method": "initialize", "params": {
            "clientInfo": {"name": "monitorx-quota-export", "version": "1.0"}}})
        while time.monotonic() < deadline:
            if not selector.select(max(0, deadline - time.monotonic())):
                raise ValueError("timeout")
            chunk = os.read(process.stdout.fileno(), 65536)
            received += len(chunk)
            if not chunk or received > 2 * 1024 * 1024:
                raise ValueError("invalid response")
            buffer += chunk
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                message = json.loads(line)
                if message.get("id") not in (1, 2):
                    continue
                if "error" in message:
                    raise ValueError("RPC failed")
                if message["id"] == 1:
                    send({"method": "initialized", "params": {}})
                    send({"id": 2, "method": "account/rateLimits/read"})
                else:
                    return message["result"]
        raise ValueError("timeout")
    finally:
        selector.close()
        process.stdin.close()
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                process.kill()
        process.wait()
        process.stdout.close()


def snapshot(result, now):
    by_id = result.get("rateLimitsByLimitId")
    entries = list(by_id.values()) if isinstance(by_id, dict) and by_id else [result.get("rateLimits")]
    buckets = []
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        bucket = {}
        for key in ("limitId", "limitName"):
            name = entry.get(key)
            if isinstance(name, str) and len(name) <= 100 and not any(ord(c) < 32 or ord(c) == 127 for c in name):
                bucket[key] = name
        for key in ("primary", "secondary"):
            window = entry.get(key)
            if not isinstance(window, dict):
                continue
            used, minutes, reset = (window.get(k) for k in ("usedPercent", "windowDurationMins", "resetsAt"))
            if (type(used) not in (int, float) or not math.isfinite(used) or not 0 <= used <= 100
                    or type(minutes) is not int or not 1 <= minutes <= 525600
                    or type(reset) not in (int, float) or not math.isfinite(reset) or reset <= 0):
                continue
            bucket[key] = {"usedPercent": used, "windowDurationMins": minutes, "resetsAt": reset}
        if "primary" in bucket or "secondary" in bucket:
            buckets.append(bucket)
    if not buckets or len(buckets) > 32:
        raise ValueError("no complete quota windows")
    return {"provider": "codex", "updatedAt": now, "buckets": buckets}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--codex", help="Path to the official Codex CLI")
    args = parser.parse_args()
    binary = args.codex or shutil.which("codex")
    if not binary:
        parser.exit(1, "Install the official Codex CLI and sign in with ChatGPT first.\n")
    temporary = None
    try:
        body = json.dumps(snapshot(query(binary), time.time()), ensure_ascii=False, allow_nan=False).encode()
        if len(body) > 64 * 1024:
            raise ValueError("snapshot too large")
        output = args.output.expanduser().absolute()
        with tempfile.NamedTemporaryFile(dir=output.parent, prefix=".monitorx-quota-", delete=False) as handle:
            temporary = Path(handle.name)
            os.chmod(temporary, 0o600)
            handle.write(body + b"\n")
        os.replace(temporary, output)
        temporary = None
        print("Saved quota-only snapshot. Select this JSON file in MonitorX.")
    except (OSError, ValueError, KeyError, TypeError):
        parser.exit(1, "Could not export quota. Check Codex sign-in, CLI version and output folder.\n")
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
