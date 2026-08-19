import glob
import os
import re

src_dir = r"c:\Users\tummala surya\Downloads\roblox\src"
files = sorted(glob.glob(os.path.join(src_dir, "**", "*.luau"), recursive=True))

print("=== DEEP CODE INSPECTION FOR AUDIT ===")

for filepath in files:
    rel_path = os.path.relpath(filepath, src_dir)
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    lines = content.splitlines()

    # 1. Check line 1 for --!strict
    if not lines or "--!strict" not in lines[0]:
        print(f"[STRICT FAIL] {rel_path}: Line 1 is '{lines[0] if lines else ''}'")

    # 2. Check for empty functions or suspicious one-liner functions
    func_pattern = re.compile(r"^\s*(local\s+)?function\s+([a-zA-Z0-9_\:\.]+)\s*\((.*?)\)", re.MULTILINE)
    matches = list(func_pattern.finditer(content))

    for m in matches:
        func_name = m.group(2)
        start_pos = m.start()
        # find matching end
        # simple heuristic: find lines from start_pos
        line_start = content[:start_pos].count('\n')
        fn_lines = lines[line_start:line_start+15]
        # check if function ends quickly
        fn_body = "\n".join(fn_lines)
        if "end" in fn_body:
            body_part = fn_body[:fn_body.find("end")+3]
            # check body length
            body_lines = [l.strip() for l in body_part.splitlines() if l.strip() and not l.strip().startswith("--")]
            if len(body_lines) <= 2:
                print(f"[SHORT FN] {rel_path}:{line_start+1} {func_name}: {' ; '.join(body_lines)}")

    # 3. Check for hardcoded string patterns like 'PASS', 'TEST PASSED', 'VERIFIED'
    for idx, l in enumerate(lines):
        if re.search(r'\b(test passed|all tests passed|fake|mock|todo|fixme|stub)\b', l, re.IGNORECASE):
            if not rel_path.endswith(".spec.luau") and not rel_path.endswith("TestRunner.luau"):
                print(f"[SUSPICIOUS TEXT] {rel_path}:{idx+1}: {l.strip()}")
