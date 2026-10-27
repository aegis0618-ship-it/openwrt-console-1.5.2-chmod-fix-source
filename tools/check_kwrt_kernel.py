"""Verify the kernel version selected by the checked-out OpenWrt/Kwrt source."""
import pathlib
import re
import sys

if len(sys.argv) < 3:
    raise SystemExit("usage: check_kwrt_kernel.py VERSION ROOT [ROOT ...]")

expected = sys.argv[1]
roots = [pathlib.Path(item) for item in sys.argv[2:]]
assignment = re.compile(
    rb"^\s*LINUX_VERSION(?:-[A-Za-z0-9_.+-]+)?\s*[:?+]?=\s*([0-9]+\.[0-9]+\.[0-9]+)",
    re.M,
)
versions = {}

for root in roots:
    if not root.exists():
        continue
    for path in root.rglob("*"):
        if not path.is_file() or path.stat().st_size > 256_000:
            continue
        if not path.name.startswith("kernel-"):
            continue
        try:
            data = path.read_bytes()
        except OSError:
            continue
        for found in assignment.findall(data):
            versions.setdefault(found.decode(), []).append(str(path))

if expected not in versions:
    found = ", ".join(sorted(versions)) or "(no kernel version declaration found)"
    raise SystemExit(
        f"Kwrt source kernel declarations: {found}; expected {expected}. "
        "Select the exact Kwrt source ref matching the device kernel."
    )

print(f"Verified selected kernel source version: {expected}")
for path in versions[expected]:
    print(path)
