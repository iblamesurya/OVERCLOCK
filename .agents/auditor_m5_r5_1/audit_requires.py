import os
import re

ROOT_DIR = r"c:\Users\tummala surya\Downloads\roblox"
SRC_DIR = os.path.join(ROOT_DIR, "src")

# Root services mapping in Rojo
# ReplicatedStorage -> src/shared
# ServerScriptService -> src/server
# StarterPlayerScripts -> src/client

def resolve_roblox_path(script_rel_path, req_expr):
    req_expr = req_expr.strip()
    
    # Check simple service-based paths
    # e.g., ReplicatedStorage.Data.WeaponStats
    # e.g., ServerScriptService.Services.SpawnService
    # e.g., script.Parent.X
    
    tokens = req_expr.split('.')
    first = tokens[0].strip()
    
    if first == "ReplicatedStorage" or "ReplicatedStorage" in first:
        base = os.path.join(SRC_DIR, "shared")
        path_parts = tokens[1:]
    elif first == "ServerScriptService" or "ServerScriptService" in first:
        base = os.path.join(SRC_DIR, "server")
        path_parts = tokens[1:]
    elif first == "StarterPlayerScripts" or "StarterPlayerScripts" in first:
        base = os.path.join(SRC_DIR, "client")
        path_parts = tokens[1:]
    elif first == "script":
        # Relative require
        curr_dir = os.path.dirname(os.path.join(SRC_DIR, script_rel_path))
        path_parts = tokens[1:]
        base = curr_dir
        while path_parts and path_parts[0] == "Parent":
            base = os.path.dirname(base)
            path_parts.pop(0)
    else:
        return True, f"Dynamic or unhandled require: {req_expr}"

    if not path_parts:
        return True, "Root service reference"

    # Construct target path
    target = base
    for part in path_parts:
        target = os.path.join(target, part)
        
    target_file = target + ".luau"
    target_init = os.path.join(target, "init.luau")
    
    if os.path.exists(target_file) or os.path.exists(target_init) or os.path.isdir(target):
        return True, f"Resolved to {target_file}"
    else:
        return False, f"Could not find {target_file} or {target_init}"

def audit_requires():
    all_luau_files = []
    for root, dirs, files in os.walk(SRC_DIR):
        for f in files:
            if f.endswith(".luau"):
                full_path = os.path.join(root, f)
                rel_path = os.path.relpath(full_path, SRC_DIR)
                all_luau_files.append((full_path, rel_path))

    require_pattern = re.compile(r'require\s*\(\s*([^)]+)\s*\)')
    total_requires = 0
    failed_requires = []
    
    for full_path, rel_path in all_luau_files:
        with open(full_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
            
        for line_num, line in enumerate(content.splitlines(), 1):
            if "require(" in line and not line.strip().startswith("--"):
                matches = require_pattern.findall(line)
                for m in matches:
                    total_requires += 1
                    ok, msg = resolve_roblox_path(rel_path, m)
                    if not ok:
                        failed_requires.append((rel_path, line_num, m, msg))
                        
    print(f"Total require statements checked: {total_requires}")
    if failed_requires:
        print(f"FAILED REQUIRES FOUND ({len(failed_requires)}):")
        for r, l, m, msg in failed_requires:
            print(f"  {r}:{l} -> require({m}) => {msg}")
    else:
        print("ALL REQUIRE STATEMENTS RESOLVED SUCCESSFULLY!")

if __name__ == "__main__":
    audit_requires()
