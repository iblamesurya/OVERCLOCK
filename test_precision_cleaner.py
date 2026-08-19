import os
import glob
import re

docs_dir = r"c:\Users\tummala surya\Downloads\roblox\scraped_docs"
md_files = glob.glob(os.path.join(docs_dir, "**", "*.md"), recursive=True)

def clean_markdown(content):
    # 1. Fix malformed backticks in table rows
    # Target unescaped ``` inside table cells (e.g. | Toggle backpack | ``` | N/A | N/A |)
    content = re.sub(r'(\|\s*)```(\s*\|)', r'\1`\\` `\2', content)

    # 2. Fix concatenated opening code block fences (e.g. "text:```lua", "speedometer.```lua")
    # Match any line that is NOT a table row (not starting with '|') and contains '```' not at start
    lines = content.split('\n')
    new_lines = []
    for line in lines:
        if line.strip().startswith('|'):
            new_lines.append(line)
            continue
        
        # If line contains concatenated inline heading before ``` (e.g., "...generate. #### Car This example...```lua")
        # Split inline headings first if present: e.g. "#### Car " or "#### Airplane "
        if re.search(r'#{1,6}\s+[A-Z]', line) and '```' in line:
            # Fix pattern: "...text. #### Heading text...```lang"
            # Replace "...text. #### Heading " with "...text.\n\n#### Heading\n\n"
            line = re.sub(r'([^\n])\s*(#{1,6}\s+[A-Z][A-Za-z0-9_-]*)\s+([A-Z])', r'\1\n\n\2\n\n\3', line)

        # Now fix code fences concatenated onto preceding text (e.g., "text:```lua" -> "text:\n\n```lua")
        sub_lines = []
        for l in line.split('\n'):
            if '```' in l and not l.strip().startswith('```'):
                l_sub = re.sub(r'(.+?)(```[a-zA-Z0-9_-]*)', r'\1\n\n\2', l)
                sub_lines.append(l_sub)
            else:
                sub_lines.append(l)
        
        new_lines.append('\n'.join(sub_lines))

    content = '\n'.join(new_lines)

    # Clean up excess blank lines (>2 blank lines -> 1 blank line, i.e. \n{3,} -> \n\n)
    content = re.sub(r'\n{3,}', '\n\n', content)
    return content

# Test on all files
modified = []
for filepath in md_files:
    rel_path = os.path.relpath(filepath, docs_dir)
    with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
        orig = f.read()
    c = clean_markdown(orig)
    if c != orig:
        modified.append((rel_path, orig, c))

print(f"Modified files count: {len(modified)}")
for path, orig, c in modified:
    print(f" - {path}")
