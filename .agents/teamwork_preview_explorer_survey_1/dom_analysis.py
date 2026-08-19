import requests
import re
from xml.etree import ElementTree

url = "https://create.roblox.com/docs/creation"
headers = {'User-Agent': 'Mozilla/5.0'}
html = requests.get(url, headers=headers).text

print("=== HTML Structure Analysis ===")
print("Contains <main>:", "<main" in html)
print("Contains <article>:", "<article" in html)
print("Contains <nav>:", "<nav" in html)
print("Contains <header>:", "<header" in html)
print("Contains <footer>:", "<footer" in html)
print("Contains <aside>:", "<aside" in html)
print("Contains __NEXT_DATA__:", "__NEXT_DATA__" in html)

# Find main tags or key container classes/ids
main_matches = re.findall(r'<main[^>]*>', html)
print("\nMain tag attributes:", main_matches)

article_matches = re.findall(r'<article[^>]*>', html)
print("Article tag attributes:", article_matches)

nav_matches = re.findall(r'<nav[^>]*>', html)
print("Nav tag count:", len(nav_matches), "attributes:", nav_matches[:3])

header_matches = re.findall(r'<header[^>]*>', html)
print("Header tag count:", len(header_matches), "attributes:", header_matches[:3])

footer_matches = re.findall(r'<footer[^>]*>', html)
print("Footer tag count:", len(footer_matches), "attributes:", footer_matches[:3])

aside_matches = re.findall(r'<aside[^>]*>', html)
print("Aside tag count:", len(aside_matches), "attributes:", aside_matches[:3])

# Inspect script tags
script_ids = re.findall(r'<script[^>]*id="([^"]+)"', html)
print("Script tag IDs:", script_ids)

# Inspect div container classes or data-attributes near main content
div_containers = re.findall(r'<div[^>]*class="([^"]*content[^"]*)"', html, re.IGNORECASE)
print("Content-related div classes:", list(set(div_containers))[:10])

# Inspect data-testid attributes
data_testids = re.findall(r'data-testid="([^"]+)"', html)
print("Data testids:", list(set(data_testids))[:15])

# Snippet around main/article
match_main = re.search(r'<main.*?</main>', html, re.DOTALL)
if match_main:
    main_content = match_main.group(0)
    print(f"\nMain content tag total length: {len(main_content)} chars")
    print("Main content preview (first 1000 chars):\n", main_content[:1000])

