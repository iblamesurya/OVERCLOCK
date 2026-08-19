import os
import re
import sys

sys.stdout.reconfigure(encoding='utf-8')

def gfm_slugify(text):
    # GitHub Flavored Markdown slugify rules:
    # 1. Downcase
    # 2. Remove anything that's not a letter, number, space, or hyphen/underscore
    # 3. Replace spaces with hyphens
    text = text.lower()
    text = re.sub(r'[^\w\s-]', '', text)
    text = text.replace(' ', '-')
    return text

index_path = r"c:\Users\tummala surya\Downloads\roblox\scraped_docs\INDEX.md"
with open(index_path, "r", encoding="utf-8") as f:
    content = f.read()

# Extract headings
headings = re.findall(r"^##\s+(.+)$", content, re.MULTILINE)
print("Headings and their GFM slugs:")
heading_map = {}
for h in headings:
    slug = gfm_slugify(h)
    heading_map[slug] = h
    print(f"  Header: '{h}' -> Anchor: #{slug}")

# Extract TOC links
toc_links = re.findall(r"\[([^\]]+)\]\((#[^)]+)\)", content)
print("\nTOC Anchor Links vs Headings Check:")
broken_toc = []
for text, anchor in toc_links:
    slug = anchor[1:]
    if slug in heading_map:
        print(f"  ✅ '{text}' -> {anchor} matches header '{heading_map[slug]}'")
    else:
        print(f"  ❌ '{text}' -> {anchor} DOES NOT MATCH ANY HEADER!")
        broken_toc.append((text, anchor))

print(f"\nTotal TOC Anchor links checked: {len(toc_links)}")
print(f"Broken TOC Anchor links: {len(broken_toc)}")
