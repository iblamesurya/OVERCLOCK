import os
import glob
import re

docs_dir = r"c:\Users\tummala surya\Downloads\roblox\scraped_docs"
md_files = glob.glob(os.path.join(docs_dir, "**", "*.md"), recursive=True)

def clean_markdown(content):
    # 1. Fix malformed fence marker in table row cells (e.g. | Toggle backpack | ``` | N/A | N/A |)
    content = re.sub(r'\|\s*```\s*\|', r'| `\\` ` |', content)

    # 2. Fix inline headings preceded by text or lists/blockquotes and followed by text
    # e.g., "...spiked roof"#### Airplane This example..." -> "...spiked roof"\n\n#### Airplane\n\nThis example..."
    # e.g., "...you'd like to generate. #### Car This example..." -> "...generate.\n\n#### Car\n\nThis example..."
    def fix_inline_heading(match):
        prefix = match.group(1)
        heading = match.group(2)
        following = match.group(3)
        return f"{prefix}\n\n{heading}\n\n{following}"

    content = re.sub(r'([^\n])\s*(#{1,6}\s+[A-Z][A-Za-z0-9_]*)\s+([A-Z])', fix_inline_heading, content)

    # 3. Fix code block fences concatenated directly onto preceding text without leading newline
    lines = content.split('\n')
    new_lines = []
    for line in lines:
        if line.strip().startswith('|'):
            new_lines.append(line)
            continue
        
        if '```' in line and not line.strip().startswith('```'):
            subbed = re.sub(r'(.+?)(```[a-zA-Z0-9_-]*)', r'\1\n\n\2', line)
            new_lines.append(subbed)
        else:
            new_lines.append(line)

    content = '\n'.join(new_lines)

    # Clean up excess newlines (3 or more -> 2)
    content = re.sub(r'\n{3,}', '\n\n', content)
    return content

modified_files = []

for filepath in md_files:
    with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
        original = f.read()
    
    cleaned = clean_markdown(original)
    if cleaned != original:
        rel_path = os.path.relpath(filepath, docs_dir)
        modified_files.append(rel_path)
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(cleaned)

print(f"Total files modified: {len(modified_files)}")
for f in modified_files:
    print(f" - {f}")
