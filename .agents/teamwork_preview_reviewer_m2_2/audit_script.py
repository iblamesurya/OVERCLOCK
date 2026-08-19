import glob
import os
import re
import sys

sys.stdout.reconfigure(encoding='utf-8')

scraped_dir = os.path.join(os.path.dirname(__file__), '..', '..', 'scraped_docs')
md_files = glob.glob(os.path.join(scraped_dir, '**', '*.md'), recursive=True)

stats = {
    'total_files': len(md_files),
    'files_with_frontmatter': 0,
    'files_with_h1': 0,
    'files_with_h2': 0,
    'files_with_codeblocks': 0,
    'codeblocks_languages': {},
    'html_tags_found': 0,
    'empty_files': 0,
    'formatting_issues': []
}

for filepath in md_files:
    rel_path = os.path.relpath(filepath, scraped_dir)
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
        lines = content.splitlines()
        
    if len(content.strip()) == 0:
        stats['empty_files'] += 1
        
    if content.startswith('---'):
        stats['files_with_frontmatter'] += 1
        
    if any(line.startswith('# ') for line in lines):
        stats['files_with_h1'] += 1
        
    if any(line.startswith('## ') for line in lines):
        stats['files_with_h2'] += 1
        
    html_tags = re.findall(r'<(div|span|p|a|ul|li|table|tr|td|script|style)[^>]*>', content, re.IGNORECASE)
    if html_tags:
        stats['html_tags_found'] += len(html_tags)
        stats['formatting_issues'].append((rel_path, f'Found {len(html_tags)} raw HTML tags: {set(html_tags)}'))
        
    in_code = False
    for idx, line in enumerate(lines):
        if line.strip().startswith('```'):
            if not in_code:
                in_code = True
                lang = line.strip()[3:].strip()
                stats['codeblocks_languages'][lang] = stats['codeblocks_languages'].get(lang, 0) + 1
                stats['files_with_codeblocks'] += 1
            else:
                in_code = False
        elif '```' in line and not line.strip().startswith('```'):
            stats['formatting_issues'].append((rel_path, f'Line {idx+1}: Unspaced code block fence: {line[:60]}'))

print(f"Total scraped files: {stats['total_files']}")
print(f"Files with YAML frontmatter: {stats['files_with_frontmatter']}")
print(f"Files with H1 header: {stats['files_with_h1']}")
print(f"Files with H2 header: {stats['files_with_h2']}")
print(f"Codeblock language distribution: {stats['codeblocks_languages']}")
print(f"HTML tags found across all files: {stats['html_tags_found']}")
print(f"Formatting issue count: {len(stats['formatting_issues'])}")
if stats['formatting_issues']:
    print("\nSample formatting issues:")
    for item in stats['formatting_issues'][:20]:
        print(f"  {item[0]}: {item[1]}")
