# URL Survey & DOM Structure Analysis — URLs 1 to 17

**Target Scope**: Roblox Creator Documentation URLs 1 to 17  
**Explorer Agent**: `teamwork_preview_explorer_survey_1`  
**Date**: 2026-08-07  

---

## 1. URL to Output Markdown File Mapping

All 17 target URLs were verified with HTTP status `200 OK`. The documentation structure categorizes pages into subdirectories (`creation/`, `projects/`, `workspace/`, `parts/`, `physics/`).

Below is the exact mapping table for URLs 1 through 17:

| # | Target Doc URL | Category | Recommended Relative Path (`scraped_docs/`) | Alternate Relative Path | Title | MD Size (Bytes) | Headings | Code Blocks |
|---|---|---|---|---|---|---|---|---|
| 1 | `https://create.roblox.com/docs/creation` | `creation` | `creation/index.md` | `creation/creation.md` | Creation overview | 3,053 | 21 | 0 |
| 2 | `https://create.roblox.com/docs/projects` | `projects` | `projects/index.md` | `projects/projects.md` | Projects | 6,410 | 7 | 0 |
| 3 | `https://create.roblox.com/docs/workspace` | `workspace` | `workspace/index.md` | `workspace/workspace.md` | 3D workspace | 4,696 | 5 | 0 |
| 4 | `https://create.roblox.com/docs/parts` | `parts` | `parts/index.md` | `parts/parts.md` | Parts | 14,535 | 20 | 0 |
| 5 | `https://create.roblox.com/docs/parts/meshes` | `parts` | `parts/meshes.md` | `parts/meshes.md` | Meshes | 10,999 | 16 | 0 |
| 6 | `https://create.roblox.com/docs/parts/models` | `parts` | `parts/models.md` | `parts/models.md` | Models | 10,020 | 10 | 0 |
| 7 | `https://create.roblox.com/docs/parts/procedural-models` | `parts` | `parts/procedural-models.md` | `parts/procedural-models.md` | Procedural models | 9,940 | 14 | 1 |
| 8 | `https://create.roblox.com/docs/parts/materials` | `parts` | `parts/materials.md` | `parts/materials.md` | Materials | 34,249 | 25 | 0 |
| 9 | `https://create.roblox.com/docs/parts/terrain` | `parts` | `parts/terrain.md` | `parts/terrain.md` | Environmental terrain | 22,282 | 23 | 1 |
| 10 | `https://create.roblox.com/docs/physics` | `physics` | `physics/index.md` | `physics/physics.md` | Physics | 4,117 | 9 | 0 |
| 11 | `https://create.roblox.com/docs/physics/assemblies` | `physics` | `physics/assemblies.md` | `physics/assemblies.md` | Assemblies | 5,703 | 4 | 0 |
| 12 | `https://create.roblox.com/docs/physics/network-ownership` | `physics` | `physics/network-ownership.md` | `physics/network-ownership.md` | Network ownership | 7,106 | 6 | 1 |
| 13 | `https://create.roblox.com/docs/physics/mechanical-constraints` | `physics` | `physics/mechanical-constraints.md` | `physics/mechanical-constraints.md` | Mechanical constraints | 8,346 | 6 | 0 |
| 14 | `https://create.roblox.com/docs/physics/mover-constraints` | `physics` | `physics/mover-constraints.md` | `physics/mover-constraints.md` | Mover constraints | 11,172 | 7 | 0 |
| 15 | `https://create.roblox.com/docs/physics/sleep-system` | `physics` | `physics/sleep-system.md` | `physics/sleep-system.md` | Sleep system | 13,642 | 9 | 0 |
| 16 | `https://create.roblox.com/docs/physics/adaptive-timestepping` | `physics` | `physics/adaptive-timestepping.md` | `physics/adaptive-timestepping.md` | Adaptive timestepping | 3,216 | 4 | 0 |
| 17 | `https://create.roblox.com/docs/physics/units` | `physics` | `physics/units.md` | `physics/units.md` | Roblox units | 4,495 | 7 | 0 |

