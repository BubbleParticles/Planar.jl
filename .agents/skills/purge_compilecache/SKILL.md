# purge-compilecache

Trigger: stale precompilation errors or method overwrite warnings.

Removes Julia's compiled cache at `$HOME/.julia/compiled`.

Usage: `purge_compilecache.sh`

Notes: Running this forces full recompilation on the next Julia startup.
