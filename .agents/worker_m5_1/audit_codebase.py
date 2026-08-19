import os
import re

SRC_DIR = r"c:\Users\tummala surya\Downloads\roblox\src"

def resolve_require(file_rel_path, req_str):
    # Standard patterns:
    # 1. script.Parent...
    # 2. ReplicatedStorage:WaitForChild("Folder"):WaitForChild("Module")
    # 3. game:GetService(...)
    # 4. path requires
    # Returns (status: bool, note: str)
    return True, "OK"

def deep_audit():
    missing_files = []
    unresolved_requires = []
    
    # Map of Luau virtual paths based on default.project.json
    # ServerScriptService -> src/server
    # StarterPlayerScripts -> src/client
    # ReplicatedStorage -> src/shared
    
    all_luau_files = {}
    for root, _, files in os.walk(SRC_DIR):
        for f in files:
            if f.endswith(".luau") or f.endswith(".lua"):
                full_path = os.path.join(root, f)
                rel = os.path.relpath(full_path, SRC_DIR)
                all_luau_files[rel.replace("\\", "/")] = full_path

    print(f"Total Luau files in src: {len(all_luau_files)}")

    # Check each file for syntax or obvious broken paths
    for rel_path, full_path in all_luau_files.items():
        with open(full_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
            lines = content.splitlines()
            for line_idx, line in enumerate(lines, start=1):
                # find requires
                matches = re.findall(r'require\s*\(([^)]+)\)', line)
                for m in matches:
                    m_clean = m.strip()
                    # Check if require uses string path e.g. require("...")
                    str_match = re.match(r'^["\']([^"\']+)["\']$', m_clean)
                    if str_match:
                        target = str_match.group(1)
                        # e.g., require("src/shared/...") or require(".Parent.Service")
                        # check if exists
                        print(f"String require in {rel_path}:{line_idx} -> {target}")

    return all_luau_files

if __name__ == "__main__":
    files = deep_audit()