---

## 2. Page DOM Structure & Content Container vs Noise Selectors

### Page HTML Architecture
Roblox Creator Documentation is built on Next.js with React hydration:
- **Main Container Selector**: `<main id="main">` or `<article class="...articleHeader...">` / `[data-testid="article"]`.
- **Content Sub-container**: `<div class="...Grid-root-contentContainer...">`.

### Noise Elements to Strip (HTML Scraping Mode)
If parsing HTML directly, the following selectors and elements MUST be stripped to satisfy requirement **R1** (Noise Removal):

1. **Top Header & Navigation**: `<div data-testid="top-nav-header">`
2. **Breadcrumbs Bar**: `<nav aria-label="breadcrumbs">` / `div.MuiBreadcrumbs-root`
3. **Left Sidebar Navigation Drawer**: `<div role="navigation">`, `.MuiDrawer-root`
4. **Right Table of Contents Sidebar**: `[data-testid="on-this-page-nav"]`, `.rightSidebar`
5. **Interactive UI Buttons**:
   - Copy Link button: `[data-testid="copy-heading-link"]`
   - Language selector: `[data-testid="language-menu-button"]`
   - Feedback & action buttons: `<button>` tags
6. **Icons & SVGs**: SVGs with `data-testid="LinkIcon"`, `data-testid="ArrowForwardIcon"`, etc.
7. **Scripts & Data Payloads**: `<script id="__NEXT_DATA__">`, hydration scripts
8. **Footer & Cookie Banners**: Bottom container footers and cookie privacy modals

### Native Markdown Endpoint Discovery (Primary Scraping Route)
Every Roblox documentation HTML contains a `<link>` tag in its `<head>`:
```html
<link rel="alternate" type="text/markdown" href="https://create.roblox.com/docs/en-us/<slug>.md" />
```
Fetching `https://create.roblox.com/docs/en-us/<slug>.md` directly yields the exact, pre-cleaned Markdown document with Frontmatter header (`title`, `url`, `last_updated`, `description`), 0 UI noise elements, complete headings, tables, lists, and code blocks.

---

## 3. Environment & Fetching Strategy

### Python Environment Audit
- **Python Version**: `3.11.15`
- **Installed HTTP Libraries**:
  - `requests` (Available)
  - `httpx` (Available)
  - `aiohttp` (Available)
  - `urllib3` (Available)
  - Standard library `urllib.request` (Available)
- **HTML/MD Parsing Libraries**:
  - `bs4` / `beautifulsoup4`: **Not installed**
  - `html2text`: **Not installed**
  - `markdownify`: **Not installed**
  - Standard library `html.parser`, `re`, `json`, `xml.etree.ElementTree`: **Available**

### Recommended Fetching & Formatting Strategy
1. **Primary Dual-Mode Strategy (Direct Markdown Fetching)**:
   - Use `requests.get("https://create.roblox.com/docs/en-us/<slug>.md")` for all 17 URLs.
   - Strip or format YAML frontmatter headers if desired, leaving clean Markdown.
   - Saves into target directories under `c:\Users\tummala surya\Downloads\roblox\scraped_docs/`.
2. **Fallback HTML Scraping Strategy (Zero Third-Party Dependencies)**:
   - Request `https://create.roblox.com/docs/<slug>` via `requests`.
   - Use `re` or `html.parser` to extract content inside `<main id="main">`.
   - Strip noise tags (`<nav>`, `<button>`, `<script>`, `<header>`, `data-testid="copy-heading-link"`).
   - Convert HTML headings (`<h1>`-`<h6>`), lists (`<ul>`/`<ol>`), code blocks (`<pre><code>`), tables (`<table>`) to Markdown syntax.

---

## 4. Summary & Verification

- All 17 assigned URLs have been surveyed and tested.
- 100% of URLs returned HTTP 200 and produced non-zero size content (>3,000 bytes each).
- Clean subfolder directory structure mapped under `scraped_docs/` (`creation/`, `projects/`, `workspace/`, `parts/`, `physics/`).
