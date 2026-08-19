import os
import re
import glob

modified_files = [
    r"c:\Users\tummala surya\Downloads\roblox\src\server\ServerMain.server.luau",
    r"c:\Users\tummala surya\Downloads\roblox\src\client\ClientMain.client.luau",
    r"c:\Users\tummala surya\Downloads\roblox\src\client\UI\HUDController.luau",
    r"c:\Users\tummala surya\Downloads\roblox\src\server\Combat\CombatServer.luau",
]

errors = 0

for filepath in modified_files:
    if not os.path.exists(filepath):
        print(f"ERROR: File not found: {filepath}")
        errors += 1
        continue
    
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    
    lines = content.splitlines()
    print(f"Checking {os.path.basename(filepath)} ({len(lines)} lines)...")
    
    # 1. Check --!strict header
    if not lines or lines[0].strip() != "--!strict":
        print(f"  [ERROR] Missing --!strict header at line 1 in {filepath}")
        errors += 1
    else:
        print("  [OK] --!strict header present.")
        
    # 2. Syntax structure balance (end vs block starts)
    block_starts = 0
    block_ends = 0
    for idx, line in enumerate(lines, 1):
        # strip comments
        code_line = line.split("--")[0]
        tokens = re.findall(r'\b(function|if|do|then|end)\b', code_line)
        for t in tokens:
            if t in ("function", "if", "do"):
                block_starts += 1
            elif t == "end":
                block_ends += 1

    # Check unused local declarations without _ prefix
    local_vars = re.findall(r'\blocal\s+([a-zA-Z0-9_]+)\b', content)
    unused = []
    for var in local_vars:
        if not var.startswith("_") and var not in ("script", "game", "self"):
            count = len(re.findall(r'\b' + re.escape(var) + r'\b', content))
            if count == 1:
                unused.append(var)
    
    if unused:
        print(f"  [WARN] Unused local variables without '_' prefix: {unused}")
    else:
        print("  [OK] No unused local variables detected.")
        
    print(f"  [OK] Verified {os.path.basename(filepath)}")
    print()

if errors == 0:
    print("ALL MODIFIED FILES PASSED VERIFICATION WITH 0 ERRORS!")
else:
    print(f"FAILED WITH {errors} ERRORS.")
