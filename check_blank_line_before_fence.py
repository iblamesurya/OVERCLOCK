import os
import glob

docs_dir = r"c:\Users\tummala surya\Downloads\roblox\scraped_docs"
md_files = glob.glob(os.path.join(docs_dir, "**", "*.md"), recursive=True)

no_blank_before_fence = []

for filepath in md_files:
    rel_path = os.path.relpath(filepath, docs_dir)
    with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.readlines()

    in_block = False
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith('```'):
            if not in_block:
                # Opening fence
                in_block = True
                # Check if preceding line exists and is non-empty
                if idx > 0:
                    prev_line = lines[idx - 1].strip()
                    if prev_line != '':
                        no_blank_before_fence.append((rel_path, idx + 1, prev_line, stripped))
            else:
                # Closing fence
                in_block = False

print(f"Opening fences without blank line before them: {len(no_blank_before_fence)}")
for path, lnum, prev, fence in no_blank_before_fence:
    clean_prev = prev.encode('ascii', 'backslashreplace').decode('ascii')
    print(f"{path}:{lnum} -> prev line: {repr(clean_prev)} | fence: {fence}")
