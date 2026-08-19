import os
import sys
import tempfile
import shutil
import subprocess

PROJECT_ROOT = r"c:\Users\tummala surya\Downloads\roblox"
SCRAPED_DOCS_DIR = os.path.join(PROJECT_ROOT, "scraped_docs")
VERIFY_DOCS_PATH = os.path.join(PROJECT_ROOT, "verify_docs.py")

with tempfile.TemporaryDirectory() as temp_dir:
    temp_script = os.path.join(temp_dir, "verify_docs.py")
    shutil.copy2(VERIFY_DOCS_PATH, temp_script)
    temp_scraped = os.path.join(temp_dir, "scraped_docs")
    shutil.copytree(SCRAPED_DOCS_DIR, temp_scraped)

    idx_file = os.path.join(temp_scraped, "INDEX.md")
    content = open(idx_file, "r", encoding="utf-8").read()
    new_content = content.replace("projects/index.md", "projects/REMOVED.md")
    open(idx_file, "w", encoding="utf-8").write(new_content)

    env_utf8 = os.environ.copy()
    env_utf8["PYTHONIOENCODING"] = "utf-8"

    proc_utf8 = subprocess.run(
        [sys.executable, temp_script],
        cwd=temp_dir,
        capture_output=True,
        text=True,
        encoding='utf-8',
        errors='replace',
        env=env_utf8
    )

    substr = "FAIL: INDEX.md is missing links"
    print("Match:", substr in proc_utf8.stdout)
    print("Return code:", proc_utf8.returncode)
    print("Length of stdout:", len(proc_utf8.stdout))
