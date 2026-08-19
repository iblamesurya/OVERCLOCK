import urllib.request
import re

urls = [
    ('18', 'https://create.roblox.com/docs/effects', 'effects'),
    ('19', 'https://create.roblox.com/docs/workspace/camera', 'workspace/camera'),
    ('20', 'https://create.roblox.com/docs/parts/model-generation', 'parts/model-generation'),
    ('21', 'https://create.roblox.com/docs/scripting', 'scripting'),
    ('22', 'https://create.roblox.com/docs/environment', 'environment'),
    ('23', 'https://create.roblox.com/docs/players', 'players'),
    ('24', 'https://create.roblox.com/docs/characters', 'characters'),
    ('25', 'https://create.roblox.com/docs/input', 'input'),
    ('26', 'https://create.roblox.com/docs/audio', 'audio'),
    ('27', 'https://create.roblox.com/docs/ui', 'ui'),
    ('28', 'https://create.roblox.com/docs/animation', 'animation'),
    ('29', 'https://create.roblox.com/docs/matchmaking', 'matchmaking'),
    ('30', 'https://create.roblox.com/docs/performance-optimization', 'performance-optimization'),
    ('31', 'https://create.roblox.com/docs/cloud-services/data-stores-vs-memory-stores', 'cloud-services/data-stores-vs-memory-stores'),
    ('32', 'https://create.roblox.com/docs/unity', 'unity'),
    ('33', 'https://create.roblox.com/docs/unreal', 'unreal'),
    ('34', 'https://create.roblox.com/docs/discovery', 'discovery')
]

headers = {'User-Agent': 'Mozilla/5.0'}
for num, html_url, slug in urls:
    md_url = f"https://create.roblox.com/docs/en-us/{slug}.md"
    try:
        req = urllib.request.Request(md_url, headers=headers)
        with urllib.request.urlopen(req, timeout=10) as resp:
            content = resp.read().decode('utf-8')
            lines = content.splitlines()
            title = 'N/A'
            for line in lines:
                if line.startswith('title:'):
                    title = line.split('title:')[1].strip().strip('"\'')
                    break
            print(f"URL {num}: Title=\"{title}\"")
    except Exception as e:
        print(f"URL {num}: Error={e}")
