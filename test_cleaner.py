import re

def clean_markdown(content):
    # 1. Fix malformed fence marker in table row cells (e.g. | Toggle backpack | ``` | N/A | N/A |)
    content = re.sub(r'\|\s*```\s*\|', r'| `\\` ` |', content)

    # 2. Fix inline headings (e.g., "text. #### Heading Text")
    # First, handle heading followed immediately by paragraph text on the same line:
    # e.g., "#### Car This example generates..." -> "\n\n#### Car\n\nThis example generates..."
    # e.g., "#### Airplane This example generates..." -> "\n\n#### Airplane\n\nThis example generates..."
    # e.g., "#### Material To apply..." -> "\n\n#### Material\n\nTo apply..."
    # e.g., "#### Colormap To apply..." -> "\n\n#### Colormap\n\nTo apply..."
    
    # Let's fix specific pattern: (preceding_text) (#### Heading) (paragraph_text)
    # Match: ([^\n])\s*(#{1,6}\s+[A-Z][A-Za-z0-9_]*)\s+([A-Z][a-z]+)
    def fix_inline_heading(match):
        prefix = match.group(1)
        heading = match.group(2)
        following = match.group(3)
        return f"{prefix}\n\n{heading}\n\n{following}"

    # Fix heading concatenated after text (e.g. "generate. #### Car")
    content = re.sub(r'([^\n])\s*(#{1,6}\s+[A-Z][A-Za-z0-9_]*)\s+([A-Z])', fix_inline_heading, content)

    # 3. Fix code block fences concatenated directly onto preceding text without leading newline
    # Match any non-newline character preceding ``` (excluding table lines which were already handled)
    # We split into lines or use regex with negative lookbehind if possible, or line processing
    lines = content.split('\n')
    new_lines = []
    for line in lines:
        if line.strip().startswith('|'):
            new_lines.append(line)
            continue
        
        # Check if ``` is embedded in line after text
        # e.g. "text:```lua" -> "text:\n\n```lua"
        if '```' in line and not line.strip().startswith('```'):
            # Replace occurrences of non-newline + ```
            # Note: line doesn't contain \n, so regex r'([^\s])(```[a-zA-Z0-9_-]*)' or r'(.+?)(```[a-zA-Z0-9_-]*)'
            subbed = re.sub(r'(.+?)(```[a-zA-Z0-9_-]*)', r'\1\n\n\2', line)
            new_lines.append(subbed)
        else:
            new_lines.append(line)

    content = '\n'.join(new_lines)

    # Clean up excess newlines (3 or more -> 2)
    content = re.sub(r'\n{3,}', '\n\n', content)
    return content

# Test on scripting/index.md
with open(r"c:\Users\tummala surya\Downloads\roblox\scraped_docs\scripting\index.md", "r", encoding="utf-8") as f:
    s_content = f.read()

cleaned_s = clean_markdown(s_content)
print("Scripting clean diff check:")
print("Contains ':```'?", ':```' in cleaned_s)

# Test on parts/model-generation.md
with open(r"c:\Users\tummala surya\Downloads\roblox\scraped_docs\parts\model-generation.md", "r", encoding="utf-8") as f:
    m_content = f.read()

cleaned_m = clean_markdown(m_content)
print("Model-generation clean diff check:")
print("Contains '.```'?", '.```' in cleaned_m)
print("Contains '#### Car This'?", '#### Car This' in cleaned_m)

# Test on input/index.md
with open(r"c:\Users\tummala surya\Downloads\roblox\scraped_docs\input\index.md", "r", encoding="utf-8") as f:
    i_content = f.read()

cleaned_i = clean_markdown(i_content)
print("Input clean diff check:")
print("Contains '| ``` |'?", '| ``` |' in cleaned_i)
