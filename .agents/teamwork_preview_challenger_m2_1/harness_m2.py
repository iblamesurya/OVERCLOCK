import os
import re

EXPECTED_FILES = [
    r"scraped_docs\creation\index.md",
    r"scraped_docs\projects\index.md",
    r"scraped_docs\workspace\index.md",
    r"scraped_docs\parts\index.md",
    r"scraped_docs\parts\meshes.md",
    r"scraped_docs\parts\models.md",
    r"scraped_docs\parts\procedural-models.md",
    r"scraped_docs\parts\materials.md",
    r"scraped_docs\parts\terrain.md",
    r"scraped_docs\physics\index.md",
    r"scraped_docs\physics\assemblies.md",
    r"scraped_docs\physics\network-ownership.md",
    r"scraped_docs\physics\mechanical-constraints.md",
    r"scraped_docs\physics\mover-constraints.md",
    r"scraped_docs\physics\sleep-system.md",
    r"scraped_docs\physics\adaptive-timestepping.md",
    r"scraped_docs\physics\units.md",
    r"scraped_docs\effects\index.md",
    r"scraped_docs\workspace\camera.md",
    r"scraped_docs\parts\model-generation.md",
    r"scraped_docs\scripting\index.md",
    r"scraped_docs\environment\index.md",
    r"scraped_docs\players\index.md",
    r"scraped_docs\characters\index.md",
    r"scraped_docs\input\index.md",
    r"scraped_docs\audio\index.md",
    r"scraped_docs\ui\index.md",
    r"scraped_docs\animation\index.md",
    r"scraped_docs\matchmaking\index.md",
    r"scraped_docs\performance-optimization\index.md",
    r"scraped_docs\cloud-services\data-stores-vs-memory-stores.md",
    r"scraped_docs\unity\index.md",
    r"scraped_docs\unreal\index.md",
    r"scraped_docs\discovery\index.md",
    r"scraped_docs\production\game-design.md",
    r"scraped_docs\monetization\monetize-experiences.md",
    r"scraped_docs\production\monetization\index.md",
    r"scraped_docs\production\monetization\developer-exchange.md",
    r"scraped_docs\creator-rewards\index.md",
    r"scraped_docs\production\monetization\roblox-plus.md",
    r"scraped_docs\production\monetization\robux-transfers.md",
    r"scraped_docs\production\monetization\private-servers.md",
    r"scraped_docs\production\monetization\subscriptions.md",
    r"scraped_docs\production\monetization\passes.md",
    r"scraped_docs\production\monetization\developer-products.md",
    r"scraped_docs\production\monetization\commerce-products.md",
    r"scraped_docs\production\monetization\shop.md",
    r"scraped_docs\production\monetization\paid-access-robux.md",
    r"scraped_docs\production\monetization\paid-access-local-currency.md",
    r"scraped_docs\production\monetization\managed-pricing.md",
    r"scraped_docs\ip-licensing\index.md"
]

BASE_DIR = r"c:\Users\tummala surya\Downloads\roblox"

