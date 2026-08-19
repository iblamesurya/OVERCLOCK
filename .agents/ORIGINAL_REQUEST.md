# Original User Request

## 2026-08-07T10:37:54Z

# Teamwork Project Prompt — Roblox Creator Documentation Scraper

Scrape, clean, and organize all 50+ specified Roblox Creator documentation pages into structured, categorized Markdown files with a master index.

Working directory: c:/Users/tummala surya/Downloads/roblox/scraped_docs
Integrity mode: demo

List of URLs to scrape:
1. https://create.roblox.com/docs/creation
2. https://create.roblox.com/docs/projects
3. https://create.roblox.com/docs/workspace
4. https://create.roblox.com/docs/parts
5. https://create.roblox.com/docs/parts/meshes
6. https://create.roblox.com/docs/parts/models
7. https://create.roblox.com/docs/parts/procedural-models
8. https://create.roblox.com/docs/parts/materials
9. https://create.roblox.com/docs/parts/terrain
10. https://create.roblox.com/docs/physics
11. https://create.roblox.com/docs/physics/assemblies
12. https://create.roblox.com/docs/physics/network-ownership
13. https://create.roblox.com/docs/physics/mechanical-constraints
14. https://create.roblox.com/docs/physics/mover-constraints
15. https://create.roblox.com/docs/physics/sleep-system
16. https://create.roblox.com/docs/physics/adaptive-timestepping
17. https://create.roblox.com/docs/physics/units
18. https://create.roblox.com/docs/effects
19. https://create.roblox.com/docs/workspace/camera
20. https://create.roblox.com/docs/parts/model-generation
21. https://create.roblox.com/docs/scripting
22. https://create.roblox.com/docs/environment
23. https://create.roblox.com/docs/players
24. https://create.roblox.com/docs/characters
25. https://create.roblox.com/docs/input
26. https://create.roblox.com/docs/audio
27. https://create.roblox.com/docs/ui
28. https://create.roblox.com/docs/animation
29. https://create.roblox.com/docs/matchmaking
30. https://create.roblox.com/docs/performance-optimization
31. https://create.roblox.com/docs/cloud-services/data-stores-vs-memory-stores
32. https://create.roblox.com/docs/unity
33. https://create.roblox.com/docs/unreal
34. https://create.roblox.com/docs/discovery
35. https://create.roblox.com/docs/production/game-design
36. https://create.roblox.com/docs/monetize-experiences
37. https://create.roblox.com/docs/production/monetization
38. https://create.roblox.com/docs/production/monetization/developer-exchange
39. https://create.roblox.com/docs/creator-rewards
40. https://create.roblox.com/docs/production/monetization/roblox-plus
41. https://create.roblox.com/docs/production/monetization/robux-transfers
42. https://create.roblox.com/docs/production/monetization/private-servers
43. https://create.roblox.com/docs/production/monetization/subscriptions
44. https://create.roblox.com/docs/production/monetization/passes
45. https://create.roblox.com/docs/production/monetization/developer-products
46. https://create.roblox.com/docs/production/monetization/commerce-products
47. https://create.roblox.com/docs/production/monetization/shop
48. https://create.roblox.com/docs/production/monetization/paid-access-robux
49. https://create.roblox.com/docs/production/monetization/paid-access-local-currency
50. https://create.roblox.com/docs/production/monetization/managed-pricing
51. https://create.roblox.com/docs/ip-licensing

## Requirements

### R1. Documentation Scraping & Cleaning Engine
Fetch content from all 51 specified Roblox Creator documentation URLs. Extract main article text, headers, code snippets, and tables while stripping UI headers, sidebars, footers, and scripts.

### R2. Categorized Markdown Organization
Format each scraped page into clean Markdown and save into subdirectories reflecting the Roblox documentation hierarchy (e.g., `workspace/`, `physics/`, `scripting/`, `monetization/`).

### R3. Master Table of Contents & Index
Generate a root `INDEX.md` file listing all scraped topics, categories, and direct links to local files.

## Acceptance Criteria

### Execution & Storage
- [ ] All 51 target Roblox documentation pages are successfully fetched and saved as `.md` files.
- [ ] Markdown files are logically organized in subfolders matching their doc category.
- [ ] Non-content noise (navbars, footers, breadcrumbs) is excluded from saved files.

### Verification
- [ ] A verification script (`verify_docs.py` or `.js`) checks that all 51 target files exist, have non-zero size, and contain markdown headings.
- [ ] `INDEX.md` is generated and contains links to every scraped document.
