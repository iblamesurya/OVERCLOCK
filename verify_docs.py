import os
import sys

TARGET_DOCS = [
    ("https://create.roblox.com/docs/creation", "creation/index.md"),
    ("https://create.roblox.com/docs/projects", "projects/index.md"),
    ("https://create.roblox.com/docs/workspace", "workspace/index.md"),
    ("https://create.roblox.com/docs/parts", "parts/index.md"),
    ("https://create.roblox.com/docs/parts/meshes", "parts/meshes.md"),
    ("https://create.roblox.com/docs/parts/models", "parts/models.md"),
    ("https://create.roblox.com/docs/parts/procedural-models", "parts/procedural-models.md"),
    ("https://create.roblox.com/docs/parts/materials", "parts/materials.md"),
    ("https://create.roblox.com/docs/parts/terrain", "parts/terrain.md"),
    ("https://create.roblox.com/docs/physics", "physics/index.md"),
    ("https://create.roblox.com/docs/physics/assemblies", "physics/assemblies.md"),
    ("https://create.roblox.com/docs/physics/network-ownership", "physics/network-ownership.md"),
    ("https://create.roblox.com/docs/physics/mechanical-constraints", "physics/mechanical-constraints.md"),
    ("https://create.roblox.com/docs/physics/mover-constraints", "physics/mover-constraints.md"),
    ("https://create.roblox.com/docs/physics/sleep-system", "physics/sleep-system.md"),
    ("https://create.roblox.com/docs/physics/adaptive-timestepping", "physics/adaptive-timestepping.md"),
    ("https://create.roblox.com/docs/physics/units", "physics/units.md"),
    ("https://create.roblox.com/docs/effects", "effects/index.md"),
    ("https://create.roblox.com/docs/workspace/camera", "workspace/camera.md"),
    ("https://create.roblox.com/docs/parts/model-generation", "parts/model-generation.md"),
    ("https://create.roblox.com/docs/scripting", "scripting/index.md"),
    ("https://create.roblox.com/docs/environment", "environment/index.md"),
    ("https://create.roblox.com/docs/players", "players/index.md"),
    ("https://create.roblox.com/docs/characters", "characters/index.md"),
    ("https://create.roblox.com/docs/input", "input/index.md"),
    ("https://create.roblox.com/docs/audio", "audio/index.md"),
    ("https://create.roblox.com/docs/ui", "ui/index.md"),
    ("https://create.roblox.com/docs/animation", "animation/index.md"),
    ("https://create.roblox.com/docs/matchmaking", "matchmaking/index.md"),
    ("https://create.roblox.com/docs/performance-optimization", "performance-optimization/index.md"),
    ("https://create.roblox.com/docs/cloud-services/data-stores-vs-memory-stores", "cloud-services/data-stores-vs-memory-stores.md"),
    ("https://create.roblox.com/docs/unity", "unity/index.md"),
    ("https://create.roblox.com/docs/unreal", "unreal/index.md"),
    ("https://create.roblox.com/docs/discovery", "discovery/index.md"),
    ("https://create.roblox.com/docs/production/game-design", "production/game-design.md"),
    ("https://create.roblox.com/docs/monetize-experiences", "monetization/monetize-experiences.md"),
    ("https://create.roblox.com/docs/production/monetization", "production/monetization/index.md"),
    ("https://create.roblox.com/docs/production/monetization/developer-exchange", "production/monetization/developer-exchange.md"),
    ("https://create.roblox.com/docs/creator-rewards", "creator-rewards/index.md"),
    ("https://create.roblox.com/docs/production/monetization/roblox-plus", "production/monetization/roblox-plus.md"),
    ("https://create.roblox.com/docs/production/monetization/robux-transfers", "production/monetization/robux-transfers.md"),
    ("https://create.roblox.com/docs/production/monetization/private-servers", "production/monetization/private-servers.md"),
    ("https://create.roblox.com/docs/production/monetization/subscriptions", "production/monetization/subscriptions.md"),
    ("https://create.roblox.com/docs/production/monetization/passes", "production/monetization/passes.md"),
    ("https://create.roblox.com/docs/production/monetization/developer-products", "production/monetization/developer-products.md"),
    ("https://create.roblox.com/docs/production/monetization/commerce-products", "production/monetization/commerce-products.md"),
    ("https://create.roblox.com/docs/production/monetization/shop", "production/monetization/shop.md"),
    ("https://create.roblox.com/docs/production/monetization/paid-access-robux", "production/monetization/paid-access-robux.md"),
    ("https://create.roblox.com/docs/production/monetization/paid-access-local-currency", "production/monetization/paid-access-local-currency.md"),
    ("https://create.roblox.com/docs/production/monetization/managed-pricing", "production/monetization/managed-pricing.md"),
    ("https://create.roblox.com/docs/ip-licensing", "ip-licensing/index.md"),
]