def run_checks():
    print("=== STARTING MILESTONE 2 EMPIRICAL TEST HARNESS ===")
    
    # 1. Existence Check
    missing_files = []
    found_files = []
    file_sizes = {}
    
    for rel_path in EXPECTED_FILES:
        full_path = os.path.join(BASE_DIR, rel_path)
        if not os.path.exists(full_path):
            missing_files.append(rel_path)
        else:
            found_files.append(rel_path)
            file_sizes[rel_path] = os.path.getsize(full_path)
            
    print(f"Check 1: Target Document Existence")
    print(f"  Expected count: {len(EXPECTED_FILES)}")
    print(f"  Found count: {len(found_files)}")
    print(f"  Missing count: {len(missing_files)}")
    if missing_files:
        print(f"  Missing files list: {missing_files}")

    # Check for all .md files in scraped_docs to detect any extra or root index
    scraped_docs_dir = os.path.join(BASE_DIR, "scraped_docs")
    all_md_files = []
    for root, dirs, files in os.walk(scraped_docs_dir):
        for f in files:
            if f.endswith(".md"):
                rel = os.path.relpath(os.path.join(root, f), BASE_DIR)
                all_md_files.append(rel)
                
    print(f"  Total .md files in scraped_docs: {len(all_md_files)}")
    extra_files = set(all_md_files) - set(EXPECTED_FILES)
    print(f"  Extra files (e.g. INDEX.md): {list(extra_files)}")

    # 2. File Sizes (> 100 bytes, min and avg)
    sizes = list(file_sizes.values())
    under_100 = [path for path, sz in file_sizes.items() if sz <= 100]
    
    min_size = min(sizes) if sizes else 0
    max_size = max(sizes) if sizes else 0
    avg_size = sum(sizes) / len(sizes) if sizes else 0
    
    min_file = min(file_sizes.items(), key=lambda x: x[1]) if file_sizes else None
    max_file = max(file_sizes.items(), key=lambda x: x[1]) if file_sizes else None

    print(f"\nCheck 2: File Size Analysis")
    print(f"  Files > 100 bytes: {len(sizes) - len(under_100)} / {len(sizes)}")
    print(f"  Files <= 100 bytes: {len(under_100)}")
    if under_100:
        print(f"  Failing files: {under_100}")
    print(f"  Minimum file size: {min_size} bytes ({min_file[0] if min_file else 'N/A'})")
    print(f"  Maximum file size: {max_size} bytes ({max_file[0] if max_file else 'N/A'})")
    print(f"  Average file size: {avg_size:.2f} bytes")

    # 3. Markdown Headers (# or ##)
    no_h1_h2 = []
    header_counts = {}
    
    for rel_path in found_files:
        full_path = os.path.join(BASE_DIR, rel_path)
        with open(full_path, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()
        
        # Check for # or ## headings
        # Match lines starting with # or ## or frontmatter title/headers
        h1_matches = re.findall(r"^#\s+(.+)$", content, re.MULTILINE)
        h2_matches = re.findall(r"^##\s+(.+)$", content, re.MULTILINE)
        
        has_headers = len(h1_matches) > 0 or len(h2_matches) > 0
        if not has_headers:
            # Fallback check if any line starts with '#'
            if any(line.strip().startswith('#') for line in content.splitlines()):
                has_headers = True
                
        header_counts[rel_path] = (len(h1_matches), len(h2_matches))
        if not has_headers:
            no_h1_h2.append(rel_path)

    print(f"\nCheck 3: Markdown Headers (# or ##)")
    print(f"  Files with # or ## headings: {len(found_files) - len(no_h1_h2)} / {len(found_files)}")
    print(f"  Files missing # or ## headings: {len(no_h1_h2)}")
    if no_h1_h2:
        print(f"  Files without headers: {no_h1_h2}")

    # 4. HTML Noise Check (<nav>, <footer>, <script>, <header>)
    noise_tags = ["<nav>", "</nav>", "<nav ", "<footer>", "</footer>", "<footer ", "<script>", "</script>", "<script ", "<header>", "</header>", "<header "]
    noise_pattern = re.compile(r"<\s*(nav|footer|script|header)[\s/>]", re.IGNORECASE)
    
    files_with_noise = {}
    
    for rel_path in found_files:
        full_path = os.path.join(BASE_DIR, rel_path)
        with open(full_path, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()
            
        matches = noise_pattern.findall(content)
        if matches:
            files_with_noise[rel_path] = matches

    print(f"\nCheck 4: Noise Tag Check (<nav>, <footer>, <script>, <header>)")
    print(f"  Files free of target noise tags: {len(found_files) - len(files_with_noise)} / {len(found_files)}")
    print(f"  Files containing noise tags: {len(files_with_noise)}")
    if files_with_noise:
        for f, tags in files_with_noise.items():
            print(f"    {f}: found tags {set(tags)}")

    # 5. Additional Quality & Integrity Checks
    error_404_files = []
    for rel_path in found_files:
        full_path = os.path.join(BASE_DIR, rel_path)
        with open(full_path, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()
        if "404 Not Found" in content or "Page Not Found" in content or "404: Page not found" in content:
            error_404_files.append(rel_path)
            
    print(f"\nCheck 5: Additional Quality Checks (404/Error pages)")
    print(f"  404 error page count: {len(error_404_files)}")
    if error_404_files:
        print(f"  404 files: {error_404_files}")

    # Overall Verdict Logic
    pass_c1 = (len(found_files) == 51) and (len(missing_files) == 0)
    pass_c2 = (len(under_100) == 0)
    pass_c3 = (len(no_h1_h2) == 0)
    pass_c4 = (len(files_with_noise) == 0)
    pass_c5 = (len(error_404_files) == 0)

    overall_pass = pass_c1 and pass_c2 and pass_c3 and pass_c4 and pass_c5

    print("\n================ VERDICT SUMMARY ================")
    print(f"Requirement 1 (51 files exist): {'PASS' if pass_c1 else 'FAIL'}")
    print(f"Requirement 2 (Files > 100 bytes): {'PASS' if pass_c2 else 'FAIL'}")
    print(f"Requirement 3 (Markdown headers #/##): {'PASS' if pass_c3 else 'FAIL'}")
    print(f"Requirement 4 (No HTML noise tags): {'PASS' if pass_c4 else 'FAIL'}")
    print(f"Quality Check (No 404 pages): {'PASS' if pass_c5 else 'FAIL'}")
    print(f"OVERALL VERDICT: {'APPROVE' if overall_pass else 'REJECT'}")

if __name__ == "__main__":
    run_checks()
