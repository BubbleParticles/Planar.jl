#!/usr/bin/env python3
"""Update all Manifests: replace vendored Zarr with upstream + add missing deps."""

import re, os

PROJECT = "/project"

# Canonical upstream entries (extracted from Processing/Manifest.toml after Pkg.update)
UPSTREAM_ZARR = """[[deps.Zarr]]
deps = ["Blosc", "CRC32c", "ChunkCodecCore", "ChunkCodecLibZlib", "ChunkCodecLibZstd", "DataStructures", "DateTimes64", "Dates", "DiskArrays", "HTTP", "JSON", "OffsetArrays", "OpenSSL", "Pkg", "URIs", "ZipArchives"]
git-tree-sha1 = "e006bf49f81ae1f04af9e9ff405d02620a845405"
uuid = "0a941bbe-ad1d-11e8-39d9-ab76183a1d99"
version = "0.10.0\""""

EXTENSIONS = """    [deps.Zarr.extensions]
    ZarrAWSS3Ext = "AWSS3\""""

WEAKDEPS = """    [deps.Zarr.weakdeps]
    AWSS3 = "1c724243-ef5b-51ab-93f4-b0a88ac62a95\""""

NEW_ENTRIES = {
    "CRC32c": """[[deps.CRC32c]]
uuid = "8bf52ea8-c179-5cab-976a-9e18b702a9bc"
version = "1.11.0\"""",
    "ChunkCodecCore": """[[deps.ChunkCodecCore]]
git-tree-sha1 = "1a3ad7e16a321667698a19e77362b35a1e94c544"
uuid = "0b6fb165-00bc-4d37-ab8b-79f91016dbe1"
version = "1.0.1\"""",
    "ChunkCodecLibZlib": """[[deps.ChunkCodecLibZlib]]
deps = ["ChunkCodecCore", "Zlib_jll"]
git-tree-sha1 = "cee8104904c53d39eb94fd06cbe60cb5acde7177"
uuid = "4c0bbee4-addc-4d73-81a0-b6caacae83c8"
version = "1.0.0\"""",
    "ChunkCodecLibZstd": """[[deps.ChunkCodecLibZstd]]
deps = ["ChunkCodecCore", "Zstd_jll"]
git-tree-sha1 = "34d9873079e4cb3d0c62926a225136824677073f"
uuid = "55437552-ac27-4d47-9aa3-63184e8fd398"
version = "1.0.0\"""",
    "DateTimes64": """[[deps.DateTimes64]]
deps = ["Dates"]
git-tree-sha1 = "1db3d38eecf7c197f5839d2afd6aedb15a8753b3"
uuid = "b342263e-b350-472a-b1a9-8dfd21b51589"
version = "1.0.1\"""",
    "ZipArchives": """[[deps.ZipArchives]]
deps = ["ArgCheck", "CodecInflate64", "CodecZlib", "InputBuffers", "PrecompileTools", "TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "83f728ecb873c58b794964f8b4bed811814d4b0d"
uuid = "49080126-0e18-4c2a-b176-c102e4b3760c"
version = "2.6.0\"""",
}

import subprocess
result = subprocess.run(
    ["find", PROJECT, "-name", "Manifest.toml", "-not", "-path", "*/vendor/*", "-not", "-path", "*/.git/*"],
    capture_output=True, text=True
)
manifest_files = [f for f in result.stdout.strip().split("\n") if f]
print(f"Found {len(manifest_files)} total Manifest files")

count_updated = 0
count_skipped = 0

for mf in manifest_files:
    with open(mf) as f:
        content = f.read()
    
    original = content
    
    # Check if this Manifest needs vendored Zarr replacement
    has_vendored = '../vendor/Zarr' in content
    has_upstream = 'version = "0.10.0"' in content
    has_new_deps = all(f"[[deps.{k}]]" in content for k in NEW_ENTRIES)
    
    if not has_vendored:
        count_skipped += 1
        continue
    
    relpath = os.path.relpath(mf, PROJECT)
    
    # 1. Replace the vendored Zarr block
    # Match [[deps.Zarr]] ... until next [[deps. or end
    pattern = r'(\[\[deps\.Zarr\]\].*?)(?=\n\[\[deps\.|\Z)'
    def zarr_replacer(m):
        block = m.group(1)
        if '../vendor/Zarr' in block or 'version = "99.9.9"' in block:
            return '\n' + UPSTREAM_ZARR + '\n\n' + EXTENSIONS + '\n\n' + WEAKDEPS + '\n'
        return block
    new_content = re.sub(pattern, zarr_replacer, content, flags=re.DOTALL)
    
    # 2. Add missing dep entries
    for name, entry_text in NEW_ENTRIES.items():
        marker = f"[[deps.{name}]]"
        if marker not in new_content:
            new_content = new_content.rstrip() + '\n\n' + entry_text + '\n'
    
    if new_content != original:
        with open(mf, "w") as f:
            f.write(new_content)
        count_updated += 1
        print(f"  UPDATED: {relpath}")
    else:
        count_skipped += 1

print(f"\nDone! Updated: {count_updated}, Skipped: {count_skipped}")
