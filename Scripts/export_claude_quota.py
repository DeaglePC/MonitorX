#!/usr/bin/env python3
"""An optional Claude Code statusLine command, installed manually by the user.

    python3 /absolute/path/export_claude_quota.py /absolute/path/claude-quota.json

Reads documented stdin rate_limits, writes quota fields only, and prints a status line.
Missing startup quota leaves the last snapshot and its timestamp untouched.
"""
import argparse
import json
import math
import os
from pathlib import Path
import sys
import tempfile
import time


def snapshot(payload, now):
    if not isinstance(payload, dict) or not isinstance(payload.get("rate_limits"), dict):
        return None
    windows = {}
    for key in ("five_hour", "seven_day"):
        window = payload["rate_limits"].get(key)
        if not isinstance(window, dict):
            continue
        used, reset = window.get("used_percentage"), window.get("resets_at")
        if (type(used) in (int, float) and math.isfinite(used) and 0 <= used <= 100
                and type(reset) in (int, float) and math.isfinite(reset) and reset > now):
            windows[key] = {"used_percentage": used, "resets_at": reset}
    return {"updatedAt": now, "windows": windows} if windows else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    temporary = None
    try:
        raw = sys.stdin.buffer.read(2 * 1024 * 1024 + 1)
        if len(raw) > 2 * 1024 * 1024:
            return
        data = snapshot(json.loads(raw), time.time())
        if data is None:
            return
        output = args.output.expanduser().absolute()
        with tempfile.NamedTemporaryFile(dir=output.parent, prefix=".monitorx-quota-", delete=False) as handle:
            temporary = Path(handle.name)
            os.chmod(temporary, 0o600)
            handle.write(json.dumps(data, allow_nan=False).encode() + b"\n")
        os.replace(temporary, output)
        temporary = None
    except (OSError, ValueError, TypeError):
        pass  # Never echo stdin, which can contain private session content.
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
        print("Claude")


if __name__ == "__main__":
    main()