def run_verification():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    if os.path.basename(script_dir) == "scraped_docs":
        docs_dir = script_dir
    elif os.path.isdir(os.path.join(script_dir, "scraped_docs")):
        docs_dir = os.path.join(script_dir, "scraped_docs")
    else:
        docs_dir = script_dir

    print("==================================================")
    print(" Roblox Creator Documentation Verification Suite ")
    print("==================================================")
    print(f"Target Directory: {docs_dir}")
    print(f"Total Expected Documents: {len(TARGET_DOCS)}")
    print("--------------------------------------------------\n")

    errors = []

    # Verification 1: All 51 target .md files exist on disk
    print("[Verification 1] Checking file existence on disk...")
    missing_files = []
    for url, rel_path in TARGET_DOCS:
        full_path = os.path.join(docs_dir, rel_path)
        if not os.path.exists(full_path):
            missing_files.append(rel_path)

    if missing_files:
        msg = f"FAIL: {len(missing_files)} files missing on disk: {missing_files}"
        print(f"  ❌ {msg}")
        errors.append(msg)
    else:
        print(f"  PASS: All {len(TARGET_DOCS)} files exist on disk.")

    # Verification 2: All 51 target .md files have size > 100 bytes
    print("\n[Verification 2] Checking file sizes (> 100 bytes)...")
    undersized_files = []
    for url, rel_path in TARGET_DOCS:
        full_path = os.path.join(docs_dir, rel_path)
        if os.path.exists(full_path):
            sz = os.path.getsize(full_path)
            if sz <= 100:
                undersized_files.append((rel_path, sz))

    if undersized_files:
        msg = f"FAIL: {len(undersized_files)} files under 100 bytes: {undersized_files}"
        print(f"  ❌ {msg}")
        errors.append(msg)
    else:
        print(f"  PASS: All {len(TARGET_DOCS)} files exceed 100 bytes.")

    # Verification 3: All 51 target .md files contain valid Markdown headings (# or ##)
    print("\n[Verification 3] Checking Markdown headings (# or ##)...")
    invalid_heading_files = []
    for url, rel_path in TARGET_DOCS:
        full_path = os.path.join(docs_dir, rel_path)
        if os.path.exists(full_path):
            try:
                with open(full_path, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read()
                has_heading = any(
                    line.strip().startswith("#") for line in content.splitlines()
                )
                if not has_heading:
                    invalid_heading_files.append(rel_path)
            except Exception as e:
                invalid_heading_files.append(f"{rel_path} (error reading: {e})")

    if invalid_heading_files:
        msg = f"FAIL: {len(invalid_heading_files)} files missing valid Markdown headings: {invalid_heading_files}"
        print(f"  ❌ {msg}")
        errors.append(msg)
    else:
        print(f"  PASS: All {len(TARGET_DOCS)} files contain valid Markdown headings.")

    # Verification 4: INDEX.md exists, size > 100 bytes, and contains relative links to all 51 target files
    print("\n[Verification 4] Checking INDEX.md and relative link coverage...")
    index_path = os.path.join(docs_dir, "INDEX.md")
    if not os.path.exists(index_path):
        msg = "FAIL: INDEX.md does not exist!"
        print(f"  ❌ {msg}")
        errors.append(msg)
    else:
        index_size = os.path.getsize(index_path)
        if index_size <= 100:
            msg = f"FAIL: INDEX.md is undersized ({index_size} bytes)!"
            print(f"  ❌ {msg}")
            errors.append(msg)
        else:
            with open(index_path, "r", encoding="utf-8", errors="ignore") as f:
                index_content = f.read()
            missing_links = []
            for url, rel_path in TARGET_DOCS:
                if rel_path not in index_content:
                    missing_links.append(rel_path)

            if missing_links:
                msg = f"FAIL: INDEX.md is missing links to {len(missing_links)} files: {missing_links}"
                print(f"  ❌ {msg}")
                errors.append(msg)
            else:
                print(
                    f"  PASS: INDEX.md exists ({index_size} bytes) and contains valid relative links to all {len(TARGET_DOCS)} target files."
                )

    print("\n==================================================")
    if errors:
        print(f" VERIFICATION FAILED - {len(errors)} error(s) detected!")
        print("==================================================")
        for err in errors:
            print(f" - {err}")
        sys.exit(1)
    else:
        print(" VERIFICATION SUCCESSFUL - All 4 checks passed! (0 errors)")
        print("==================================================")
        sys.exit(0)


if __name__ == "__main__":
    run_verification()
