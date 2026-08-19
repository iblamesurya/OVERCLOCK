import os
import re
import sys

sys.stdout.reconfigure(encoding='utf-8')

project_root = r"c:\Users\tummala surya\Downloads\roblox"
docs_dir = os.path.join(project_root, "scraped_docs")
index_path = os.path.join(docs_dir, "INDEX.md")

print("==================================================")
print(" EMPIRICAL STRESS TEST SUITE - MILESTONE 3 ")
print("==================================================")

# 1. Read INDEX.md
with open(index_path, "r", encoding="utf-8") as f:
    index_content = f.read()

# Extract headings and generate standard markdown slugs
heading_pattern = re.compile(r"^#{1,6}\s+(.+)$", re.MULTILINE)
raw_headings = heading_pattern.findall(index_content)

def slugify(title):
    # Standard GFM slugify
    s = title.lower()
    s = re.sub(r'[^\w\s-]', '', s)
    s = re.sub(r'[\s_]+', '-', s)
    return s

heading_slugs = [slugify(h) for h in raw_headings]
print(f"Headings found in INDEX.md ({len(raw_headings)}):")
for h, s in zip(raw_headings, heading_slugs):
    print(f"  - '{h}' -> #{s}")

# Extract all links [text](target)
link_pattern = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")
all_links = link_pattern.findall(index_content)
print(f"\nTotal Markdown Links in INDEX.md: {len(all_links)}")

file_links = []
anchor_links = []
url_links = []
broken_file_links = []
broken_anchor_links = []

for text, target in all_links:
    if target.startswith("#"):
        anchor = target[1:]
        anchor_links.append((text, target))
        if anchor not in heading_slugs:
            broken_anchor_links.append((text, target))
    elif target.startswith("http://") or target.startswith("https://"):
        url_links.append((text, target))
    else:
        file_links.append((text, target))
        resolved = os.path.normpath(os.path.join(docs_dir, target))
        if not (os.path.exists(resolved) and os.path.isfile(resolved)):
            broken_file_links.append((text, target, resolved))

print(f"Relative File Links: {len(file_links)}")
print(f"Internal Anchor Links: {len(anchor_links)}")
print(f"External URL Links: {len(url_links)}")

print("\n--- LINK HEALTH RESULTS ---")
print(f"Broken Relative File Links: {len(broken_file_links)}")
if broken_file_links:
    for text, target, res in broken_file_links:
        print(f"  ❌ Broken File Link: [{text}]({target}) -> {res}")
else:
    print("  ✅ All relative file links in INDEX.md resolve to existing files on disk.")

print(f"Broken Anchor Links: {len(broken_anchor_links)}")
if broken_anchor_links:
    for text, target in broken_anchor_links:
        print(f"  ❌ Broken Anchor Link: [{text}]({target})")
else:
    print("  ✅ All internal anchor links in INDEX.md point to valid section headings.")

# Check unique target files linked
unique_file_targets = set(os.path.normpath(os.path.join(docs_dir, target)) for text, target in file_links)
print(f"\nUnique Target Markdown Files Linked in INDEX.md: {len(unique_file_targets)}")

# Check TARGET_DOCS list from verify_docs.py vs actual disk files
from verify_docs import TARGET_DOCS

target_docs_count = len(TARGET_DOCS)
print(f"Target Documents Count in verify_docs.py: {target_docs_count}")

all_51_exist = True
for url, rel_path in TARGET_DOCS:
    full_p = os.path.normpath(os.path.join(docs_dir, rel_path))
    if not os.path.exists(full_p):
        print(f"  ❌ Missing target doc: {rel_path}")
        all_51_exist = False

if all_51_exist:
    print("  ✅ All 51 target documents in verify_docs.py exist on disk.")

print("==================================================")
