import os
import re
import json
import subprocess

PROJECT_ROOT = r"c:\Users\tummala surya\Downloads\roblox"
SRC_DIR = os.path.join(PROJECT_ROOT, "src")

# Gather all .luau files in src
files_by_dir = {
    "shared": [],
    "server": [],
    "client": []
}

all_src_files = []
for root, dirs, files in os.walk(SRC_DIR):
    for f in files:
        if f.endswith(".luau"):
            rel_path = os.path.relpath(os.path.join(root, f), PROJECT_ROOT)
            rel_norm = rel_path.replace("\\", "/")
            all_src_files.append(rel_norm)
            if rel_norm.startswith("src/shared/"):
                files_by_dir["shared"].append(rel_norm)
            elif rel_norm.startswith("src/server/"):
                files_by_dir["server"].append(rel_norm)
            elif rel_norm.startswith("src/client/"):
                files_by_dir["client"].append(rel_norm)

print("=== FILE COUNT SUMMARY ===")
print(f"Total files in src/: {len(all_src_files)}")
print(f"  src/shared: {len(files_by_dir['shared'])}")
print(f"  src/server: {len(files_by_dir['server'])}")
print(f"  src/client: {len(files_by_dir['client'])}")

# Check for .luau files in .agents directory
agents_files = []
AGENTS_DIR = os.path.join(PROJECT_ROOT, ".agents")
for root, dirs, files in os.walk(AGENTS_DIR):
    for f in files:
        if f.endswith(".luau") or f.endswith(".lua"):
            agents_files.append(os.path.relpath(os.path.join(root, f), PROJECT_ROOT))

print(f"\n.agents/ folder Luau file count: {len(agents_files)}")
if agents_files:
    print("  Violations:", agents_files)

# Check API cross contamination
contamination_findings = []

for rel_path in all_src_files:
    full_path = os.path.join(PROJECT_ROOT, rel_path)
    with open(full_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Shared checks
    if rel_path.startswith("src/shared/"):
        if "DataStoreService" in content:
            contamination_findings.append((rel_path, "DataStoreService in shared"))
        if "UserInputService" in content:
            contamination_findings.append((rel_path, "UserInputService in shared"))
        if "ContextActionService" in content:
            contamination_findings.append((rel_path, "ContextActionService in shared"))
        if "GuiService" in content:
            contamination_findings.append((rel_path, "GuiService in shared"))
        if "Players.LocalPlayer" in content or 'game:GetService("Players").LocalPlayer' in content:
            contamination_findings.append((rel_path, "LocalPlayer in shared"))

    # Server checks
    elif rel_path.startswith("src/server/"):
        if "UserInputService" in content:
            contamination_findings.append((rel_path, "UserInputService in server"))
        if "ContextActionService" in content:
            contamination_findings.append((rel_path, "ContextActionService in server"))
        if "GuiService" in content:
            contamination_findings.append((rel_path, "GuiService in server"))
        if re.search(r'Players\.LocalPlayer\b', content) or re.search(r'game:GetService\("Players"\)\.LocalPlayer\b', content):
            contamination_findings.append((rel_path, "LocalPlayer property reference in server"))

    # Client checks
    elif rel_path.startswith("src/client/"):
        if "DataStoreService" in content:
            contamination_findings.append((rel_path, "DataStoreService in client"))
        if 'game:GetService("ServerScriptService")' in content:
            contamination_findings.append((rel_path, "ServerScriptService reference in client"))
        if 'game:GetService("ServerStorage")' in content:
            contamination_findings.append((rel_path, "ServerStorage reference in client"))

print(f"\n=== API CROSS-CONTAMINATION FINDINGS ===")
print(f"Total findings: {len(contamination_findings)}")
for path, desc in contamination_findings:
    print(f"  {path}: {desc}")

# Require validation check
print(f"\n=== AUDITING REQUIRES ===")
unresolved_requires = []
for rel_path in all_src_files:
    full_path = os.path.join(PROJECT_ROOT, rel_path)
    with open(full_path, "r", encoding="utf-8") as f:
        lines = f.readlines()
    for line_idx, line in enumerate(lines, 1):
        if "require(" in line:
            # Check for illegal server-requiring-client
            if rel_path.startswith("src/server/") and "StarterPlayer" in line:
                unresolved_requires.append((rel_path, line_idx, line.strip(), "Server requires StarterPlayer"))
            if rel_path.startswith("src/shared/") and ("StarterPlayer" in line or "ServerScriptService" in line):
                unresolved_requires.append((rel_path, line_idx, line.strip(), "Shared requires Server/Client service"))

print(f"Total illegal require findings: {len(unresolved_requires)}")
for path, lno, text, desc in unresolved_requires:
    print(f"  {path}:{lno}: {desc} -> {text}")

# Check Rojo build
print(f"\n=== ROJO BUILD CHECK ===")
cmd = [os.path.join(PROJECT_ROOT, "rojo.exe"), "build", "default.project.json", "-o", "RivalsParadigm.rbxl"]
res = subprocess.run(cmd, cwd=PROJECT_ROOT, capture_output=True, text=True)
print(f"Rojo Exit Code: {res.returncode}")
print(f"Rojo Output: {res.stdout.strip()}")
if res.stderr:
    print(f"Rojo Errors: {res.stderr.strip()}")
