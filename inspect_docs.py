import os
import glob
import re

docs_dir = r"c:\Users\tummala surya\Downloads\roblox\scraped_docs"
md_files = glob.glob(os.path.join(docs_dir, "**", "*.md"), recursive=True)

print(f"Total MD files found: {len(md_files)}")

code_fence_concats = []
table_fence_issues = []
heading_concats = []

for filepath in md_files:
    rel_path = os.path.relpath(filepath, docs_dir)
    with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    # 1. Check for code fences not preceded by newline
    # Match any char except \n immediately followed by ```
    matches = re.finditer(r'([^\n])(```[a-zA-Z0-9_-]*)', content)
    for m in matches:
        pre_char = m.group(1)
        fence = m.group(2)
        start_idx = max(0, m.start() - 30)
        end_idx = min(len(content), m.end() + 30)
        snippet = content[start_idx:end_idx].replace('\n', '\\n')
        code_fence_concats.append((rel_path, snippet))

    # 2. Check for table rows containing ```
    lines = content.splitlines()
    for i, line in enumerate(lines):
        if line.strip().startswith('|') and '```' in line:
            table_fence_issues.append((rel_path, i + 1, line))

    # 3. Check for inline headings (e.g. text directly followed by #### Heading)
    heading_matches = re.finditer(r'([^\n])(#{1,6}\s+[A-Z])', content)
    for m in heading_matches:
        start_idx = max(0, m.start() - 30)
        end_idx = min(len(content), m.end() + 30)
        snippet = content[start_idx:end_idx].replace('\n', '\\n')
        heading_concats.append((rel_path, snippet))

out_lines = []
out_lines.append(f"Total MD files found: {len(md_files)}")
out_lines.append("\n--- 1. CODE FENCE CONCATENATIONS ---")
for path, snip in code_fence_concats:
    out_lines.append(f"{path}: {snip}")

out_lines.append("\n--- 2. TABLE FENCE ISSUES ---")
for path, lnum, line in table_fence_issues:
    out_lines.append(f"{path}:{lnum}: {line}")

out_lines.append("\n--- 3. HEADING CONCATENATIONS ---")
for path, snip in heading_concats:
    out_lines.append(f"{path}: {snip}")

with open("inspection_report.txt", "w", encoding="utf-8") as f:
    f.write("\n".join(out_lines))

print("Report saved to inspection_report.txt")
