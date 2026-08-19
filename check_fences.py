import os
import glob
import sys

docs_dir = r"c:\Users\tummala surya\Downloads\roblox\scraped_docs"
md_files = glob.glob(os.path.join(docs_dir, "**", "*.md"), recursive=True)

print(f"Total MD files: {len(md_files)}")

results = []

for filepath in md_files:
    rel_path = os.path.relpath(filepath, docs_dir)
    with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.readlines()

    for idx, line in enumerate(lines):
        if '```' in line:
            if not line.startswith('```'):
                pos = line.find('```')
                pre_char = line[pos-1] if pos > 0 else 'NEWLINE'
                results.append((rel_path, idx + 1, pre_char, line.rstrip()))

print(f"Found {len(results)} lines containing ``` not at start of line:")
for path, line_num, pre, text in results:
    text_clean = text.encode('ascii', 'backslashreplace').decode('ascii')
    print(f"{path}:{line_num} (pre: {repr(pre)}): {text_clean}")
