import os
import sys
import re
import json
import subprocess

PROJECT_ROOT = r"c:\Users\tummala surya\Downloads\roblox"
SRC_DIR = os.path.join(PROJECT_ROOT, "src")

def remove_luau_comments_and_strings(code):
    """
    Strips out all Luau strings and comments safely using regex / state machine.
    """
    output = []
    i = 0
    n = len(code)
    
    while i < n:
        # Multi-line comment --[=*[ ... ]=*]
        if code.startswith("--[", i):
            # Check for --[=*[
            match = re.match(r'--\[(=*)\[', code[i:])
            if match:
                eq_len = len(match.group(1))
                closing = "]" + "=" * eq_len + "]"
                end_idx = code.find(closing, i + len(match.group(0)))
                if end_idx != -1:
                    i = end_idx + len(closing)
                    continue
                else:
                    # Unterminated block comment
                    i = n
                    continue
            else:
                # Single line comment -- ...
                end_idx = code.find('\n', i)
                if end_idx != -1:
                    i = end_idx + 1
                    continue
                else:
                    i = n
                    continue
        elif code.startswith("--", i):
            end_idx = code.find('\n', i)
            if end_idx != -1:
                i = end_idx + 1
                continue
            else:
                i = n
                continue
        # Multi-line string [=*[ ... ]=*]
        elif code.startswith("[", i):
            match = re.match(r'\[(=*)\[', code[i:])
            if match:
                eq_len = len(match.group(1))
                closing = "]" + "=" * eq_len + "]"
                end_idx = code.find(closing, i + len(match.group(0)))
                if end_idx != -1:
                    i = end_idx + len(closing)
                    output.append('""')
                    continue
                else:
                    output.append(code[i])
                    i += 1
            else:
                output.append(code[i])
                i += 1
        # Single or Double quoted string
        elif code[i] in ('"', "'"):
            quote = code[i]
            i += 1
            start = i
            escaped = False
            while i < n:
                if escaped:
                    escaped = False
                elif code[i] == '\\':
                    escaped = True
                elif code[i] == quote:
                    i += 1
                    break
                i += 1
            output.append('""')
        else:
            output.append(code[i])
            i += 1
            
    return "".join(output)

def check_file_brackets_and_keywords(filepath, content):
    clean = remove_luau_comments_and_strings(content)
    
    parens = clean.count('(') - clean.count(')')
    braces = clean.count('{') - clean.count('}')
    brackets = clean.count('[') - clean.count(']')
    
    errors = []
    if parens != 0:
        errors.append(f"Unbalanced parentheses: open={clean.count('(')}, close={clean.count(')')}, diff={parens}")
    if braces != 0:
        errors.append(f"Unbalanced braces: open={clean.count('{')}, close={clean.count('}')}, diff={braces}")
    if brackets != 0:
        errors.append(f"Unbalanced brackets: open={clean.count('[')}, close={clean.count(']')}, diff={brackets}")
        
    return errors, clean

# Run verification
results = {
    "total_files": 0,
    "bracket_errors": [],
    "contamination_errors": [],
    "legacy_brand_references": [],
    "rojo_build_passed": False
}

luau_files = []
for root, dirs, files in os.walk(SRC_DIR):
    for f in files:
        if f.endswith(".luau"):
            luau_files.append(os.path.relpath(os.path.join(root, f), PROJECT_ROOT))

results["total_files"] = len(luau_files)

for rel_path in luau_files:
    full_path = os.path.join(PROJECT_ROOT, rel_path)
    with open(full_path, "r", encoding="utf-8") as f:
        code = f.read()
    
    errs, clean_code = check_file_brackets_and_keywords(rel_path, code)
    if errs:
        results["bracket_errors"].append((rel_path, errs))

print(f"Total files checked: {results['total_files']}")
print(f"Bracket Balance Errors: {len(results['bracket_errors'])}")
for path, errs in results["bracket_errors"]:
    print(f"  {path}: {errs}")
