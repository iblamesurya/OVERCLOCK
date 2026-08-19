import os
import glob

docs_dir = r"c:\Users\tummala surya\Downloads\roblox\scraped_docs"
md_files = glob.glob(os.path.join(docs_dir, "**", "*.md"), recursive=True)

table_rows_with_backticks = []

for filepath in md_files:
    rel_path = os.path.relpath(filepath, docs_dir)
    with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.readlines()

    for idx, line in enumerate(lines):
        if line.strip().startswith('|'):
            # Check for ``` or odd backtick count in table cells
            cells = line.split('|')
            for c_idx, cell in enumerate(cells):
                if '```' in cell:
                    table_rows_with_backticks.append((rel_path, idx + 1, cell, line.strip()))

print(f"Total problematic table cells found: {len(table_rows_with_backticks)}")
for path, lnum, cell, full in table_rows_with_backticks:
    print(f"{path}:{lnum} -> cell: {repr(cell)} | line: {full}")
