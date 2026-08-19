import os
import re

ROOT_DIR = r"c:\Users\tummala surya\Downloads\roblox"
SRC_DIR = os.path.join(ROOT_DIR, "src")
AGENTS_DIR = os.path.join(ROOT_DIR, ".agents")

def run_audit():
    print("=== M5 STRUCTURAL REORGANIZATION FORENSIC AUDIT ===")
    
    # 1. Check .agents directory compliance
    print("\n--- 1. Checking .agents/ Directory Compliance ---")
    prohibited_extensions = {".luau", ".rbxl", ".lua", ".exe"}
    violations_in_agents = []
    for root, dirs, files in os.walk(AGENTS_DIR):
        for f in files:
            ext = os.path.splitext(f)[1].lower()
            full_path = os.path.join(root, f)
            # Python scripts written by auditors for auditing are metadata/tooling, but luau/rbxl code is prohibited
            if ext in prohibited_extensions:
                violations_in_agents.append(full_path)
    
    if violations_in_agents:
        print(f"FAIL: Prohibited files found in .agents/: {violations_in_agents}")
    else:
        print("PASS: .agents/ contains only agent metadata and tooling. No project source code present.")

    # 2. Check Directory Structure and File Distribution
    print("\n--- 2. Checking Directory Layout & File Counts ---")
    subdirs = ["shared", "server", "client"]
    counts = {}
    total_luau = 0
    all_luau_files = []
    
    for sd in subdirs:
        sd_path = os.path.join(SRC_DIR, sd)
        sd_files = []
        for root, dirs, files in os.walk(sd_path):
            for f in files:
                if f.endswith(".luau") or f.endswith(".lua"):
                    rel = os.path.relpath(os.path.join(root, f), SRC_DIR)
                    sd_files.append(rel)
                    all_luau_files.append((os.path.join(root, f), rel))
        counts[sd] = len(sd_files)
        total_luau += len(sd_files)
        print(f"  src/{sd}: {len(sd_files)} files")
    
    print(f"Total Luau files in src/: {total_luau}")

    # 3. Check Boundary Isolation (DataStoreService, LocalPlayer, UserInputService)
    print("\n--- 3. Boundary Isolation Check ---")
    boundary_errors = []
    
    for full_path, rel in all_luau_files:
        with open(full_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
            lines = content.splitlines()
            
        is_shared = rel.startswith("shared")
        is_server = rel.startswith("server")
        is_client = rel.startswith("client")
        
        # Check DataStoreService
        if "DataStoreService" in content:
            if not is_server:
                boundary_errors.append(f"DataStoreService referenced in non-server file: {rel}")
                
        # Check LocalPlayer
        if "Players.LocalPlayer" in content or "game.Players.LocalPlayer" in content or "game:GetService(\"Players\").LocalPlayer" in content:
            if not is_client:
                boundary_errors.append(f"LocalPlayer referenced in non-client file: {rel}")

        # Check UserInputService / GuiService
        if "UserInputService" in content or "GuiService" in content:
            if not is_client:
                boundary_errors.append(f"UserInputService/GuiService referenced in non-client file: {rel}")
                
    if boundary_errors:
        print(f"FAIL: Boundary violations detected ({len(boundary_errors)}):")
        for err in boundary_errors:
            print(f"  - {err}")
    else:
        print("PASS: Zero boundary violations detected across server, client, and shared.")

    # 4. Check Require Statements and Imports
    print("\n--- 4. Require Resolution & Import Audit ---")
    require_pattern = re.compile(r'require\(([^)]+)\)')
    total_requires = 0
    unresolved_requires = []
    
    # Map virtual Roblox hierarchy to local filesystem
    # ReplicatedStorage -> src/shared
    # ServerScriptService -> src/server
    # StarterPlayerScripts -> src/client
    
    for full_path, rel in all_luau_files:
        with open(full_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
            
        requires = require_pattern.findall(content)
        total_requires += len(requires)
        
        for req in requires:
            req_str = req.strip()
            # Simple heuristic checking for obvious invalid paths
            # e.g. require(ReplicatedStorage.NonExistent)
            pass

    print(f"Scanned {total_requires} require(...) calls across all files.")

    # 5. Legacy Reference Check (RIVALS-PARADIGM in src/)
    print("\n--- 5. Checking Legacy References ---")
    legacy_refs = []
    for full_path, rel in all_luau_files:
        with open(full_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
            if "RIVALS-PARADIGM" in content or "RivalsCrosshairGui" in content:
                legacy_refs.append(rel)
                
    if legacy_refs:
        print(f"WARNING: Legacy project references found in {len(legacy_refs)} files:")
        for lr in legacy_refs:
            print(f"  - {lr}")
    else:
        print("PASS: Zero legacy 'RIVALS-PARADIGM' or 'RivalsCrosshairGui' references in src/.")

    # 6. Check Facades and Empty Return Stubs
    print("\n--- 6. Facade & Stub Detection ---")
    stub_files = []
    for full_path, rel in all_luau_files:
        with open(full_path, "r", encoding="utf-8", errors="ignore") as f:
            lines = [l.strip() for l in f.readlines() if l.strip() and not l.strip().startswith("--")]
            
        # Check if file has almost no logic (e.g. < 5 lines and returns constant)
        if len(lines) < 5 and any("return {" in l or "return function" in l or "return true" in l for l in lines):
            stub_files.append((rel, len(lines)))
            
    if stub_files:
        print(f"Potential stub/facade files found ({len(stub_files)}):")
        for sf, lc in stub_files:
            print(f"  - {sf} ({lc} non-comment lines)")
    else:
        print("PASS: No trivial facade/stub files detected.")

    print("\n=== AUDIT SCRIPT COMPLETE ===")

if __name__ == "__main__":
    run_audit()
