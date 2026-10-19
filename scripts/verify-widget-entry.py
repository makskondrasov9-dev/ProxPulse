#!/usr/bin/env python3
"""Check the Mach-O entry itself; a valid code signature alone is insufficient."""
import re
import subprocess
import sys

binary = sys.argv[1]
load = subprocess.check_output(["/usr/bin/otool", "-l", binary], text=True)
text = re.search(r"segname __TEXT\s+vmaddr (0x[0-9a-fA-F]+)", load)
entry = re.search(r"cmd LC_MAIN\s+cmdsize \d+\s+entryoff (\d+)", load)
if not text or not entry:
    raise SystemExit("FAIL: missing __TEXT or LC_MAIN")
address = int(text.group(1), 16) + int(entry.group(1))
indirect = subprocess.check_output(["/usr/bin/otool", "-Iv", binary], text=True)
stubs = {int(match.group(1), 16) for match in re.finditer(r"(0x[0-9a-fA-F]+)\s+\d+\s+_NSExtensionMain\b", indirect)}
if address not in stubs:
    raise SystemExit(f"FAIL: LC_MAIN 0x{address:x} does not resolve to _NSExtensionMain")
print(f"PASS: LC_MAIN 0x{address:x} resolves to _NSExtensionMain")
