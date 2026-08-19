import os

PROJECT_ROOT = r"c:\Users\tummala surya\Downloads\roblox"
AGENTS_DIR = os.path.join(PROJECT_ROOT, ".agents")

print("=== .AGENTS DIRECTORY STRUCTURE ===")
for root, dirs, files in os.walk(AGENTS_DIR):
    rel = os.path.relpath(root, AGENTS_DIR)
    print(f"Directory: .agents/{rel}")
    for f in files:
        print(f"  - {f}")
