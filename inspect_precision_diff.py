import os
import glob
import difflib
from test_precision_cleaner import clean_markdown, docs_dir

md_files = glob.glob(os.path.join(docs_dir, "**", "*.md"), recursive=True)

for filepath in md_files:
    rel_path = os.path.relpath(filepath, docs_dir)
    with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
        orig = f.read()
    c = clean_markdown(orig)
    if c != orig:
        print(f"=== DIFF FOR {rel_path} ===")
        diff = difflib.unified_diff(
            orig.splitlines(), c.splitlines(),
            fromfile='original', tofile='cleaned', lineterm=''
        )
        for line in list(diff)[:30]:
            print(line.encode('ascii', 'backslashreplace').decode('ascii'))
        print("\n")
