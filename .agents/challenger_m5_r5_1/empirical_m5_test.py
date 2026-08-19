import os
import sys
import re
import json
import subprocess

PROJECT_ROOT = r"c:\Users\tummala surya\Downloads\roblox"
SRC_DIR = os.path.join(PROJECT_ROOT, "src")

results = {
    "file_count": 0,
    "file_list": [],
    "syntax_errors": [],
    "contamination_errors": [],
    "require_errors": [],
    "agent_dir_violations": [],
    "legacy_brand_warnings": [],
    "rojo_build_passed": False,
    "rojo_build_output": ""
}

# 1. Collect all .luau files in src
for root, dirs, files in os.walk(SRC_DIR):
    for f in files:
        if f.endswith(".luau"):
            rel_path = os.path.relpath(os.path.join(root, f), PROJECT_ROOT)
            results["file_list"].append(rel_path)

results["file_count"] = len(results["file_list"])

# Check for any .luau files in .agents directory (violates layout compliance rule)
AGENTS_DIR = os.path.join(PROJECT_ROOT, ".agents")
for root, dirs, files in os.walk(AGENTS_DIR):
    for f in files:
        if f.endswith(".luau") or f.endswith(".lua"):
            rel_path = os.path.relpath(os.path.join(root, f), PROJECT_ROOT)
            results["agent_dir_violations"].append(rel_path)

# 2. Syntax / Tokenizer check for Luau files
BLOCK_START_KEYWORDS = {"do", "then", "repeat"}
# 'function' can start a block if not followed immediately by 'end' or in type def
# 'if' opens a block requiring 'then'
# 'for' / 'while' open blocks requiring 'do'

def check_luau_syntax(filepath, content):
    errors = []
    # Strip string literals and comments to do bracket & keyword balance check
    # 1. Multi-line comments --[[ ... ]]
    # 2. Single line comments -- ...
    # 3. Multiline strings [=[ ... ]=]
    # 4. Single/double quote strings
    
    # Check simple bracket matching first
    lines = content.splitlines()
    
    # Simple line-by-line syntax sanity checks
    # E.g. unclosed string literal on non-multiline string, invalid tokens
    in_multiline_comment = False
    in_multiline_string = False
    multiline_eq_count = 0

    # Lua stack tracking for block keywords
    stack = []
    
    # Tokenize stripped code to check keyword balance
    clean_code = re.sub(r'--\[\[.*?\]\]', '', content, flags=re.DOTALL) # block comments
    clean_code = re.sub(r'--[^\n]*', '', clean_code) # line comments
    
    # Strings replacement
    clean_code = re.sub(r'"([^"\\]|\\.)*"', '""', clean_code)
    clean_code = re.sub(r"'([^'\\]|\\.)*'", "''", clean_code)
    clean_code = re.sub(r'\[=*\[.*?\]=*\]', '""', clean_code, flags=re.DOTALL)
    
    # Count open/close parentheses, braces, brackets
    parens = clean_code.count('(') - clean_code.count(')')
    braces = clean_code.count('{') - clean_code.count('}')
    brackets = clean_code.count('[') - clean_code.count(']')

    if parens != 0:
        errors.append(f"Unbalanced parentheses: delta = {parens}")
    if braces != 0:
        errors.append(f"Unbalanced braces: delta = {braces}")
    if brackets != 0:
        errors.append(f"Unbalanced brackets: delta = {brackets}")

    # Check Lua keyword balance (function, if, for, while, do, repeat, until, end)
    tokens = re.findall(r'\b[a-zA-Z_][a-zA-Z0-9_]*\b', clean_code)
    
    # Count functions, ifs, for/while, repeats vs end/until
    # Note: 'type' or local function can be declarations, type functions, etc.
    # In Luau, 'function' opens block, 'do' opens block, 'then' opens block, 'repeat' opens block.
    # 'end' closes function, do/then block.
    # 'until' closes repeat block.
    
    end_count = tokens.count('end')
    until_count = tokens.count('until')
    
    do_count = tokens.count('do')
    then_count = tokens.count('then')
    repeat_count = tokens.count('repeat')
    
    # 'function' can be anonymous or named, each function requires an 'end'
    # Count occurrences of 'function' keyword
    fn_count = tokens.count('function')
    
    expected_ends = fn_count + do_count + then_count
    
    if end_count != expected_ends:
        # Check if difference is due to type functions or interface edge cases
        errors.append(f"Keyword balance mismatch: 'end' count={end_count}, expected (fn+do+then)={expected_ends} (fn={fn_count}, do={do_count}, then={then_count})")
        
    if repeat_count != until_count:
        errors.append(f"Repeat/until mismatch: repeat={repeat_count}, until={until_count}")
        
    return errors

for rel_path in results["file_list"]:
    full_path = os.path.join(PROJECT_ROOT, rel_path)
    with open(full_path, "r", encoding="utf-8") as f:
        code = f.read()
    
    syn_errs = check_luau_syntax(rel_path, code)
    if syn_errs:
        results["syntax_errors"].append((rel_path, syn_errs))

