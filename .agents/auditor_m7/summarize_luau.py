import glob
import os

src_dir = r"c:\Users\tummala surya\Downloads\roblox\src"
files = sorted(glob.glob(os.path.join(src_dir, "**", "*.luau"), recursive=True))

for filepath in files:
    rel_path = os.path.relpath(filepath, src_dir)
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    lines = content.splitlines()
    print(f"=== File: {rel_path} ({len(lines)} lines) ===")
    if len(lines) > 0:
        print(f"  Line 1: {lines[0]}")
    # print functions defined in file
    funcs = [line.strip() for line in lines if line.strip().startswith("function ") or " function(" in line]
    print(f"  Functions count: {len(funcs)}")
    for fn in funcs[:10]:
        print(f"    {fn}")
    if len(funcs) > 10:
        print(f"    ... and {len(funcs) - 10} more")
    print()
