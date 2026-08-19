import os
import re
import sys

sys.stdout.reconfigure(encoding='utf-8')

project_root = r"c:\Users\tummala surya\Downloads\roblox"
sys.path.insert(0, project_root)

docs_dir = os.path.join(project_root, "scraped_docs")
index_path = os.path.join(docs_dir, "INDEX.md")

from verify_docs import TARGET_DOCS

print("==================================================")
print(" EMPIRICAL STRESS TEST SUITE - 51 MARKDOWN FILES ")
print("==================================================")

file_results = []
broken_internal_links = []

for url, rel_path in TARGET_DOCS:
    full_path = os.path.normpath(os.path.join(docs_dir, rel_path))
    status = "OK"
    issues = []
    size = 0
    
    if not os.path.exists(full_path):
        status = "FAIL"
        issues.append("File does not exist")
    else:
        size = os.path.getsize(full_path)
        if size <= 100:
            status = "FAIL"
            issues.append(f"File undersized ({size} bytes)")
        
        try:
            with open(full_path, "r", encoding="utf-8") as f:
                content = f.read()
            
            # Check heading
            headings = [line for line in content.splitlines() if line.strip().startswith("#")]
            if not headings:
                status = "FAIL"
                issues.append("No Markdown headings (# or ##)")
            
            # Check internal links inside each doc file if any
            internal_links = re.findall(r"\[([^\]]+)\]\(([^)]+)\)", content)
            for link_text, link_target in internal_links:
                clean_target = link_target.split("#")[0].split("?")[0]
                if clean_target and not (clean_target.startswith("http://") or clean_target.startswith("https://") or clean_target.startswith("#")):
                    file_dir = os.path.dirname(full_path)
                    resolved_target = os.path.normpath(os.path.join(file_dir, clean_target))
                    if not (os.path.exists(resolved_target) and os.path.isfile(resolved_target)):
                        broken_internal_links.append((rel_path, link_text, link_target, resolved_target))

        except Exception as e:
            status = "FAIL"
            issues.append(f"UTF-8 read error: {e}")

    file_results.append((rel_path, status, size, issues))

pass_count = sum(1 for r in file_results if r[1] == "OK")
fail_count = sum(1 for r in file_results if r[1] != "OK")

print(f"Total Target Files Checked: {len(file_results)}")
print(f"Passed Checks: {pass_count}")
print(f"Failed Checks: {fail_count}")

if broken_internal_links:
    print(f"\nBroken Internal Links within Docs Files ({len(broken_internal_links)}):")
    for source_file, text, target, resolved in broken_internal_links:
        print(f"  - In {source_file}: [{text}]({target}) -> {resolved} NOT FOUND")
else:
    print("\n✅ Zero broken internal links across all 51 document files!")

print("==================================================")
