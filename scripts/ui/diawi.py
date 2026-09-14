#!/usr/bin/env python3
"""Upload an IPA to Diawi and print the install link.

Usage: DIAWI_TOKEN=... diawi.py <ipa>
"""
import json
import os
import subprocess
import sys
import time

ipa = sys.argv[1]
token = os.environ["DIAWI_TOKEN"]


def curl(*args: str) -> str:
    return subprocess.run(
        ["curl", "-s", *args], capture_output=True, text=True, check=True
    ).stdout


upload = curl("-F", f"token={token}", "-F", f"file=@{ipa}", "https://upload.diawi.com/")
data = json.loads(upload)
job = data.get("job") or data.get("udid")
if not job:
    print("upload failed:", upload, file=sys.stderr)
    sys.exit(1)

for _ in range(45):
    status = curl(f"https://upload.diawi.com/status?token={token}&job={job}")
    payload = json.loads(status)
    link = payload.get("link") or payload.get("url")
    if link:
        print("DIAWI_URL=" + link)
        sys.exit(0)
    state = payload.get("status")
    if isinstance(state, int) and state >= 4000:
        print("diawi status:", state, payload.get("message", ""), file=sys.stderr)
        sys.exit(1)
    time.sleep(4)

print("diawi: timed out waiting for the build", file=sys.stderr)
sys.exit(1)
