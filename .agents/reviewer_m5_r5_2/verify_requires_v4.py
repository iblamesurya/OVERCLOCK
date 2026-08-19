import os
import re
from pathlib import Path
from collections import defaultdict

SRC_DIR = Path(r"c:\Users\tummala surya\Downloads\roblox\src")

all_files = list(SRC_DIR.glob("**/*.luau"))

file_map = {}
for f in all_files:
    rel = f.relative_to(SRC_DIR).as_posix() # e.g. "shared/Data/WeaponStats.luau"
    file_map[rel] = f
    if rel.endswith(".luau"):
        file_map[rel[:-5]] = f # "shared/Data/WeaponStats"
    # Also strip .server, .client, .spec if present for matching
    base_no_ext = rel.replace(".server.luau", "").replace(".client.luau", "").replace(".spec.luau", "").replace(".luau", "")
    file_map[base_no_ext] = f

def find_requires_in_code(code):
    requires = []
    idx = 0
    while True:
        pos = code.find("require", idx)
        if pos == -1:
            break
        if pos > 0 and (code[pos-1].isalnum() or code[pos-1] == '_'):
            idx = pos + 7
            continue
        after = pos + 7
        if after < len(code) and (code[after].isalnum() or code[after] == '_'):
            idx = after
            continue
        
        open_paren = code.find("(", after)
        if open_paren == -1 or open_paren > after + 20:
            idx = after
            continue
        
        depth = 1
        curr = open_paren + 1
        in_string = False
        str_char = None
        
        while curr < len(code) and depth > 0:
            ch = code[curr]
            if in_string:
                if ch == str_char and code[curr-1] != '\\':
                    in_string = False
            else:
                if ch in ('"', "'"):
                    in_string = True
                    str_char = ch
                elif ch == '(':
                    depth += 1
                elif ch == ')':
                    depth -= 1
            curr += 1
        
        if depth == 0:
            arg = code[open_paren+1 : curr-1].strip()
            requires.append(arg)
            idx = curr
        else:
            idx = after
            
    return requires


def resolve_require(source_file, arg):
    arg_clean = arg.strip()
    
    # Strip type assertion (e.g. :: any or :: Types.Something)
    if "::" in arg_clean:
        arg_clean = arg_clean.split("::")[0].strip()
        
    if not any(k in arg_clean for k in ("ReplicatedStorage", "ServerScriptService", "StarterPlayerScripts", "StarterPlayer", "script", "game:")):
        return None, "Dynamic or variable require"

    # Replace game:GetService("...") with service name
    arg_clean = re.sub(r'game:GetService\s*\(\s*["\'](\w+)["\']\s*\)', r'\1', arg_clean)
    if arg_clean.startswith("game."):
        arg_clean = arg_clean[5:]
        
    # Standardize :WaitForChild("X") and .FindFirstChild("X") to .X
    arg_clean = re.sub(r':WaitForChild\s*\(\s*["\']([^"\']+)["\']\s*\)', r'.\1', arg_clean)
    arg_clean = re.sub(r'\.FindFirstChild\s*\(\s*["\']([^"\']+)["\']\s*\)', r'.\1', arg_clean)
    
    parts = [p.strip() for p in arg_clean.split('.') if p.strip()]
    if not parts:
        return None, "Empty target"
        
    base = parts[0]
    
    if base in ("ReplicatedStorage", "ServerScriptService", "StarterPlayerScripts", "StarterPlayer"):
        if base == "StarterPlayer" and len(parts) > 1 and parts[1] == "StarterPlayerScripts":
            parts = parts[1:]
            base = parts[0]
            
        disk_top = "shared" if base == "ReplicatedStorage" else ("server" if base == "ServerScriptService" else "client")
        sub_parts = parts[1:]
        
        rel_target = disk_top + ("/" + "/".join(sub_parts) if sub_parts else "")
        
        if rel_target in file_map:
            return file_map[rel_target], "OK"
        elif (rel_target + ".luau") in file_map:
            return file_map[rel_target + ".luau"], "OK"
        elif (rel_target + "/init.luau") in file_map:
            return file_map[rel_target + "/init.luau"], "OK"
        else:
            return None, f"Root target '{rel_target}' not found"

    elif base == "script":
        rel_src = source_file.relative_to(SRC_DIR).as_posix() # e.g. "server/Services/RoundService.luau"
        src_parts = rel_src.split('/') # ['server', 'Services', 'RoundService.luau']
        
        # script object is src_parts[-1] (e.g. RoundService.luau)
        # script.Parent is src_parts[:-1] (e.g. ['server', 'Services'])
        # script.Parent.Parent is src_parts[:-2] (e.g. ['server'])
        
        # We start traversal at index 1 of parts
        # If parts[1] == "Parent", we move up from current directory (which starts at src_parts[:-1])
        curr_dir = list(src_parts[:-1]) # parent directory of script file
        
        idx = 1
        # If parts[1] is NOT "Parent", script.Child means a child module of this script (or script itself)
        if idx < len(parts) and parts[idx] != "Parent":
            # e.g. script.ChildModule
            curr_dir.append(parts[idx])
            idx += 1
            
        while idx < len(parts):
            token = parts[idx]
            if token == "Parent":
                if curr_dir:
                    curr_dir.pop()
            else:
                curr_dir.append(token)
            idx += 1
            
        rel_target = "/".join(curr_dir)
        if rel_target in file_map:
            return file_map[rel_target], "OK"
        elif (rel_target + ".luau") in file_map:
            return file_map[rel_target + ".luau"], "OK"
        elif (rel_target + "/init.luau") in file_map:
            return file_map[rel_target + "/init.luau"], "OK"
        else:
            return None, f"Script target '{rel_target}' not found"

    return None, f"Unrecognized base '{base}'"


dep_graph = defaultdict(list)
results = []
unresolved = []

for f in all_files:
    text = f.read_text(encoding='utf-8', errors='ignore')
    lines = text.splitlines()
    clean_lines = []
    for line in lines:
        c_idx = line.find("--")
        if c_idx != -1:
            clean_lines.append(line[:c_idx])
        else:
            clean_lines.append(line)
    clean_text = "\n".join(clean_lines)
    
    reqs = find_requires_in_code(clean_text)
    for r in reqs:
        target, status = resolve_require(f, r)
        if target:
            dep_graph[f].append(target)
            results.append((f, r, target))
        else:
            if "Dynamic" not in status:
                unresolved.append((f, r, status))

print(f"\n--- ACCURATE REQUIRE RESOLUTION RESULTS ---")
print(f"Total static requires analyzed: {len(results) + len(unresolved)}")
print(f"Successfully resolved targets: {len(results)}")
print(f"Unresolved / Broken targets: {len(unresolved)}")

if unresolved:
    print("\n--- UNRESOLVED DETAILED LIST ---")
    for src, r, status in unresolved:
        print(f"Source: {src.relative_to(SRC_DIR).as_posix()}\n  Require: {r}\n  Status: {status}\n")

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
            print(f"  -> {elem.relative_to(SRC_DIR).as_posix()}")

