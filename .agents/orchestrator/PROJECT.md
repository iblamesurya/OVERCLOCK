# Project: Roblox Creator Documentation Scraper

## Architecture
- Target Directory: `c:\Users\tummala surya\Downloads\roblox\scraped_docs`
- Output Format: Categorized Markdown (`.md`) files
- Endpoint Strategy: Primary fetch via Roblox Creator Docs Markdown endpoint (`https://create.roblox.com/docs/en-us/<slug>.md`) with HTML fallback (`<main id="main">` / `<article>`).
- Verification: `verify_docs.py` checks file presence (51 target files), non-zero size (>100B), markdown headings, and INDEX coverage.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | URL Catalog & Mapping | Map 51 Roblox doc URLs to category paths | M1 | ORIGINAL_REQUEST.md |
| 2 | DOM Extraction & Noise Cleaner | Strip nav, footer, script, UI noise | M2 | ORIGINAL_REQUEST.md |
| 3 | Markdown Formatting Engine | Convert cleaned content to formatted Markdown | M2 | ORIGINAL_REQUEST.md |
| 4 | Categorized Subfolder Exporter | Save `.md` files to structured subfolders | M2 | ORIGINAL_REQUEST.md |
| 5 | Master INDEX.md Generator | Generate root TOC with local relative links | M3 | ORIGINAL_REQUEST.md |
| 6 | Verification Suite | `verify_docs.py` automated test runner | M3 | ORIGINAL_REQUEST.md |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | Survey & URL Mapping | Map 51 URLs, DOM selectors & folder tree | none | DONE |
| 2 | Scraping & Markdown Engine | Implement scraper, clean HTML, export 51 docs | M1 | DONE |
| 3 | Master Index & Verification | Create INDEX.md and verify_docs.py | M2 | IN_PROGRESS |
| 4 | Final Verification & Sentinel Report | Validate 100% acceptance & notify Sentinel | M3 | PLANNED |

## Output Folder Structure
Target Base Path: `c:\Users\tummala surya\Downloads\roblox\scraped_docs\`
Categories:
- `creation/`
- `projects/`
- `workspace/`
- `parts/`
- `physics/`
- `effects/`
- `scripting/`
- `environment/`
- `players/`
- `characters/`
- `input/`
- `audio/`
- `ui/`
- `animation/`
- `matchmaking/`
- `performance-optimization/`
- `cloud-services/`
- `unity/`
- `unreal/`
- `discovery/`
- `production/` & `production/monetization/`
- `monetization/`
- `creator-rewards/`
- `ip-licensing/`
- Root: `INDEX.md`
