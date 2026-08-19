# Roblox Creator Documentation Scraper — Survey 2 Analysis Report (URLs 18-34)

**Target Scope**: Roblox Creator Documentation URLs 18 to 34  
**Explorer Agent**: `teamwork_preview_explorer_survey_2`  
**Date**: 2026-08-07  
**Working Directory**: `c:\Users\tummala surya\Downloads\roblox\.agents\teamwork_preview_explorer_survey_2`  

---

## Executive Summary

A comprehensive investigation of Roblox Creator Documentation target URLs 18 through 34 was conducted. All **17 assigned URLs** were verified and returned HTTP `200 OK` status for both standard HTML rendering and direct Markdown (`.md`) native documentation endpoints.

Key Findings:
1. **100% URL Accessibility**: All 17 target URLs are active, returning rich documentation with non-zero sizes (range: 2,664 to 20,142 bytes for native Markdown; 425 KB to 571 KB for raw HTML).
2. **Native Markdown Endpoint Availability**: Every Roblox documentation page exposes an alternate native Markdown resource endpoint at `https://create.roblox.com/docs/en-us/<slug>.md`. This endpoint delivers pre-cleaned, perfectly formatted Markdown with syntax-highlighted code blocks (`luau`/`lua`), tables, lists, and callout blocks without any HTML/UI noise.
3. **Structured Mapping Scheme**: Each URL maps cleanly into 17 target subdirectories under `scraped_docs/` (`effects/`, `workspace/`, `parts/`, `scripting/`, `environment/`, `players/`, `characters/`, `input/`, `audio/`, `ui/`, `animation/`, `matchmaking/`, `performance-optimization/`, `cloud-services/`, `unity/`, `unreal/`, `discovery/`).

---

## 1. URL to Output Markdown File Mapping Table

Below is the definitive mapping table for URLs 18 through 34:

| # | Target Doc URL | Category Folder | Recommended Relative Path (`scraped_docs/`) | Alternate Relative Path | Document Title | Native MD Endpoint URL | MD Size (Bytes) | Headings Count | Code Blocks Count |
|---|---|---|---|---|---|---|---|---|---|
| 18 | `https://create.roblox.com/docs/effects` | `effects/` | `effects/index.md` | `effects/effects.md` | Effects | `https://create.roblox.com/docs/en-us/effects.md` | 3,136 | 6 | 8 |
| 19 | `https://create.roblox.com/docs/workspace/camera` | `workspace/` | `workspace/camera.md` | `workspace/camera.md` | Customize the camera | `https://create.roblox.com/docs/en-us/workspace/camera.md` | 6,142 | 7 | 32 |
| 20 | `https://create.roblox.com/docs/parts/model-generation` | `parts/` | `parts/model-generation.md` | `parts/model-generation.md` | Model generation | `https://create.roblox.com/docs/en-us/parts/model-generation.md` | 10,013 | 4 | 34 |
| 21 | `https://create.roblox.com/docs/scripting` | `scripting/` | `scripting/index.md` | `scripting/scripting.md` | Scripting | `https://create.roblox.com/docs/en-us/scripting.md` | 6,716 | 6 | 45 |
| 22 | `https://create.roblox.com/docs/environment` | `environment/` | `environment/index.md` | `environment/environment.md` | Lighting and effects | `https://create.roblox.com/docs/en-us/environment.md` | 3,509 | 9 | 10 |
| 23 | `https://create.roblox.com/docs/players` | `players/` | `players/index.md` | `players/players.md` | Users and players | `https://create.roblox.com/docs/en-us/players.md` | 12,388 | 15 | 107 |
| 24 | `https://create.roblox.com/docs/characters` | `characters/` | `characters/index.md` | `characters/characters.md` | Characters | `https://create.roblox.com/docs/en-us/characters.md` | 5,662 | 4 | 21 |
| 25 | `https://create.roblox.com/docs/input` | `input/` | `input/index.md` | `input/input.md` | Input | `https://create.roblox.com/docs/en-us/input.md` | 9,031 | 10 | 85 |
| 26 | `https://create.roblox.com/docs/audio` | `audio/` | `audio/index.md` | `audio/audio.md` | Audio | `https://create.roblox.com/docs/en-us/audio.md` | 2,937 | 4 | 12 |
| 27 | `https://create.roblox.com/docs/ui` | `ui/` | `ui/index.md` | `ui/ui.md` | User interface | `https://create.roblox.com/docs/en-us/ui.md` | 4,402 | 10 | 20 |
| 28 | `https://create.roblox.com/docs/animation` | `animation/` | `animation/index.md` | `animation/animation.md` | Animation in Roblox | `https://create.roblox.com/docs/en-us/animation.md` | 2,664 | 4 | 3 |
| 29 | `https://create.roblox.com/docs/matchmaking` | `matchmaking/` | `matchmaking/index.md` | `matchmaking/matchmaking.md` | Matchmaking | `https://create.roblox.com/docs/en-us/matchmaking.md` | 4,291 | 6 | 0 |
| 30 | `https://create.roblox.com/docs/performance-optimization` | `performance-optimization/` | `performance-optimization/index.md` | `performance-optimization/performance-optimization.md` | Performance optimization | `https://create.roblox.com/docs/en-us/performance-optimization.md` | 3,709 | 3 | 0 |
| 31 | `https://create.roblox.com/docs/cloud-services/data-stores-vs-memory-stores` | `cloud-services/` | `cloud-services/data-stores-vs-memory-stores.md` | `cloud-services/data-stores-vs-memory-stores.md` | Choose between cloud services | `https://create.roblox.com/docs/en-us/cloud-services/data-stores-vs-memory-stores.md` | 6,210 | 6 | 2 |
| 32 | `https://create.roblox.com/docs/unity` | `unity/` | `unity/index.md` | `unity/unity.md` | Roblox for Unity developers | `https://create.roblox.com/docs/en-us/unity.md` | 15,087 | 12 | 93 |
| 33 | `https://create.roblox.com/docs/unreal` | `unreal/` | `unreal/index.md` | `unreal/unreal.md` | Roblox for Unreal developers | `https://create.roblox.com/docs/en-us/unreal.md` | 15,111 | 12 | 80 |
| 34 | `https://create.roblox.com/docs/discovery` | `discovery/` | `discovery/index.md` | `discovery/discovery.md` | Discovery | `https://create.roblox.com/docs/en-us/discovery.md` | 20,142 | 15 | 0 |

