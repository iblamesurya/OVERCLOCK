import urllib.request

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
}

def test_fetch(slug):
    md_url = f"https://create.roblox.com/docs/en-us/{slug}.md"
    print(f"Fetching {md_url}...")
    req = urllib.request.Request(md_url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=10) as res:
            content = res.read().decode('utf-8')
            print(f"Length: {len(content)}")
            return content
    except Exception as e:
        print(f"Error: {e}")
        return None

c1 = test_fetch("scripting")
if c1:
    for line in c1.splitlines():
        if '```' in line and not line.strip().startswith('```'):
            print("scripting direct MD has fence issue:", line)

c2 = test_fetch("input")
if c2:
    for line in c2.splitlines():
        if '```' in line and not line.strip().startswith('```'):
            print("input direct MD has fence issue:", line)

c3 = test_fetch("parts/model-generation")
if c3:
    for line in c3.splitlines():
        if '```' in line and not line.strip().startswith('```'):
            print("model-generation direct MD has fence issue:", line)
