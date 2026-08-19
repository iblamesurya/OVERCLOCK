import os
import re
from pathlib import Path
from collections import defaultdict

SRC_DIR = Path(r"c:\Users\tummala surya\Downloads\roblox\src")

# Find all luau files
all_files = list(SRC_DIR.glob("**/*.luau"))
print(f"Total .luau files in src/: {len(all_files)}")

# Build file index mapping:
# 1) Relative path from src/ -> Path
# 2) Roblox logical path -> Path
# e.g.,
# shared/Data/WeaponStats.luau -> ReplicatedStorage/Data/WeaponStats
# server/Services/SpawnService.luau -> ServerScriptService/Services/SpawnService
# client/Controllers/WeaponController.luau -> StarterPlayerScripts/Controllers/WeaponController

# Also map folders (for WaitForChild checks)

file_index = {}
dir_index = set()

for f in all_files:
    rel = f.relative_to(SRC_DIR)
    parts = list(rel.parts)

    top = parts[0]
    if top == "shared":
        service = "ReplicatedStorage"
    elif top == "server":
        service = "ServerScriptService"
    elif top == "client":
        service = "StarterPlayerScripts"
    else:
        service = top
    
    # Store by disk relative path without .luau
    disk_key = "/".join(parts)
    if disk_key.endswith(".luau"):
        disk_key_no_ext = disk_key[:-5]
    else:
        disk_key_no_ext = disk_key
    file_index[disk_key] = f
    file_index[disk_key_no_ext] = f
    
    # Also store directory paths
    parent_dir = rel.parent
    while parent_dir != Path('.'):
        dir_index.add("/".join(parent_dir.parts))
        parent_dir = parent_dir.parent

    # Store by Roblox logical path
    # handle filename suffixes like .server.luau, .client.luau, .spec.luau, .luau
    mod_parts = list(parts[1:])
    if mod_parts:
        fname = mod_parts[-1]
        base_name = fname.split('.')[0]
        mod_parts[-1] = base_name
        roblox_path = service + "/" + "/".join(mod_parts)
        file_index[roblox_path] = f

print(f"Indexed {len(all_files)} files.")

# Helper to resolve a require expression string from a source file
def parse_and_resolve(source_file, expr):
    expr = expr.strip()
    
    # Remove game:GetService("...")
    expr = re.sub(r'game:GetService\s*\(\s*["\'](\w+)["\']\s*\)', r'\1', expr)
    # Remove game.
    if expr.startswith("game."):
        expr = expr[5:]
    
    # Standardize :WaitForChild("Name") and .FindFirstChild("Name") to .Name
    expr = re.sub(r':WaitForChild\s*\(\s*["\']([^"\']+)["\']\s*\)', r'.\1', expr)
    expr = re.sub(r'\.FindFirstChild\s*\(\s*["\']([^"\']+)["\']\s*\)', r'.\1', expr)
    
    # Remove trailing/leading spaces or parens inside string if any
    expr = expr.strip()
    
    parts = [p.strip() for p in expr.split('.') if p.strip()]
    if not parts:
        return None, "Empty expression"
    
    base = parts[0]
    
    # Case 1: Rooted in Roblox services (ReplicatedStorage, ServerScriptService, StarterPlayerScripts)
    if base in ("ReplicatedStorage", "ServerScriptService", "StarterPlayerScripts", "StarterPlayer"):
        if base == "StarterPlayer" and len(parts) > 1 and parts[1] == "StarterPlayerScripts":
            parts = parts[1:] # collapse StarterPlayer.StarterPlayerScripts -> StarterPlayerScripts
            base = parts[0]
            
        disk_top = "shared" if base == "ReplicatedStorage" else ("server" if base == "ServerScriptService" else "client")
        sub_parts = parts[1:]
        
        # Check disk path: disk_top + sub_parts
        test_path_parts = [disk_top] + sub_parts
        test_key = "/".join(test_path_parts)
        
        if test_key in file_index:
            return file_index[test_key], f"Resolved root {test_key}"
        elif (test_key + ".luau") in file_index:
            return file_index[test_key + ".luau"], f"Resolved root {test_key}.luau"
        # Check if it's a folder containing init.luau or similar
        elif (test_key + "/init.luau") in file_index:
            return file_index[test_key + "/init.luau"], f"Resolved root {test_key}/init.luau"
        else:
            return None, f"Could not find module at {test_key} (from {expr})"

    # Case 2: Rooted in script
    elif base == "script":
        rel_src = source_file.relative_to(SRC_DIR)
        curr_disk_parts = list(rel_src.parts) # e.g. ['server', 'Services', 'SpawnService.luau']
        
        # script points to the current file
        # script.Parent points to the containing directory (or parent module)
        curr_chain = curr_disk_parts[:-1] # start with directory containing script
        
        idx = 1
        while idx < len(parts):
            token = parts[idx]
            if token == "Parent":
                if curr_chain:
                    curr_chain.pop()
            else:
                curr_chain.append(token)
            idx += 1
        
        test_key = "/".join(curr_chain)
        if test_key in file_index:
            return file_index[test_key], f"Resolved script-relative {test_key}"
        elif (test_key + ".luau") in file_index:
            return file_index[test_key + ".luau"], f"Resolved script-relative {test_key}.luau"
        elif (test_key + "/init.luau") in file_index:
            return file_index[test_key + "/init.luau"], f"Resolved script-relative {test_key}/init.luau"
        else:
            return None, f"Could not find script-relative module at {test_key} (from {expr})"

    else:
        return None, f"Unknown base token '{base}' in expression '{expr}'"


