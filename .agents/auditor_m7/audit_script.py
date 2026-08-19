import glob
import os

src_dir = r"c:\Users\tummala surya\Downloads\roblox\src"
files = glob.glob(os.path.join(src_dir, "**", "*.luau"), recursive=True)
print(f"Total .luau files found: {len(files)}")

missing_strict = []
empty_files = []
suspicious_patterns = []

prohibited_keywords = [
    "mock", "dummy", "todo", "fixme", "notimplemented",
    "fake", "stub", "return true -- placeholder", "return {} -- placeholder"
]

for filepath in files:
    rel_path = os.path.relpath(filepath, src_dir)
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
        lines = content.splitlines()

    if not lines:
        empty_files.append(rel_path)
        continue

    first_line = lines[0].strip()
    if "--!strict" not in first_line:
        missing_strict.append((rel_path, first_line))

    # Check for empty functions or suspicious patterns
    for idx, line in enumerate(lines):
        line_str = line.lower().strip()
        for kw in prohibited_keywords:
            if kw in line_str and not rel_path.endswith(".spec.luau"):
                suspicious_patterns.append((rel_path, idx + 1, line.strip()))

print("\n--- 1. Strict Mode Check ---")
if missing_strict:
    print("Files MISSING --!strict on line 1:")
    for path, line1 in missing_strict:
        print(f"  {path}: '{line1}'")
else:
    print("PASS: All .luau files have --!strict on line 1.")

print("\n--- 2. Empty Files Check ---")
if empty_files:
    print("EMPTY files:")
    for path in empty_files:
        print(f"  {path}")
else:
    print("PASS: No empty .luau files found.")

print("\n--- 3. Suspicious Keywords Check ---")
if suspicious_patterns:
    print("Suspicious patterns found:")
    for path, line_num, line_code in suspicious_patterns:
        print(f"  {path}:{line_num}: {line_code}")
else:
    print("PASS: No suspicious keywords found.")
