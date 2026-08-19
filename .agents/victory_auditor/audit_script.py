import os
import glob
import re

src_dir = r"c:\Users\tummala surya\Downloads\roblox\src"
luau_files = glob.glob(os.path.join(src_dir, "**", "*.luau"), recursive=True)

print(f"Total .luau files found: {len(luau_files)}")

strict_issues = []
empty_func_issues = []
not_implemented_issues = []
todo_issues = []

for filepath in luau_files:
    rel_path = os.path.relpath(filepath, src_dir)
    with open(filepath, "r", encoding="utf-8") as f:
        lines = f.readlines()
    
    if not lines:
        strict_issues.append((rel_path, "Empty file"))
        continue
    
    first_line = lines[0].strip()
    if first_line != "--!strict":
        strict_issues.append((rel_path, f"Line 1 is '{first_line}', expected '--!strict'"))
        
    content = "".join(lines)
    
    # Check for empty function bodies like function foo() end or function() end
    # Match function(...) \n end or function(...) end
    matches = re.findall(r'function\s*\w*\s*\([^)]*\)\s*\n?\s*end', content)
    if matches:
        empty_func_issues.append((rel_path, matches))
        
    if "NotImplemented" in content or "not implemented" in content.lower():
        not_implemented_issues.append((rel_path, "Contains NotImplemented"))
        
    if "TODO" in content or "FIXME" in content:
        todo_issues.append((rel_path, "Contains TODO/FIXME"))

print("\n--- Strict Mode Results ---")
if not strict_issues:
    print("PASS: 100% of .luau files start with '--!strict' on Line 1.")
else:
    print(f"FAIL: {len(strict_issues)} files failed strict check:")
    for path, err in strict_issues:
        print(f"  {path}: {err}")

print("\n--- Empty Functions ---")
if not empty_func_issues:
    print("PASS: No empty functions found.")
else:
    print(f"WARNING/FAIL: Found empty functions in {len(empty_func_issues)} files:")
    for path, m in empty_func_issues:
        print(f"  {path}: {m}")

print("\n--- Not Implemented / Facades ---")
if not not_implemented_issues:
    print("PASS: No 'NotImplemented' references found.")
else:
    print(f"FAIL: {len(not_implemented_issues)} files contain NotImplemented:")
    for path, err in not_implemented_issues:
        print(f"  {path}: {err}")

print("\n--- TODO/FIXME ---")
if not todo_issues:
    print("PASS: No TODO/FIXME comments found.")
else:
    print(f"INFO: {len(todo_issues)} files contain TODO/FIXME:")
    for path, err in todo_issues:
        print(f"  {path}: {err}")
