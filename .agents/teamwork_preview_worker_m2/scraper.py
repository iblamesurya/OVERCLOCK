import os
import re
import urllib.request
import urllib.error
from html.parser import HTMLParser

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

URL_MAPPINGS = [
    ("https://create.roblox.com/docs/creation", "scraped_docs/creation/index.md"),
    ("https://create.roblox.com/docs/projects", "scraped_docs/projects/index.md"),
    ("https://create.roblox.com/docs/workspace", "scraped_docs/workspace/index.md"),
    ("https://create.roblox.com/docs/parts", "scraped_docs/parts/index.md"),
    ("https://create.roblox.com/docs/parts/meshes", "scraped_docs/parts/meshes.md"),
    ("https://create.roblox.com/docs/parts/models", "scraped_docs/parts/models.md"),
    ("https://create.roblox.com/docs/parts/procedural-models", "scraped_docs/parts/procedural-models.md"),
    ("https://create.roblox.com/docs/parts/materials", "scraped_docs/parts/materials.md"),
    ("https://create.roblox.com/docs/parts/terrain", "scraped_docs/parts/terrain.md"),
    ("https://create.roblox.com/docs/physics", "scraped_docs/physics/index.md"),
    ("https://create.roblox.com/docs/physics/assemblies", "scraped_docs/physics/assemblies.md"),
    ("https://create.roblox.com/docs/physics/network-ownership", "scraped_docs/physics/network-ownership.md"),
    ("https://create.roblox.com/docs/physics/mechanical-constraints", "scraped_docs/physics/mechanical-constraints.md"),
    ("https://create.roblox.com/docs/physics/mover-constraints", "scraped_docs/physics/mover-constraints.md"),
    ("https://create.roblox.com/docs/physics/sleep-system", "scraped_docs/physics/sleep-system.md"),
    ("https://create.roblox.com/docs/physics/adaptive-timestepping", "scraped_docs/physics/adaptive-timestepping.md"),
    ("https://create.roblox.com/docs/physics/units", "scraped_docs/physics/units.md"),
    ("https://create.roblox.com/docs/effects", "scraped_docs/effects/index.md"),
    ("https://create.roblox.com/docs/workspace/camera", "scraped_docs/workspace/camera.md"),
    ("https://create.roblox.com/docs/parts/model-generation", "scraped_docs/parts/model-generation.md"),
    ("https://create.roblox.com/docs/scripting", "scraped_docs/scripting/index.md"),
    ("https://create.roblox.com/docs/environment", "scraped_docs/environment/index.md"),
    ("https://create.roblox.com/docs/players", "scraped_docs/players/index.md"),
    ("https://create.roblox.com/docs/characters", "scraped_docs/characters/index.md"),
    ("https://create.roblox.com/docs/input", "scraped_docs/input/index.md"),
    ("https://create.roblox.com/docs/audio", "scraped_docs/audio/index.md"),
    ("https://create.roblox.com/docs/ui", "scraped_docs/ui/index.md"),
    ("https://create.roblox.com/docs/animation", "scraped_docs/animation/index.md"),
    ("https://create.roblox.com/docs/matchmaking", "scraped_docs/matchmaking/index.md"),
    ("https://create.roblox.com/docs/performance-optimization", "scraped_docs/performance-optimization/index.md"),
    ("https://create.roblox.com/docs/cloud-services/data-stores-vs-memory-stores", "scraped_docs/cloud-services/data-stores-vs-memory-stores.md"),
    ("https://create.roblox.com/docs/unity", "scraped_docs/unity/index.md"),
    ("https://create.roblox.com/docs/unreal", "scraped_docs/unreal/index.md"),
    ("https://create.roblox.com/docs/discovery", "scraped_docs/discovery/index.md"),
    ("https://create.roblox.com/docs/production/game-design", "scraped_docs/production/game-design.md"),
    ("https://create.roblox.com/docs/monetize-experiences", "scraped_docs/monetization/monetize-experiences.md"),
    ("https://create.roblox.com/docs/production/monetization", "scraped_docs/production/monetization/index.md"),
    ("https://create.roblox.com/docs/production/monetization/developer-exchange", "scraped_docs/production/monetization/developer-exchange.md"),
    ("https://create.roblox.com/docs/creator-rewards", "scraped_docs/creator-rewards/index.md"),
    ("https://create.roblox.com/docs/production/monetization/roblox-plus", "scraped_docs/production/monetization/roblox-plus.md"),
    ("https://create.roblox.com/docs/production/monetization/robux-transfers", "scraped_docs/production/monetization/robux-transfers.md"),
    ("https://create.roblox.com/docs/production/monetization/private-servers", "scraped_docs/production/monetization/private-servers.md"),
    ("https://create.roblox.com/docs/production/monetization/subscriptions", "scraped_docs/production/monetization/subscriptions.md"),
    ("https://create.roblox.com/docs/production/monetization/passes", "scraped_docs/production/monetization/passes.md"),
    ("https://create.roblox.com/docs/production/monetization/developer-products", "scraped_docs/production/monetization/developer-products.md"),
    ("https://create.roblox.com/docs/production/monetization/commerce-products", "scraped_docs/production/monetization/commerce-products.md"),
    ("https://create.roblox.com/docs/production/monetization/shop", "scraped_docs/production/monetization/shop.md"),
    ("https://create.roblox.com/docs/production/monetization/paid-access-robux", "scraped_docs/production/monetization/paid-access-robux.md"),
    ("https://create.roblox.com/docs/production/monetization/paid-access-local-currency", "scraped_docs/production/monetization/paid-access-local-currency.md"),
    ("https://create.roblox.com/docs/production/monetization/managed-pricing", "scraped_docs/production/monetization/managed-pricing.md"),
    ("https://create.roblox.com/docs/ip-licensing", "scraped_docs/ip-licensing/index.md")
]

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.5'
}

class HTMLToMarkdownParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.md_out = []
        self.tag_stack = []
        self.skip_tags = {'script', 'style', 'nav', 'header', 'footer', 'aside', 'button', 'svg'}
        self.current_skip = 0
        self.in_code_block = False
        self.list_depth = 0

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        if tag in self.skip_tags or self.current_skip > 0:
            if tag in self.skip_tags:
                self.current_skip += 1
            return
        
        self.tag_stack.append(tag)
        if tag in ['h1', 'h2', 'h3', 'h4', 'h5', 'h6']:
            level = int(tag[1])
            self.md_out.append('\n\n' + '#' * level + ' ')
        elif tag == 'p':
            self.md_out.append('\n\n')
        elif tag == 'pre':
            self.in_code_block = True
            self.md_out.append('\n\n```\n')
        elif tag == 'code' and not self.in_code_block:
            self.md_out.append('`')
        elif tag == 'li':
            self.md_out.append('\n' + '  ' * max(0, self.list_depth - 1) + '- ')
        elif tag in ['ul', 'ol']:
            self.list_depth += 1
            self.md_out.append('\n')
        elif tag in ['strong', 'b']:
            self.md_out.append('**')
        elif tag in ['em', 'i']:
            self.md_out.append('*')
        elif tag == 'br':
            self.md_out.append('\n')

    def handle_endtag(self, tag):
        tag = tag.lower()
        if self.current_skip > 0:
            if tag in self.skip_tags:
                self.current_skip -= 1
            return
        
        if self.tag_stack and self.tag_stack[-1] == tag:
            self.tag_stack.pop()

        if tag in ['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'p']:
            self.md_out.append('\n\n')
        elif tag == 'pre':
            self.in_code_block = False
            self.md_out.append('\n```\n\n')
        elif tag == 'code' and not self.in_code_block:
            self.md_out.append('`')
        elif tag in ['ul', 'ol']:
            if self.list_depth > 0:
                self.list_depth -= 1
            self.md_out.append('\n')
        elif tag in ['strong', 'b']:
            self.md_out.append('**')
        elif tag in ['em', 'i']:
            self.md_out.append('*')

    def handle_data(self, data):
        if self.current_skip > 0:
            return
        self.md_out.append(data)

    def get_markdown(self):
        raw = ''.join(self.md_out)
        cleaned = re.sub(r'\n{3,}', '\n\n', raw).strip()
        return cleaned

def fetch_direct_md(url):
    slug = url.split('/docs/')[1]
    md_url = f"https://create.roblox.com/docs/en-us/{slug}.md"
    req = urllib.request.Request(md_url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=10) as res:
            if res.status == 200:
                content = res.read().decode('utf-8')
                if len(content) > 100 and ('#' in content or '---' in content or 'title:' in content):
                    return content
    except Exception:
        pass
    return None

def fetch_html_fallback(url):
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=15) as res:
            if res.status == 200:
                html_content = res.read().decode('utf-8')
                
                main_match = re.search(r'<main[^>]*>(.*?)</main>', html_content, re.DOTALL | re.IGNORECASE)
                if not main_match:
                    main_match = re.search(r'<article[^>]*>(.*?)</article>', html_content, re.DOTALL | re.IGNORECASE)
                
                content_to_parse = main_match.group(1) if main_match else html_content
                
                parser = HTMLToMarkdownParser()
                parser.feed(content_to_parse)
                md = parser.get_markdown()
                if len(md) > 50:
                    return md
    except Exception as e:
        print(f"  [ERROR] HTML fallback failed for {url}: {e}")
    return None

def main():
    print(f"Starting Roblox Documentation Scraper for {len(URL_MAPPINGS)} URLs...")
    print(f"Target Output Directory: {os.path.join(BASE_DIR, 'scraped_docs')}")
    
    success_count = 0
    direct_md_count = 0
    html_fallback_count = 0
    failed_urls = []

    for idx, (url, rel_path) in enumerate(URL_MAPPINGS, 1):
        target_path = os.path.join(BASE_DIR, rel_path)
        os.makedirs(os.path.dirname(target_path), exist_ok=True)

        print(f"[{idx}/{len(URL_MAPPINGS)}] Scraping {url} -> {rel_path}...")

        md_content = fetch_direct_md(url)
        if md_content:
            with open(target_path, 'w', encoding='utf-8') as f:
                f.write(md_content)
            direct_md_count += 1
            success_count += 1
            print(f"  -> Direct MD SUCCESS ({len(md_content)} bytes)")
            continue

        print(f"  -> Direct MD endpoint failed or empty, attempting HTML fallback...")
        md_content = fetch_html_fallback(url)
        if md_content:
            with open(target_path, 'w', encoding='utf-8') as f:
                f.write(md_content)
            html_fallback_count += 1
            success_count += 1
            print(f"  -> HTML Fallback SUCCESS ({len(md_content)} bytes)")
            continue

        print(f"  -> FAILED to scrape {url}")
        failed_urls.append(url)

    print("\n" + "="*50)
    print(f"Scraping Complete Summary:")
    print(f"Total Target URLs: {len(URL_MAPPINGS)}")
    print(f"Successfully Saved: {success_count}/{len(URL_MAPPINGS)}")
    print(f"  - Direct MD Endpoint: {direct_md_count}")
    print(f"  - HTML Fallback: {html_fallback_count}")
    print(f"Failed URLs: {len(failed_urls)}")
    print("="*50)

if __name__ == "__main__":
    main()
