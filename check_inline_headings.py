import os
import glob
import re

docs_dir = r"c:\Users\tummala surya\Downloads\roblox\scraped_docs"
md_files = glob.glob(os.path.join(docs_dir, "**", "*.md"), recursive=True)

inline_headings = []

for filepath in md_files:
    rel_path = os.path.relpath(filepath, docs_dir)
    with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.readlines()

    for idx, line in enumerate(lines):
        # Match #{1,6} not at start of line
        matches = re.finditer(r'([^\n#])(#{1,6}\s+[A-Z])', line)
        for m in matches:
            inline_headings.append((rel_path, idx + 1, m.group(0), line.strip()))

print(f"Total inline headings found: {len(inline_headings)}")
for path, lnum, match_str, full in inline_headings:
    clean_full = full.encode('ascii', 'backslashreplace').decode('ascii')
    clean_match = match_str.encode('ascii', 'backslashreplace').decode('ascii')
    print(f"{path}:{lnum} (match: {repr(clean_match)}) -> {clean_full}")
