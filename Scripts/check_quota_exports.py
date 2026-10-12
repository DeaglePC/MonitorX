#!/usr/bin/env python3
"""Verify exporters with synthetic data and a mock CLI; never touch account credentials."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    codex, claude = load("export_codex_quota"), load("export_claude_quota")
    now, private = time.time(), "PRIVATE-MUST-NOT-LEAK"
    fixture = {"rateLimits": {"limitId": "codex", "primary": {
        "usedPercent": 15, "windowDurationMins": 300, "resetsAt": now + 3600}},
        "tokens": {"access_token": private}, "email": private}
    assert private not in json.dumps(codex.snapshot(fixture, now))
    assert claude.snapshot({}, now) is None
    assert claude.snapshot({"rate_limits": {"five_hour": {
        "used_percentage": True, "resets_at": now + 3600}}}, now) is None
    with tempfile.TemporaryDirectory() as folder:
        folder = Path(folder)
        mock, output = folder / "codex", folder / "quota.json"
        mock.write_text("#!/usr/bin/env python3\nimport sys,json\n"
                        "assert json.loads(sys.stdin.readline())['method']=='initialize'\n"
                        "print(json.dumps({'id':1,'result':{}}),flush=True)\n"
                        "assert json.loads(sys.stdin.readline())['method']=='initialized'\n"
                        "assert json.loads(sys.stdin.readline())['method']=='account/rateLimits/read'\n"
                        "print(json.dumps({'id':2,'result':" + repr(fixture) + "}),flush=True)\n")
        mock.chmod(0o700)
        run = subprocess.run(["python3", str(Path(__file__).with_name("export_codex_quota.py")),
                              str(output), "--codex", str(mock)], capture_output=True, text=True, timeout=25)
        assert run.returncode == 0, run.stderr
        assert private not in output.read_text() + run.stdout + run.stderr
        assert output.stat().st_mode & 0o777 == 0o600
        payload = {"rate_limits": {"five_hour": {"used_percentage": 35, "resets_at": now + 3600}},
                   "prompt": private, "session_id": private}
        command = ["python3", str(Path(__file__).with_name("export_claude_quota.py")), str(output)]
        run = subprocess.run(command, input=json.dumps(payload), capture_output=True, text=True, timeout=5)
        assert run.returncode == 0 and private not in run.stdout + run.stderr + output.read_text()
        original = output.read_bytes()
        subprocess.run(command, input="{}", capture_output=True, text=True, check=True, timeout=5)
        assert output.read_bytes() == original
        assert output.stat().st_mode & 0o777 == 0o600
    print("Quota export passed: RPC handshake, secret redaction, private files and unchanged startup timestamp")


if __name__ == "__main__":
    main()
