#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

TAG="${1:-}"
if [[ -z "$TAG" ]]; then
    echo "Usage: $0 <tag> [output-dir]"
    echo "Example: $0 v1.8 build/release/v1.8"
    exit 1
fi

VERSION="${TAG#v}"
if [[ -z "$VERSION" || "$VERSION" == "$TAG" ]]; then
    echo "Error: tag must include a leading 'v', e.g. v1.8"
    exit 1
fi

echo "publish_release.sh is deprecated. Forwarding to release.sh..."
exec "$SCRIPT_DIR/release.sh" "$VERSION" "${2:-}"
