#!/usr/bin/env python3
"""Update all downstream Manifests by copying Zarr + new dep entries from Processing Manifest."""

import re, os

PROJECT = "/project"
REF = f"{PROJECT}/Data/Manifest.toml"

# Read reference manifest
with open(REF) as f:
    ref_content = f.read()

# Entries we need to add (new packages not in the vendored Zarr era)
NEW_ENTRY_NAMES = [
    "CRC32c",
    "ChunkCodecCore",
    "ChunkCodecLibZlib",
    "ChunkCodecLibZstd",
    "DateTimes64",
    "ZipArchives",
    "ArgCheck",
    "CodecInflate64",
    "InputBuffers",
    "TranscodingStreams",
]

def extract_entry(content, name):
    """Extract a [[deps.X]] block from manifest content."""
    pattern = re.compile(
        r'(\[\[deps\.' + re.escape(name) + r'\]\]'
        r'.*?)(?=\n\[\[deps\.|\Z)',
        re.DOTALL
    )
    m = pattern.search(content)
    if m:
        return m.group(1).strip()
    return None

# Extract reference entries
ZARR_ENTRY = extract_entry(ref_content, "Zarr")
NEW_ENTRIES = {}
for name in NEW_ENTRY_NAMES:
    entry = extract_entry(ref_content, name)
    if entry:
        NEW_ENTRIES[name] = entry
    else:
        print(f"WARNING: {name} not found in reference manifest")

print(f"Reference entries extracted: Zarr + {len(NEW_ENTRIES)} new packages")

# Find all Manifests
import subprocess
result = subprocess.run(
    ["find", PROJECT, "-name", "Manifest.toml",
     "-not", "-path", "*/vendor/*",
     "-not", "-path", "*/.git/*"],
    capture_output=True, text=True
)
manifest_files = [f for f in result.stdout.strip().split("\n") if f]
print(f"Found {len(manifest_files)} total Manifest files")

count_updated = 0
count_skipped = 0
count_vendored = 0

for mf in manifest_files:
    with open(mf) as f:
        content = f.read()
    
    original = content
    has_vendored = '../vendor/Zarr' in content
    relpath = os.path.relpath(mf, PROJECT)
    
    if not has_vendored:
        # Check if it needs new deps added even without vendored Zarr
        needs_deps = False
        for name in NEW_ENTRY_NAMES:
            if f"[[deps.{name}]]" not in content:
                needs_deps = True
                break
        if needs_deps and 'Zarr' in content:
            count_vendored += 1
            print(f"  NEEDS_DEPS (no vendored): {relpath}")
        else:
            count_skipped += 1
        continue
    
    count_vendored += 1
    
    # 1. Replace vendored Zarr block with upstream
    pattern = re.compile(
        r'(\[\[deps\.Zarr\]\].*?)(?=\n\[\[deps\.|\Z)',
        re.DOTALL
    )
    def zarr_replacer(m):
        block = m.group(1)
        if '../vendor/Zarr' in block or 'path = "../vendor/Zarr"' in block:
            return ZARR_ENTRY + '\n'
        return block
    new_content = pattern.sub(zarr_replacer, content)
    
    # 2. Add missing new dep entries
    for name, entry_text in NEW_ENTRIES.items():
        marker = f"[[deps.{name}]]"
        if marker not in new_content:
            new_content = new_content.rstrip() + '\n\n' + entry_text + '\n'
    
    if new_content != original:
        with open(mf, "w") as f:
            f.write(new_content)
        count_updated += 1
        print(f"  UPDATED: {relpath}")

print(f"\nDone! Updated: {count_updated}, Vendored-skipped: {count_skipped}, Needs-deps-no-vendored: {count_vendored}")