---

## 2. Page DOM Architecture & HTML-to-Markdown Conversion Strategies

### DOM Architecture Overview
Roblox Creator Hub documentation pages are rendered using Next.js / React with Material UI (MUI) styled components.
- Core Content Container: `<main id="main">` or `<div class="Grid-root-contentContainer">` or `div[class*="wordWrap-articleHeader"]`.
- Document Article: `<article>` element wrapping article headings, paragraphs, lists, tables, callout banners, and code snippet frames.

### Recommended Scraping Route (Dual-Mode Engine)

#### Primary Route: Direct Native Markdown Endpoint Fetching
Each Roblox documentation page exposes an explicit `<link rel="alternate" type="text/markdown" href="https://create.roblox.com/docs/en-us/<slug>.md" />` tag.
- **Advantage**: Fetching `https://create.roblox.com/docs/en-us/<slug>.md` directly returns pre-cleaned, high-fidelity Markdown.
- **Header Parsing**: Contains standard YAML frontmatter (`title`, `url`, `last_updated`, `description`). The implementation worker can strip or retain frontmatter as required.
- **Zero Noise**: Guarantees zero navigation, footer, or UI script pollution.

#### Fallback Route: HTML DOM Parsing & Cleaning Strategy
If fetching HTML directly (e.g. `https://create.roblox.com/docs/<slug>`), the engine must parse the DOM inside `<main id="main">` and apply the following conversion rules:

1. **Headings Conversion**:
   - `<h1>` -> `# Title`
   - `<h2>` -> `## Heading 2`
   - `<h3>` -> `### Heading 3`
   - `<h4>`-`<h6>` -> `#### Heading 4` to `###### Heading 6`
   - *Anchor stripping*: Remove child `<a>` tags with `data-testid="copy-heading-link"` or class `copyAnchor`.

2. **Code Blocks & Syntax Highlighting**:
   - `<pre><code class="language-luau">...</code></pre>` -> ```luau ... ```
   - `<pre><code class="language-lua">...</code></pre>` -> ```lua ... ```
   - `<pre><code>...</code></pre>` -> ```text ... ```
   - Preserve inline code `<code>...</code>` as `` `...` ``.

3. **Tables Conversion**:
   - Convert HTML `<table><thead>...</thead><tbody>...</tbody></table>` into standard GFM markdown tables:
     ```markdown
     | Header 1 | Header 2 |
     | --- | --- |
     | Cell 1 | Cell 2 |
     ```
   - Strip extra formatting or wrapper `<div>` tags around tables.

4. **Lists Handling**:
   - `<ul>` / `<li>` -> unordered lists (`- Item`)
   - `<ol>` / `<li>` -> ordered lists (`1. Item`)
   - Support nested lists with 2-space or 4-space indentation.

