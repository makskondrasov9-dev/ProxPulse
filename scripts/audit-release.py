#!/usr/bin/env python3
"""Check the staged public snapshot without echoing potentially sensitive matches."""
import pathlib
import re
import subprocess
import sys

names = subprocess.check_output(["git", "ls-files", "-z"], text=True).split("\0")
patterns = [
    r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
    r"\bgh[pousr]_[A-Za-z0-9_]{30,}\b",
    r"\bgithub_pat_[A-Za-z0-9_]{30,}\b",
    r"\bAKIA[A-Z0-9]{16}\b",
]
forbidden = {".build", ".aws", ".codex", ".agents", "Preview", "DerivedData", "xcuserdata"}
issues = []
for name in filter(None, names):
    path = pathlib.Path(name)
    if forbidden.intersection(path.parts) or path.name in {"profiles.json", "snapshot.json", ".env", ".DS_Store"}:
        issues.append(f"{name}: private artifact")
    # Scan exactly the index that will be committed, rather than an unstaged working copy.
    data = subprocess.check_output(["git", "show", f":{name}"])
    if b"\0" in data:
        continue
    for line_number, line in enumerate(data.decode("utf-8", errors="replace").splitlines(), 1):
        if any(re.search(pattern, line) for pattern in patterns):
            issues.append(f"{name}:{line_number}: credential pattern")
if issues:
    print("FAIL public release audit:\n" + "\n".join(issues))
    sys.exit(1)
print(f"PASS: {sum(bool(name) for name in names)} staged files; no private artifacts or known credential patterns")
