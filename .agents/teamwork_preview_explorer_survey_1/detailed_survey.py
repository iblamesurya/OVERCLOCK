import requests
import re
import json

urls = [
    "https://create.roblox.com/docs/creation",
    "https://create.roblox.com/docs/projects",
    "https://create.roblox.com/docs/workspace",
    "https://create.roblox.com/docs/parts",
    "https://create.roblox.com/docs/parts/meshes",
    "https://create.roblox.com/docs/parts/models",
    "https://create.roblox.com/docs/parts/procedural-models",
    "https://create.roblox.com/docs/parts/materials",
    "https://create.roblox.com/docs/parts/terrain",
    "https://create.roblox.com/docs/physics",
    "https://create.roblox.com/docs/physics/assemblies",
    "https://create.roblox.com/docs/physics/network-ownership",
    "https://create.roblox.com/docs/physics/mechanical-constraints",
    "https://create.roblox.com/docs/physics/mover-constraints",
    "https://create.roblox.com/docs/physics/sleep-system",
    "https://create.roblox.com/docs/physics/adaptive-timestepping",
    "https://create.roblox.com/docs/physics/units"
]

headers = {'User-Agent': 'Mozilla/5.0'}

detailed_info = []

for idx, u in enumerate(urls, 1):
    slug = u.replace("https://create.roblox.com/docs/", "")
    md_url = f"https://create.roblox.com/docs/en-us/{slug}.md"
    
    r = requests.get(md_url, headers=headers)
    text = r.text if r.status_code == 200 else ""
    
    # Analyze markdown content
    frontmatter_match = re.search(r'^---\s*\n(.*?)\n---', text, re.DOTALL)
    title_match = re.search(r'title:\s*"([^"]+)"', text)
    title = title_match.group(1) if title_match else "Unknown"
    
    desc_match = re.search(r'description:\s*"([^"]+)"', text)
    description = desc_match.group(1) if desc_match else ""
    
    updated_match = re.search(r'last_updated:\s*([^\n]+)', text)
    last_updated = updated_match.group(1) if updated_match else ""
    
    headings = re.findall(r'^(#{1,6})\s+(.+)$', text, re.MULTILINE)
    code_blocks = re.findall(r'```', text)
    code_block_count = len(code_blocks) // 2
    images = re.findall(r'!\[.*?\]\(.*?\)', text)
    tables = re.findall(r'\|.*?\|', text)
    has_tables = len(tables) > 0
    
    # Determine category and relative path
    parts = slug.split('/')
    if len(parts) == 1:
        cat = parts[0]
        rel_path_option_a = f"{cat}/index.md"
        rel_path_option_b = f"{cat}/{cat}.md"
    else:
        cat = parts[0]
        topic = parts[1]
        rel_path_option_a = f"{cat}/{topic}.md"
        rel_path_option_b = f"{cat}/{topic}.md"
        
    info = {
        "url_id": idx,
        "url": u,
        "slug": slug,
        "category": cat,
        "rel_path_index": rel_path_option_a,
        "rel_path_direct": rel_path_option_b,
        "md_url": md_url,
        "status": r.status_code,
        "size_bytes": len(text),
        "title": title,
        "description": description,
        "last_updated": last_updated,
        "heading_count": len(headings),
        "top_headings": [h[1] for h in headings[:5]],
        "code_block_count": code_block_count,
        "image_count": len(images),
        "has_tables": has_tables
    }
    detailed_info.append(info)
    print(f"[{idx:2d}] {slug:<30} -> {rel_path_option_a:<35} | Title: '{title}' ({len(text)} bytes, {len(headings)} headings, {code_block_count} code blocks)")

with open("detailed_survey.json", "w") as f:
    json.dump(detailed_info, f, indent=2)