# 3. Check for API Cross-Contamination
for rel_path in results["file_list"]:
    full_path = os.path.join(PROJECT_ROOT, rel_path)
    with open(full_path, "r", encoding="utf-8") as f:
        code = f.read()
    
    rel_normalized = rel_path.replace("\\", "/")
    
    # Client script checks
    if rel_normalized.startswith("src/client/"):
        if "DataStoreService" in code:
            results["contamination_errors"].append(f"{rel_path}: Client script references DataStoreService!")
        if "ServerScriptService" in code and "game:GetService(\"ServerScriptService\")" in code:
            results["contamination_errors"].append(f"{rel_path}: Client script references ServerScriptService!")
        if "ServerStorage" in code and "game:GetService(\"ServerStorage\")" in code:
            results["contamination_errors"].append(f"{rel_path}: Client script references ServerStorage!")

    # Server script checks
    elif rel_normalized.startswith("src/server/"):
        if "UserInputService" in code:
            results["contamination_errors"].append(f"{rel_path}: Server script references UserInputService!")
        if "ContextActionService" in code:
            results["contamination_errors"].append(f"{rel_path}: Server script references ContextActionService!")
        if "GuiService" in code:
            results["contamination_errors"].append(f"{rel_path}: Server script references GuiService!")
        if re.search(r'game(?::GetService\("Players"\)|\.Players)\.LocalPlayer', code) or re.search(r'Players\.LocalPlayer', code):
            results["contamination_errors"].append(f"{rel_path}: Server script references LocalPlayer property!")

    # Shared script checks
    elif rel_normalized.startswith("src/shared/"):
        if "DataStoreService" in code:
            results["contamination_errors"].append(f"{rel_path}: Shared script references DataStoreService!")
        if "UserInputService" in code:
            results["contamination_errors"].append(f"{rel_path}: Shared script references UserInputService!")
        if "ContextActionService" in code:
            results["contamination_errors"].append(f"{rel_path}: Shared script references ContextActionService!")
        if "GuiService" in code:
            results["contamination_errors"].append(f"{rel_path}: Shared script references GuiService!")
        if re.search(r'Players\.LocalPlayer', code):
            results["contamination_errors"].append(f"{rel_path}: Shared script references LocalPlayer!")

# 4. Require path checking
for rel_path in results["file_list"]:
    full_path = os.path.join(PROJECT_ROOT, rel_path)
    with open(full_path, "r", encoding="utf-8") as f:
        code = f.read()
    
    # Find requires like require(ReplicatedStorage.Data.WeaponStats) or require(script.Parent.Foo)
    requires = re.findall(r'require\(([^)]+)\)', code)
    for req in requires:
        req_clean = req.strip()
        # Basic audit of services in requires
        if "StarterPlayer" in req_clean and rel_normalized.startswith("src/server/"):
            results["require_errors"].append(f"{rel_path}: Server requiring StarterPlayer ({req_clean})")

# 5. Check for leftover brand name RIVALS-PARADIGM in code comments or string constants (ignoring default.project.json build output config if appropriate)
for rel_path in results["file_list"]:
    full_path = os.path.join(PROJECT_ROOT, rel_path)
    with open(full_path, "r", encoding="utf-8") as f:
        code = f.read()
    
    if "RIVALS-PARADIGM" in code:
        results["legacy_brand_warnings"].append(f"{rel_path}: Contains legacy string 'RIVALS-PARADIGM'")

# 6. Test Rojo build
try:
    cmd = [os.path.join(PROJECT_ROOT, "rojo.exe"), "build", "default.project.json", "-o", "RivalsParadigm.rbxl"]
    res = subprocess.run(cmd, cwd=PROJECT_ROOT, capture_output=True, text=True, timeout=30)
    results["rojo_build_output"] = res.stdout + "\n" + res.stderr
    if res.returncode == 0 and "Built project" in res.stdout:
        results["rojo_build_passed"] = True
    else:
        results["rojo_build_passed"] = False
except Exception as e:
    results["rojo_build_output"] = str(e)
    results["rojo_build_passed"] = False

# Print summary report
print("=== EMPIRICAL VERIFICATION REPORT ===")
print(f"Total Luau files in src/: {results['file_count']}")
print(f"Files in .agents directory: {len(results['agent_dir_violations'])}")
if results["agent_dir_violations"]:
    print("  Violations:", results["agent_dir_violations"])

print(f"Syntax Check Errors: {len(results['syntax_errors'])}")
for path, errs in results["syntax_errors"]:
    print(f"  {path}: {errs}")

print(f"API Cross-Contamination Errors: {len(results['contamination_errors'])}")
for err in results["contamination_errors"]:
    print(f"  {err}")

print(f"Require Statement Errors: {len(results['require_errors'])}")
for err in results["require_errors"]:
    print(f"  {err}")

print(f"Legacy Branding Warnings: {len(results['legacy_brand_warnings'])}")
for warn in results["legacy_brand_warnings"]:
    print(f"  {warn}")

print(f"Rojo Build Passed: {results['rojo_build_passed']}")
print(f"Rojo Output:\n{results['rojo_build_output'].strip()}")

# Write JSON output for detailed verification
with open(os.path.join(os.path.dirname(__file__), "empirical_results.json"), "w") as f:
    json.dump(results, f, indent=2)
