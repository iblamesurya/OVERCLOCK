import os
import re

ROOT = r"c:\Users\tummala surya\Downloads\roblox"
SRC = os.path.join(ROOT, "src")

class Instance:
    def __init__(self, name, path=None, parent=None):
        self.name = name
        self.path = path
        self.parent = parent
        self.children = {}

    def add_child(self, child_name, child_inst):
        self.children[child_name] = child_inst
        child_inst.parent = self

root_inst = Instance("game")
rs_inst = Instance("ReplicatedStorage")
sss_inst = Instance("ServerScriptService")
sp_inst = Instance("StarterPlayer")
sps_inst = Instance("StarterPlayerScripts")

root_inst.add_child("ReplicatedStorage", rs_inst)
root_inst.add_child("ServerScriptService", sss_inst)
root_inst.add_child("StarterPlayer", sp_inst)
sp_inst.add_child("StarterPlayerScripts", sps_inst)

file_to_inst = {}
path_to_modname = {}

def populate_tree(fs_dir, parent_inst):
    for entry in os.scandir(fs_dir):
        if entry.is_dir():
            dir_inst = Instance(entry.name, path=entry.path)
            parent_inst.add_child(entry.name, dir_inst)
            populate_tree(entry.path, dir_inst)
        elif entry.is_file() and (entry.name.endswith(".luau") or entry.name.endswith(".lua")):
            mod_name = entry.name.rsplit(".", 1)[0]
            if mod_name.endswith(".server") or mod_name.endswith(".client"):
                mod_name = mod_name.rsplit(".", 1)[0]
            file_inst = Instance(mod_name, path=entry.path)
            parent_inst.add_child(mod_name, file_inst)
            file_to_inst[entry.path] = file_inst
            path_to_modname[entry.path] = mod_name

populate_tree(os.path.join(SRC, "shared"), rs_inst)
populate_tree(os.path.join(SRC, "server"), sss_inst)
populate_tree(os.path.join(SRC, "client"), sps_inst)

def eval_expr(current_file, expr):
    curr_inst = file_to_inst.get(current_file)
    if not curr_inst:
        return None, "File not in DOM tree"

    expr_clean = expr.split('--')[0].strip()
    expr_clean = re.sub(r'::.*$', '', expr_clean).strip()
    expr_clean = re.sub(r':WaitForChild\(["\']([^"\']+)["\']\)', r'.\1', expr_clean)
    expr_clean = re.sub(r':FindFirstChild\(["\']([^"\']+)["\']\)', r'.\1', expr_clean)

    parts = [p.strip('"\' ') for p in expr_clean.split('.')]
    parts = [p for p in parts if p]

    if not parts:
        return None, "Empty expression"

    head = parts[0]
    node = None

    if head in ["ReplicatedStorage", 'game:GetService("ReplicatedStorage")', "game:GetService('ReplicatedStorage')"]:
        node = rs_inst
    elif head in ["ServerScriptService", 'game:GetService("ServerScriptService")', "game:GetService('ServerScriptService')"]:
        node = sss_inst
    elif head in ["StarterPlayerScripts", 'game:GetService("StarterPlayer").StarterPlayerScripts']:
        node = sps_inst
    elif head == "script":
        node = curr_inst
    else:
        return None, f"Dynamic: {head}"

    for idx, p in enumerate(parts[1:], 1):
        if p == "Parent":
            if node.parent:
                node = node.parent
            else:
                return None, f"Parent of root"
        else:
            if p in node.children:
                node = node.children[p]
            else:
                return None, f"Child '{p}' not found"

    return node, "Success"

# Build top-level static dependency graph (edges only for top-level static requires, i.e. required during module execution)
# Note: Requires inside functions are lazy requires and don't block module initialization.

top_level_deps = {}
all_deps = {}

for f_path in file_to_inst.keys():
    rel_f = os.path.relpath(f_path, SRC)
    top_level_deps[rel_f] = set()
    all_deps[rel_f] = set()

    with open(f_path, 'r', encoding='utf-8', errors='ignore') as file:
        lines = file.readlines()
        in_function = 0
        for idx, line in enumerate(lines, 1):
            line_str = line.strip()
            # Crude function tracking
            if re.search(r'\bfunction\b', line_str):
                in_function += line_str.count('function')
            if re.search(r'\bend\b', line_str):
                in_function -= line_str.count('end')
                if in_function < 0:
                    in_function = 0

            if 'require(' in line_str and not line_str.startswith('--'):
                m = re.search(r'require\((.*)\)', line_str)
                if m:
                    raw_expr = m.group(1).strip()
                    res_node, status = eval_expr(f_path, raw_expr)
                    if status == "Success" and res_node.path in file_to_inst:
                        target_rel = os.path.relpath(res_node.path, SRC)
                        all_deps[rel_f].add(target_rel)
                        if in_function == 0:
                            top_level_deps[rel_f].add(target_rel)

# Cycle detection in top_level_deps using DFS
cycles = []

def find_cycles(graph):
    visited = {}
    path = []
    
    def dfs(node):
        visited[node] = 1 # visiting
        path.append(node)
        
        for neighbor in graph.get(node, []):
            if visited.get(neighbor, 0) == 1:
                # Cycle found
                cycle_start = path.index(neighbor)
                cycles.append(path[cycle_start:] + [neighbor])
            elif visited.get(neighbor, 0) == 0:
                dfs(neighbor)
                
        path.pop()
        visited[node] = 2 # visited

    for node in list(graph.keys()):
        if visited.get(node, 0) == 0:
            dfs(node)

find_cycles(top_level_deps)

print(f"Top-level static dependency cycles found: {len(cycles)}")
if cycles:
    for c in cycles:
        print(" -> ".join(c))
else:
    print("NO TOP-LEVEL CIRCULAR DEPENDENCIES DETECTED!")
