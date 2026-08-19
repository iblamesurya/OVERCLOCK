import os
import re
import sys

sys.stdout.reconfigure(encoding='utf-8')

project_root = r"c:\Users\tummala surya\Downloads\roblox"
sys.path.insert(0, project_root)
docs_dir = os.path.join(project_root, "scraped_docs")

from verify_docs import TARGET_DOCS

print(f"Total Target Files in TARGET_DOCS: {len(TARGET_DOCS)}")

inventory = []
for idx, (url, rel_path) in enumerate(TARGET_DOCS, 1):
    full_path = os.path.normpath(os.path.join(docs_dir, rel_path))
    exists = os.path.exists(full_path)
    size = os.path.getsize(full_path) if exists else 0
    with open(full_path, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.readlines()
    h1 = next((line.strip() for line in lines if line.strip().startswith("#")), "N/A")
    inventory.append((idx, rel_path, url, exists, size, len(lines), h1))

print("| # | Relative Path | Size (Bytes) | Lines | Heading | Status |")
print("|---|---------------|--------------|-------|---------|--------|")
for item in inventory:
    idx, rel_path, url, exists, size, num_lines, h1 = item
    status = "OK" if exists and size > 100 else "FAIL"
    print(f"| {idx} | `{rel_path}` | {size} | {num_lines} | {h1[:40]} | {status} |")
