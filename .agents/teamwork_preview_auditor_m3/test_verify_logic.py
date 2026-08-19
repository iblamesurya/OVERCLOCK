import os
import shutil
import tempfile
import subprocess
import sys

VERIFY_SCRIPT = r"c:\Users\tummala surya\Downloads\roblox\scraped_docs\verify_docs.py"

def run_test_case(name, setup_fn):
    with tempfile.TemporaryDirectory() as tmpdir:
        setup_fn(tmpdir)
        dest_script = os.path.join(tmpdir, "verify_docs.py")
        shutil.copy(VERIFY_SCRIPT, dest_script)
        
        env = os.environ.copy()
        env["PYTHONIOENCODING"] = "utf-8"
        
        proc = subprocess.run([sys.executable, dest_script], cwd=tmpdir, capture_output=True, text=True, env=env)
        print(f"=== Test Case: {name} ===")
        print(f"Return code: {proc.returncode}")
        print(f"Output stdout:\n{proc.stdout}")
        if proc.stderr:
            print(f"Output stderr:\n{proc.stderr}")
        return proc.returncode

def create_all_valid_dummy_files(tmpdir):
    # Populate all 51 files from TARGET_DOCS
    import sys
    sys.path.insert(0, os.path.dirname(VERIFY_SCRIPT))
    import verify_docs
    
    for url, rel_path in verify_docs.TARGET_DOCS:
        full_path = os.path.join(tmpdir, rel_path)
        os.makedirs(os.path.dirname(full_path), exist_ok=True)
        with open(full_path, "w", encoding="utf-8") as f:
            f.write(f"# Header for {rel_path}\n" + "Content line " * 20)
            
    # Also create INDEX.md with all links
    index_path = os.path.join(tmpdir, "INDEX.md")
    with open(index_path, "w", encoding="utf-8") as f:
        f.write("# Master Index\n" + "\n".join([rel_path for url, rel_path in verify_docs.TARGET_DOCS]))

if __name__ == "__main__":
    # Test 1: Full valid set
    def setup_valid(tmpdir):
        create_all_valid_dummy_files(tmpdir)
    rc_valid = run_test_case("All Valid Files", setup_valid)
    
    # Test 2: Single Missing file
    def setup_missing(tmpdir):
        create_all_valid_dummy_files(tmpdir)
        os.remove(os.path.join(tmpdir, "creation", "index.md"))
    rc_missing = run_test_case("Missing File (creation/index.md)", setup_missing)
    
    # Test 3: Undersized file
    def setup_undersized(tmpdir):
        create_all_valid_dummy_files(tmpdir)
        with open(os.path.join(tmpdir, "creation", "index.md"), "w", encoding="utf-8") as f:
            f.write("# Small") # <= 100 bytes
    rc_undersized = run_test_case("Undersized File", setup_undersized)

    # Test 4: Missing Markdown Header
    def setup_no_header(tmpdir):
        create_all_valid_dummy_files(tmpdir)
        with open(os.path.join(tmpdir, "creation", "index.md"), "w", encoding="utf-8") as f:
            f.write("No header here line " * 20)
    rc_no_header = run_test_case("Missing Markdown Header", setup_no_header)
    
    # Test 5: Missing Link in INDEX.md
    def setup_missing_link(tmpdir):
        create_all_valid_dummy_files(tmpdir)
        index_path = os.path.join(tmpdir, "INDEX.md")
        with open(index_path, "r", encoding="utf-8") as f:
            text = f.read()
        text = text.replace("creation/index.md", "REMOVED")
        with open(index_path, "w", encoding="utf-8") as f:
            f.write(text)
    rc_missing_link = run_test_case("Missing Link in INDEX.md", setup_missing_link)

    print("\nSummary:")
    print("All Valid Files return code (expected 0):", rc_valid == 0)
    print("Missing File return code (expected non-zero):", rc_missing != 0)
    print("Undersized File return code (expected non-zero):", rc_undersized != 0)
    print("Missing Header return code (expected non-zero):", rc_no_header != 0)
    print("Missing Link return code (expected non-zero):", rc_missing_link != 0)
