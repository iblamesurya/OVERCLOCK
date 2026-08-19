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

headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'}

print(f"Testing {len(urls)} URLs...\n")

results = []

for i, u in enumerate(urls, 1):
    res_html = requests.get(u, headers=headers)
    html_status = res_html.status_code
    html_len = len(res_html.text)
    
    # Check alternate link tag in HTML
    md_match = re.search(r'<link\s+rel="alternate"\s+type="text/markdown"\s+href="([^"]+)"', res_html.text)
    md_href = md_match.group(1) if md_match else None
    
    if md_href:
        res_md = requests.get(md_href, headers=headers)
        md_status = res_md.status_code
        md_len = len(res_md.text)
        md_title_match = re.search(r'^title:\s*"([^"]+)"', res_md.text, re.MULTILINE)
        md_title = md_title_match.group(1) if md_title_match else ""
    else:
        md_status = "N/A"
        md_len = 0
        md_title = ""
        
    rel_path = u.replace("https://create.roblox.com/docs/", "")
    
    item = {
        "index": i,
        "url": u,
        "rel_slug": rel_path,
        "html_status": html_status,
        "html_len": html_len,
        "md_href": md_href,
        "md_status": md_status,
        "md_len": md_len,
        "title": md_title
    }
    results.append(item)
    print(f"{i:2d}. {rel_path:<30} | HTML: {html_status} ({html_len} bytes) | MD Link: {md_href} | MD: {md_status} ({md_len} bytes) | Title: {md_title}")

with open("survey_results.json", "w") as f:
    json.dump(results, f, indent=2)
