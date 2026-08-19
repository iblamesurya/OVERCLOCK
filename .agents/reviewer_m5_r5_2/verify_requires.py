import os
import re
from pathlib import Path
from collections import defaultdict, deque

SRC_DIR = Path(r"c:\Users\tummala surya\Downloads\roblox\src")

# Maps Roblox roots to disk subdirectories
ROOT_MAP = {
    "ReplicatedStorage": SRC_DIR / "shared",
    "ServerScriptService": SRC_DIR / "server",
    "StarterPlayerScripts": SRC_DIR / "client",
    "StarterPlayer": SRC_DIR / "client", # if StarterPlayer.StarterPlayerScripts
}

all_files = list(SRC_DIR.glob("**/*.luau"))
print(f"Total .luau files in src/: {len(all_files)}")

shared_files = list((SRC_DIR / "shared").glob("**/*.luau"))
server_files = list((SRC_DIR / "server").glob("**/*.luau"))
client_files = list((SRC_DIR / "client").glob("**/*.luau"))

print(f"  src/shared: {len(shared_files)}")
print(f"  src/server: {len(server_files)}")
print(f"  src/client: {len(client_files)}")

# Map from logical Roblox path / disk relative path to absolute file path
# e.g., ReplicatedStorage.Data.WeaponStats -> src/shared/Data/WeaponStats.luau
# or ReplicatedStorage.Data.WeaponStats.Module -> src/shared/Data/WeaponStats/Module.luau or init.luau

file_registry = {}
for f in all_files:
    rel_path = f.relative_to(SRC_DIR)
    # Convert disk path to Roblox service path
    parts = list(rel_path.parts)
    top = parts[0]
    if top == "shared":
        service = "ReplicatedStorage"
    elif top == "server":
        service = "ServerScriptService"
    elif top == "client":
        service = "StarterPlayerScripts"
    else:
        service = top
    
    # Module name without extension
    subparts = parts[1:]
    if subparts:
        last = subparts[-1]
        if last.endswith(".luau"):
            last_name = last[:-5] # remove .luau
            if last_name.endswith(".server") or last_name.endswith(".client") or last_name.endswith(".spec"):
                last_name = last_name.rsplit('.', 1)[0]
            subparts[-1] = last_name
        
        logical_key = service + "." + ".".join(subparts)
        file_registry[logical_key] = f
        # Also store lowercase key for tolerance checks if needed
        file_registry[logical_key.lower()] = f

print(f"Registered {len(file_registry)} module keys in file_registry.")

# Parse require calls
# Patterns:
# require(game:GetService("ReplicatedStorage").Data.WeaponStats)
# require(ReplicatedStorage.Network.RemoteEvents)
# require(script.Parent.SpawnService)
# require(script.Parent.Parent.SharedModule)

require_pattern = re.compile(r'require\s*\(\s*([^)]+)\s*\)')

unresolvable = []
resolved_count = 0
dep_graph = defaultdict(list)

def resolve_target(source_file, req_str):
    req_str = req_str.strip()
    # Remove game:GetService(...) wrappers
    req_str = re.sub(r'game:GetService\s*\(\s*["\'](\w+)["\']\s*\)', r'\1', req_str)
    # Remove game.ReplicatedStorage etc.
    if req_str.startswith("game."):
        req_str = req_str[5:]
    
    # Handle script relative paths
    if req_str.startswith("script."):
        # Determine location of source_file relative to SRC_DIR
        rel_parts = list(source_file.relative_to(SRC_DIR).parts)
        top = rel_parts[0]
        service = "ReplicatedStorage" if top == "shared" else ("ServerScriptService" if top == "server" else "StarterPlayerScripts")
        
        curr_parts = [service] + rel_parts[1:]
        # Remove filename from curr_parts
        curr_parts.pop()
        
        tokens = req_str.split('.')[1:] # skip 'script'
        for tok in tokens:
            tok = tok.strip()
            if tok == "Parent":
                if curr_parts:
                    curr_parts.pop()
            else:
                curr_parts.append(tok)
        
        target_key = ".".join(curr_parts)
        return target_key
    
    # Direct service paths like ReplicatedStorage.Data.WeaponStats
    # or waitForChild calls like ReplicatedStorage:WaitForChild("Network")
    req_str = re.sub(r':WaitForChild\s*\(\s*["\'](\w+)["\']\s*\)', r'.\1', req_str)
    req_str = re.sub(r'\.FindFirstChild\s*\(\s*["\'](\w+)["\']\s*\)', r'.\1', req_str)
    
    # Clean up any leftover syntax or variables
    req_str = req_str.replace(" ", "")
    return req_str

for f in all_files:
    content = f.read_text(encoding='utf-8', errors='ignore')
    # strip single-line comments
    lines = content.splitlines()
    clean_lines = []
    for line in lines:
        comment_idx = line.find("--")
        if comment_idx != -1:
            clean_lines.append(line[:comment_idx])
        else:
            clean_lines.append(line)
    clean_code = "\n".join(clean_lines)

    matches = require_pattern.findall(clean_code)
    for m in matches:
        target_str = m.strip()
        # skip pcall/variable requires or dynamic require(module)
        if not ("." in target_str or "script" in target_str or "ReplicatedStorage" in target_str or "ServerScriptService" in target_str or "StarterPlayerScripts" in target_str):
            continue
        
        resolved_key = resolve_target(f, target_str)
        # Check if resolved_key in file_registry
        if resolved_key in file_registry:
            resolved_count += 1
            dep_graph[f].append(file_registry[resolved_key])
        elif resolved_key.lower() in file_registry:
            resolved_count += 1
            dep_graph[f].append(file_registry[resolved_key.lower()])
        else:
            # Check if it points to a directory with init.luau or something
            unresolvable.append((f, target_str, resolved_key))

print(f"\nTotal requires parsed & analyzed: {resolved_count + len(unresolvable)}")
print(f"Successfully resolved require statements: {resolved_count}")
print(f"Unresolvable require statements count: {len(unresolvable)}")

if unresolvable:
    print("\n--- UNRESOLVABLE REQUIRES DETAILS ---")
    for src, req, key in unresolvable:
        print(f"File: {src.relative_to(SRC_DIR)}\n  Require: {req}\n  Attempted Key: {key}\n")

# Dependency Loop Check (Cycle Detection in Graph)
def find_cycles(graph):
    visited = {} # None: unvisited, 1: visiting, 2: visited
    cycles = []

    def dfs(node, path):
        visited[node] = 1
        path.append(node)
        for neighbor in graph[node]:
            if neighbor not in visited:
                dfs(neighbor, path)
            elif visited[neighbor] == 1:
                # Cycle found
                cycle_start = path.index(neighbor)
                cycles.append(path[cycle_start:] + [neighbor])
        path.pop()
        visited[node] = 2

    for node in list(graph.keys()):
        if node not in visited:
            dfs(node, [])

    return cycles

cycles = find_cycles(dep_graph)
print(f"\nDependency Cycles Found: {len(cycles)}")
if cycles:
    for c in cycles:
        cycle_str = " -> ".join([str(p.relative_to(SRC_DIR)) for p in c])
        print(f"Cycle: {cycle_str}")