5. **Callout Boxes (Notes, Warnings, Alerts, Tips)**:
   - In HTML, callouts appear as `<div class="callout callout-note">` or `<blockquote class="alert alert-warning">`.
   - Convert callout elements to GitHub-Flavored Markdown blockquote callouts:
     ```markdown
     > [!NOTE]
     > Callout body content goes here.
     ```
     or
     ```markdown
     > **Note:**
     > Callout body content goes here.
     ```

6. **Images & Media**:
   - Convert `<img>` tags to `![Alt text](Image URL)`. Ensure relative paths are resolved to absolute `https://assets.create.roblox.com/...` or saved assets.

---

## 3. Recommended Noise Removal Selectors

When processing raw HTML, the scraper engine MUST exclude the following DOM elements:

| Element Category | Selector / Tag / Class | Rationale for Removal |
|---|---|---|
| Top Header Nav | `header`, `[data-testid="top-nav-header"]`, `nav.MuiAppBar-root` | Site header and top navigation |
| Breadcrumbs | `nav[aria-label="breadcrumbs"]`, `.MuiBreadcrumbs-root` | Page path hierarchy links |
| Left Navigation Drawer | `#left-nav`, `div[role="navigation"]`, `.MuiDrawer-root` | Full site navigation tree |
| Right TOC Sidebar | `[data-testid="on-this-page-nav"]`, `.rightSidebar` | In-page TOC navigation links |
| Copy Link Buttons | `[data-testid="copy-heading-link"]`, `button.copyAnchor` | Interactive link anchor buttons |
| Language Selector | `[data-testid="language-menu-button"]`, `div.languageMenu` | Locale switching UI |
| Feedback Banners | `[data-testid="feedback-section"]`, `div.feedback` | "Was this page helpful?" feedback widgets |
| Scripts & Hydration | `<script>`, `<style>`, `<noscript>`, `#`__NEXT_DATA__ | React hydration payloads and CSS |
| Footer Links & Info | `footer`, `div.Grid-root-companyInfo`, `div.Grid-root-social` | Copyright, legal links, social icons |
| Cookie Consent Modals | `div[id*="cookie"]`, `div[class*="consent"]` | Cookie banner popups |

---

## 4. Python Environment Capabilities & Scraper Tooling

### Python Environment Audit
- **Python Version**: `3.11.15`
- **Available Standard Libraries**: `urllib.request`, `re`, `html.parser`, `json`, `pathlib`, `os`
- **Available Third-Party Libraries**: `requests`, `urllib3`, `httpx`, `aiohttp`
- **Missing Third-Party Libraries**: `beautifulsoup4`, `html2text`, `markdownify`

### Implementation Architecture for Milestone 2 Worker

Because `beautifulsoup4` and `html2text` are not pre-installed in the current environment, the Milestone 2 worker should implement the scraper script (`scrape_docs.py`) using **Standard Python Libraries (`urllib.request` + `re` / `html.parser`) and `requests`**:

1. **Primary Scraping Logic**:
   - Loop over the 51 mapped URLs.
   - Construct native `.md` endpoint URL: `https://create.roblox.com/docs/en-us/<slug>.md`.
   - Perform HTTP GET request with standard User-Agent header.
   - If response status is 200 OK:
     - Read UTF-8 text content.
     - Save directly to target path (e.g. `scraped_docs/effects/index.md`).
   - If response status is not 200 OK (Fallback):
     - Fetch HTML URL.
     - Extract `<main>` content using `re` or `html.parser`.
     - Strip noise selectors listed in Section 3.
     - Convert HTML tags to Markdown elements.
2. **Directory Structure Creation**:
   - Ensure subdirectories (`effects/`, `workspace/`, `parts/`, `scripting/`, `environment/`, `players/`, `characters/`, `input/`, `audio/`, `ui/`, `animation/`, `matchmaking/`, `performance-optimization/`, `cloud-services/`, `unity/`, `unreal/`, `discovery/`) are created via `os.makedirs(..., exist_ok=True)`.

---

## 5. Verification & Quality Assurance Criteria

To satisfy project acceptance criteria for URLs 18-34:
- All 17 files must exist under `c:\Users\tummala surya\Downloads\roblox\scraped_docs/`.
- File size of each document must exceed **100 bytes** (actual sizes range from **2.6 KB to 20.1 KB**).
- Each saved document must contain Markdown headings (`#`, `##`, `###`).
- Documents with Luau/Lua code must contain syntax-highlighted code blocks (` ```luau ` or ` ```lua `).
