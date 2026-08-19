# Empirical Analysis — Milestone 2 Scraped Documentation Verification

## Executive Summary
- **Target Output Directory**: `c:\Users\tummala surya\Downloads\roblox\scraped_docs`
- **Scraped Files Evaluated**: 51 / 51 expected Markdown files across 24 subfolders.
- **Overall Empirical Verdict**: **REJECT**
- **Primary Failure Mode**: Code Block Formatting defects. 6 opening code fences across 3 files (`parts/model-generation.md`, `scripting/index.md`, `input/index.md`) are concatenated directly onto preceding headings/text without leading newlines or improperly placed inside table cells.

---

## 1. Subfolder Structure Integrity
- **Status**: **PASS**
- **Expected Files**: 51
- **Found Files**: 51
- **Missing Files**: 0
- **Extra / Unmapped Files**: 0
- **Directory Hierarchy Breakdown**:
  - `creation/`: `index.md`
  - `projects/`: `index.md`
  - `workspace/`: `index.md`, `camera.md`
  - `parts/`: `index.md`, `meshes.md`, `models.md`, `procedural-models.md`, `materials.md`, `terrain.md`, `model-generation.md`
  - `physics/`: `index.md`, `assemblies.md`, `network-ownership.md`, `mechanical-constraints.md`, `mover-constraints.md`, `sleep-system.md`, `adaptive-timestepping.md`, `units.md`
  - `effects/`: `index.md`
  - `scripting/`: `index.md`
  - `environment/`: `index.md`
  - `players/`: `index.md`
  - `characters/`: `index.md`
  - `input/`: `index.md`
  - `audio/`: `index.md`
  - `ui/`: `index.md`
  - `animation/`: `index.md`
  - `matchmaking/`: `index.md`
  - `performance-optimization/`: `index.md`
  - `cloud-services/`: `data-stores-vs-memory-stores.md`
  - `unity/`: `index.md`
  - `unreal/`: `index.md`
  - `discovery/`: `index.md`
  - `production/`: `game-design.md`, `monetization/index.md`, `monetization/developer-exchange.md`, `monetization/roblox-plus.md`, `monetization/robux-transfers.md`, `monetization/private-servers.md`, `monetization/subscriptions.md`, `monetization/passes.md`, `monetization/developer-products.md`, `monetization/commerce-products.md`, `monetization/shop.md`, `monetization/paid-access-robux.md`, `monetization/paid-access-local-currency.md`, `monetization/managed-pricing.md`
  - `monetization/`: `monetize-experiences.md`
  - `creator-rewards/`: `index.md`
  - `ip-licensing/`: `index.md`

---

## 2. Content Completeness
- **Status**: **PASS**
- **Total Byte Size**: 489,484 bytes (~478 KB)
- **Total Line Count**: 6,757 lines
- **Total Word Count**: 63,443 words
- **Average File Size**: 9,597.7 bytes
- **Average Line Count**: 132.5 lines
- **Small Files (<100B or <5 lines)**: 0
- **Zero-Byte Files**: 0
- **Heading Structure Audit**:
  - 51 / 51 files contain valid Markdown headings or YAML frontmatter title metadata.
  - Total Headings: 509 headings across 51 documents.
  - Heading Level Distribution: H1: 53, H2: 228, H3: 147, H4: 78, H5: 4, H6: 2.

---

## 3. Code Block Formatting & Syntax Tags
- **Status**: **FAIL / REJECT**
- **Total Triple-Backtick Markers**: 101 lines containing ` ``` `.
- **Properly Delimited Fenced Code Blocks**: 40 blocks.
  - Language Tag Breakdown: `lua` (36 blocks), `text` (3 blocks), `mermaid` (1 block).
- **Defects Identified**:
  1. **Concatenated Opening Fences (5 instances)**:
     - `scraped_docs/scripting/index.md:L102`: `5. Add the following code to the file:```lua`
     - `scraped_docs/scripting/index.md:L113`: `7. [Run your game](/docs/en-us/studio/testing-modes.md#playtesting) and note the output:```text`
     - `scraped_docs/scripting/index.md:L137`: `2. Add the following code to the file:```lua`
     - `scraped_docs/parts/model-generation.md:L114`: `...speedometer.```lua`
     - `scraped_docs/parts/model-generation.md:L166`: `...player input.```lua`
  2. **Malformed Table Cell Fence (1 instance)**:
     - `scraped_docs/input/index.md:L107`: `| Toggle backpack | ``` | N/A | N/A |`
     - Inserts an unmatched 3-backtick sequence inside a table row, corrupting Markdown block parsing for the file.

---

## 4. Link Structure Analysis
- **Status**: **PASS**
- **Total Markdown Links Extracted**: 981 links.
- **Link Types Breakdown**:
  - Internal `/docs/...` links: 529 (53.9%)
  - External HTTP/HTTPS links: 97 (9.9%)
  - Local Anchor `#...` links: 173 (17.6%)
  - Other relative links: 182 (18.6%)
- **Syntax Integrity**: 0 unclosed brackets, 0 empty link targets `[]()`.
- **Note**: Internal links point to valid Roblox documentation endpoints across the full documentation graph.

---

## Verdict Summary
- **Subfolder Structure**: PASS
- **Content Completeness**: PASS
- **Code Block Formatting**: **FAIL**
- **Link Structure**: PASS
- **Overall Milestone 2 Verdict**: **REJECT**
