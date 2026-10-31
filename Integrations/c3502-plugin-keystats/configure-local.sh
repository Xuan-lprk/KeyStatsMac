#!/bin/bash
# Reuse the existing local C3502 toolchain without changing either lockfile.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
C3502_ROOT="$(cd "${1:?Usage: bash configure-local.sh /path/to/c3502}" && pwd)"
if [[ ! -f "$C3502_ROOT/packages/c3502/dist/kit.mjs" || ! -d "$C3502_ROOT/node_modules" ]]; then
    echo "Install and build C3502 first (pnpm install; pnpm exec vp run build)." >&2
    exit 1
fi
if [[ -e "$HERE/node_modules" || -L "$HERE/node_modules" ]]; then
    echo "node_modules already exists; leave it unchanged and check its dependency source." >&2
    exit 1
fi
ln -s "$C3502_ROOT/node_modules" "$HERE/node_modules"
echo "Local public C3502 package and toolchain linked. No source or lockfile changed."
