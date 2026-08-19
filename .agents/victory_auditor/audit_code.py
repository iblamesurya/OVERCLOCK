import os
import glob
import re

src_dir = r"c:\Users\tummala surya\Downloads\roblox\src"
luau_files = glob.glob(os.path.join(src_dir, "**", "*.luau"), recursive=True)

print(f"Auditing {len(luau_files)} Luau files...\n")

missing_strict = []
stubs_found = []
fonts_found = set()
invalid_fonts = []

for fpath in luau_files:
    rel_path = os.path.relpath(fpath, src_dir)
    with open(fpath, "r", encoding="utf-8") as f:
        content = f.read()
        lines = content.splitlines()

    # Check 1: Strict mode
    if not lines or "--!strict" not in lines[0]:
        missing_strict.append(rel_path)

    # Check 2: Stubs/TODOs/Dummy functions
    if re.search(r"\b(TODO|FIXME|NOT_IMPLEMENTED|mock|placeholder|fake|stub)\b", content, re.IGNORECASE):
        # Ignore normal comments if valid logic exists, but flag for review
        matches = re.findall(r".*\b(TODO|FIXME|NOT_IMPLEMENTED|mock|placeholder|fake|stub)\b.*", content, re.IGNORECASE)
        stubs_found.append((rel_path, matches))

    # Check 3: Font usage
    font_matches = re.findall(r"Enum\.Font\.([A-Za-z0-9_]+)", content)
    for font in font_matches:
        fonts_found.add(font)
        # Check valid Roblox fonts
        valid_roblox_fonts = {
            "Gotham", "GothamBold", "GothamBlack", "GothamMedium",
            "Arial", "ArialBold", "SourceSans", "SourceSansBold", "SourceSansItalic",
            "Roboto", "RobotoMono", "FredokaOne", "LuckiestGuy", "Michroma", "Nunito",
            "Foundation", "Standard", "BuilderSans", "BuilderSansBold"
        }
        if font not in valid_roblox_fonts:
            invalid_fonts.append((rel_path, font))

print("=== 1. STRICT MODE CHECK ===")
if missing_strict:
    print(f"FAIL: {len(missing_strict)} files missing --!strict header: {missing_strict}")
else:
    print("PASS: All 51 files contain --!strict header.")

print("\n=== 2. POTENTIAL STUBS / TODOS CHECK ===")
if stubs_found:
    print(f"Found potential keywords in {len(stubs_found)} files:")
    for path, matches in stubs_found:
        print(f"  {path}: {matches[:3]}")
else:
    print("PASS: No stubs/TODOs/placeholders found.")

print("\n=== 3. FONT USAGE CHECK ===")
print(f"Fonts used: {fonts_found}")
if invalid_fonts:
    print(f"FAIL: Invalid fonts found: {invalid_fonts}")
else:
    print("PASS: All referenced fonts are valid Roblox engine fonts.")
