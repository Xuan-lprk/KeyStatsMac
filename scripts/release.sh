#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: ./scripts/release.sh <version>"
    echo "Example: ./scripts/release.sh 1.8"
}

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    usage
    exit 1
fi

TAG="v$VERSION"
PBXPROJ="KeyStats.xcodeproj/project.pbxproj"
WINDOWS_CSPROJ="KeyStats.Windows/KeyStats/KeyStats.csproj"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "Release $TAG"

current_build=$(perl -0ne 'if (/CURRENT_PROJECT_VERSION = ([0-9]+);\s*\n\s*DEVELOPMENT_TEAM = 228XJY7Z32;/) { print $1; exit }' "$PBXPROJ")
if [[ -z "${current_build:-}" ]]; then
    echo "Error: unable to read main-app CURRENT_PROJECT_VERSION from $PBXPROJ"
    exit 1
fi

new_build=$((current_build + 1))
perl -0pi -e "s/CURRENT_PROJECT_VERSION = [0-9]+;(\s*\n\s*DEVELOPMENT_TEAM = 228XJY7Z32;)/CURRENT_PROJECT_VERSION = ${new_build};\$1/g; s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = ${VERSION};/g" "$PBXPROJ"
perl -0pi -e "s#<Version>[^<]+</Version>#<Version>${VERSION}</Version>#g" "$WINDOWS_CSPROJ"
echo "Set MARKETING_VERSION=$VERSION, CURRENT_PROJECT_VERSION=$new_build, Windows Version=$VERSION"

echo "Committing version bump..."
git add "$PBXPROJ" "$WINDOWS_CSPROJ"
git commit -m "chore: bump version to $VERSION"

echo "Tagging and pushing..."
git tag "$TAG"
git push origin main
git push origin "$TAG"

echo ""
echo "Release complete for $TAG"
echo "GitHub Actions will build and publish artifacts, including Sparkle appcast."
