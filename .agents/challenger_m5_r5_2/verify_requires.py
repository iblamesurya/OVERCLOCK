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

populate_tree(os.path.join(SRC, "shared"), rs_inst)
populate_tree(os.path.join(SRC, "server"), sss_inst)
populate_tree(os.path.join(SRC, "client"), sps_inst)

def eval_expr(current_file, expr):
    curr_inst = file_to_inst.get(current_file)
    if not curr_inst:
        return None, "File not in DOM tree"

    # Step 1: remove comments and type casts
    expr_clean = expr.split('--')[0].strip()
    expr_clean = re.sub(r'::.*$', '', expr_clean).strip()

    # Step 2: Replace method calls with dots
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
        return None, f"Dynamic/Variable: {head}"

    for idx, p in enumerate(parts[1:], 1):
        if p == "Parent":
            if node.parent:
                node = node.parent
            else:
                return None, f"Attempted to access Parent of root at index {idx}"
        else:
            if p in node.children:
                node = node.children[p]
            else:
                return None, f"Child '{p}' not found in '{node.name}' (at index {idx} in {parts})"

    return node, "Success"

broken = []
dynamic = []
valid = []

for f_path, f_inst in file_to_inst.items():
    rel_f = os.path.relpath(f_path, SRC)
    with open(f_path, 'r', encoding='utf-8', errors='ignore') as file:
        for idx, line in enumerate(file.readlines(), 1):
            line_str = line.strip()
            if 'require(' in line_str and not line_str.startswith('--'):
                # Extract require argument
                m = re.search(r'require\((.*)\)', line_str)
                if m:
                    raw_expr = m.group(1).strip()
                    res_node, status = eval_expr(f_path, raw_expr)
                    if status == "Success":
                        valid.append((rel_f, idx, line_str, res_node.path))
                    elif "Dynamic" in status:
                        dynamic.append((rel_f, idx, line_str, status))
                    else:
                        broken.append((rel_f, idx, line_str, status, raw_expr))

print(f"Total require statements evaluated: {len(valid) + len(dynamic) + len(broken)}")
print(f"Valid static require targets found: {len(valid)}")
print(f"Dynamic/Variable require targets: {len(dynamic)}")
print(f"Broken require targets found: {len(broken)}")

if broken:
    print("\n--- BROKEN REQUIRES ---")
    for b in broken:
        print(f"File {b[0]}:{b[1]} -> {b[2]}\n  Reason: {b[3]} (Expr: {b[4]})\n")