# Extract all requires
require_regex = re.compile(r'require\s*\(\s*([^)]+)\s*\)')

total_requires = 0
resolved_requires = 0
unresolved_list = []
dep_graph = defaultdict(list)

for f in all_files:
    text = f.read_text(encoding='utf-8', errors='ignore')
    # strip single-line comments
    lines = text.splitlines()
    code_lines = []
    for line in lines:
        c_idx = line.find("--")
        if c_idx != -1:
            code_lines.append(line[:c_idx])
        else:
            code_lines.append(line)
    clean_text = "\n".join(code_lines)
    
    matches = require_regex.findall(clean_text)
    for req in matches:
        req_clean = req.strip()
        # Filter out require on parameters/variables, e.g. require(module)
        if not any(k in req_clean for k in ("script", "ReplicatedStorage", "ServerScriptService", "StarterPlayerScripts", "StarterPlayer", "game:")):
            continue
        
        total_requires += 1
        target_file, reason = parse_and_resolve(f, req_clean)
        if target_file:
            resolved_requires += 1
            dep_graph[f].append(target_file)
        else:
            unresolved_list.append((f, req_clean, reason))

print(f"\n--- REQUIRE RESOLUTION RESULTS ---")
print(f"Total require statements scanned: {total_requires}")
print(f"Successfully resolved: {resolved_requires}")
print(f"Unresolved / Broken requires: {len(unresolved_list)}")

if unresolved_list:
    print("\nUNRESOLVED REQUIRES DETAILS:")
    for src, req, reason in unresolved_list:
        print(f"Source: {src.relative_to(SRC_DIR)}")
        print(f"  Expr: {req}")
        print(f"  Reason: {reason}\n")

# Cycle detection
def find_cycles(graph):
    visited = {}
    cycles = []

    def dfs(node, path):
        visited[node] = 1
        path.append(node)
        for neighbor in graph[node]:
            if neighbor not in visited:
                dfs(neighbor, path)
            elif visited[neighbor] == 1:
                cycle_start = path.index(neighbor)
                cycles.append(path[cycle_start:] + [neighbor])
        path.pop()
        visited[node] = 2

    for node in list(graph.keys()):
        if node not in visited:
            dfs(node, [])
    return cycles

cycles = find_cycles(dep_graph)
print(f"Dependency Loops (Cycles): {len(cycles)}")
if cycles:
    for c in cycles:
        print("Cycle detected:")
        for elem in c:
            print(f"  -> {elem.relative_to(SRC_DIR)}")

