import re
from test_cleaner import clean_markdown

with open(r"c:\Users\tummala surya\Downloads\roblox\scraped_docs\scripting\index.md", "r", encoding="utf-8") as f:
    s_content = f.read()
cleaned_s = clean_markdown(s_content)

print("=== SCRIPTING SNIPPET ===")
for line in cleaned_s.splitlines()[95:120]:
    print(line.encode('ascii', 'backslashreplace').decode('ascii'))

with open(r"c:\Users\tummala surya\Downloads\roblox\scraped_docs\parts\model-generation.md", "r", encoding="utf-8") as f:
    m_content = f.read()
cleaned_m = clean_markdown(m_content)

print("\n=== MODEL-GENERATION SNIPPET 1 ===")
for line in cleaned_m.splitlines()[110:130]:
    print(line.encode('ascii', 'backslashreplace').decode('ascii'))

print("\n=== MODEL-GENERATION SNIPPET 2 ===")
for line in cleaned_m.splitlines()[160:185]:
    print(line.encode('ascii', 'backslashreplace').decode('ascii'))

with open(r"c:\Users\tummala surya\Downloads\roblox\scraped_docs\input\index.md", "r", encoding="utf-8") as f:
    i_content = f.read()
cleaned_i = clean_markdown(i_content)

print("\n=== INPUT SNIPPET ===")
for line in cleaned_i.splitlines()[104:110]:
    print(line.encode('ascii', 'backslashreplace').decode('ascii'))
