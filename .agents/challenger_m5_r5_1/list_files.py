import os

PROJECT_ROOT = r"c:\Users\tummala surya\Downloads\roblox"
SRC_DIR = os.path.join(PROJECT_ROOT, "src")

all_files = []
for root, dirs, files in os.walk(SRC_DIR):
    for f in files:
        if f.endswith(".luau"):
            rel_path = os.path.relpath(os.path.join(root, f), PROJECT_ROOT).replace("\\", "/")
            all_files.append(rel_path)

all_files.sort()

print("ALL LUAU FILES IN SRC/ (Count: %d):" % len(all_files))
for f in all_files:
    print("  " + f)
