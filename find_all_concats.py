import os
import glob
import re

docs_dir = r"c:\Users\tummala surya\Downloads\roblox\scraped_docs"
md_files = glob.glob(os.path.join(docs_dir, "**", "*.md"), recursive=True)

fence_issues = []

for filepath in md_files:
    rel_path = os.path.relpath(filepath, docs_dir)
    with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.readlines()

    for idx, line in enumerate(lines):
        if '```' in line:
            # Check what comes before ```
            pos = line.find('```')
            prefix = line[:pos]
            # If prefix contains alphanumeric or punctuation (other than whitespace, >, -)
            if re.search(r'[^\s>|\-]', prefix):
                fence_issues.append((rel_path, idx + 1, prefix, line.strip()))

print(f"Total concatenated code fence lines found: {len(fence_issues)}")
for path, lnum, pre, full in fence_issues:
    clean_full = full.encode('ascii', 'backslashreplace').decode('ascii')
    clean_pre = pre.encode('ascii', 'backslashreplace').decode('ascii')
    print(f"{path}:{lnum} (prefix: {repr(clean_pre)}) -> {clean_full}")
