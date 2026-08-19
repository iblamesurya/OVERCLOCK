import os
import glob
import re

base_dir = r"c:\Users\tummala surya\Downloads\roblox"
scraped_dir = os.path.join(base_dir, "scraped_docs")

# Read URL mappings from scraper.py
mappings = []
with open(os.path.join(base_dir, "scraper.py"), "r", encoding="utf-8") as f:
    for line in f:
        m = re.search(r'\("([^"]+)",\s*"([^"]+)"\)', line)
        if m:
            mappings.append((m.group(1), m.group(2)))

file_details = []
error_pages = []
frontmatter_count = 0
html_fallback_indicators = 0

for url, rel_path in mappings:
    abs_path = os.path.join(base_dir, rel_path)
    if not os.path.exists(abs_path):
        continue
    
    size = os.path.getsize(abs_path)
    with open(abs_path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    lines = content.splitlines()
    first_line = lines[0] if lines else ""
    
    # Check frontmatter
    is_frontmatter = content.startswith("---") or "title:" in content[:200]
    if is_frontmatter:
        frontmatter_count += 1
    
    # Check if looks like raw converted HTML
    if not is_frontmatter and not content.startswith("#"):
        html_fallback_indicators += 1

    # Check for error responses
    low = content.lower()
    if "404 Not Found" in content or "Access Denied" in content or "Cloudflare" in content or "Just a moment..." in content or "enable javascript" in low:
        error_pages.append((rel_path, content[:200]))

    file_details.append({
        'rel_path': rel_path,
        'size': size,
        'lines': len(lines),
        'frontmatter': is_frontmatter,
        'has_h1': bool(re.search(r'^#\s+', content, re.MULTILINE)),
        'has_h2': bool(re.search(r'^##\s+', content, re.MULTILINE)),
        'has_code': '```' in content or '`' in content,
        'has_list': bool(re.search(r'^\s*[\-\*\+]\s+', content, re.MULTILINE)),
        'has_table': '|' in content,
        'title': lines[0][:80] if lines else ""
    })

sizes = [d['size'] for d in file_details]
min_size = min(sizes)
max_size = max(sizes)
avg_size = sum(sizes) / len(sizes)

print("=== DETAILED REPORT ===")
print(f"Total files checked: {len(file_details)}")
print(f"Min size: {min_size} bytes ({[d['rel_path'] for d in file_details if d['size'] == min_size][0]})")
print(f"Max size: {max_size} bytes ({[d['rel_path'] for d in file_details if d['size'] == max_size][0]})")
print(f"Avg size: {avg_size:.1f} bytes")
print(f"Frontmatter/Direct MD count: {frontmatter_count}")
print(f"Error pages detected: {len(error_pages)}")
if error_pages:
    for ep in error_pages:
        print(f"  - ERROR IN {ep[0]}: {ep[1]}")

print("\n--- CATEGORY BREAKDOWN ---")
cats = {}
for d in file_details:
    cat = d['rel_path'].split('/')[1] if '/' in d['rel_path'] else 'root'
    cats[cat] = cats.get(cat, 0) + 1

for cat, count in sorted(cats.items()):
    print(f"  - {cat}: {count} files")

print("\n--- FULL FILE LISTING ---")
for d in file_details:
    print(f"{d['rel_path']:<50} | {d['size']:>6} bytes | {d['lines']:>4} lines | FM:{str(d['frontmatter']):<5} | H1:{str(d['has_h1']):<5} | Code:{str(d['has_code']):<5} | Table:{str(d['has_table']):<5}")
