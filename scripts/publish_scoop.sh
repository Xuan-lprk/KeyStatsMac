#!/bin/bash
# Publish KeyStats Windows build to a Scoop bucket repository.
#
# Usage:
#   ./scripts/publish_scoop.sh <version> [bucket-repo-dir]
#
# Examples:
#   ./scripts/publish_scoop.sh 1.40
#   ./scripts/publish_scoop.sh 1.40 /tmp/scoop-keystats
#
# The script will:
#   1. Download the Windows zip from GitHub Releases (or use a local file)
#   2. Calculate SHA256 hash
#   3. Generate the Scoop manifest (keystats.json)
#   4. Commit and push to the bucket repo
#
# Environment variables:
#   SCOOP_BUCKET_REPO  - Git clone URL for the bucket repo
#                        (default: git@github.com:debugtheworldbot/scoop-keystats.git)
#   SCOOP_BUCKET_TOKEN - GitHub token for HTTPS clone (CI usage)
#   LOCAL_ZIP          - Path to a local zip file (skips download)

set -euo pipefail

GITHUB_REPO="debugtheworldbot/keyStats"
BUCKET_REPO="${SCOOP_BUCKET_REPO:-git@github.com:debugtheworldbot/scoop-keystats.git}"

VERSION="${1:-}"
BUCKET_DIR="${2:-}"

if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 <version> [bucket-repo-dir]"
    echo "Example: $0 1.40"
    exit 1
fi

TAG="v${VERSION}"
ZIP_NAME="KeyStats-Windows-${VERSION}.zip"
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${TAG}/${ZIP_NAME}"

echo "==> Calculating SHA256 for ${ZIP_NAME}..."

if [[ -n "${LOCAL_ZIP:-}" && -f "${LOCAL_ZIP}" ]]; then
    echo "    Using local file: ${LOCAL_ZIP}"
    ZIP_PATH="${LOCAL_ZIP}"
elif command -v curl &>/dev/null; then
    TMP_DIR=$(mktemp -d)
    ZIP_PATH="${TMP_DIR}/${ZIP_NAME}"
    echo "    Downloading ${DOWNLOAD_URL}..."
    curl -fSL -o "${ZIP_PATH}" "${DOWNLOAD_URL}"
else
    echo "Error: curl not found and LOCAL_ZIP not set."
    exit 1
fi

if [[ "$(uname)" == "Darwin" ]]; then
    SHA256=$(shasum -a 256 "${ZIP_PATH}" | cut -d ' ' -f 1)
else
    SHA256=$(sha256sum "${ZIP_PATH}" | cut -d ' ' -f 1)
fi
echo "    SHA256: ${SHA256}"

if [[ -n "${TMP_DIR:-}" ]]; then
    rm -rf "${TMP_DIR}"
fi

echo "==> Generating Scoop manifest..."

MANIFEST=$(cat <<EOF
{
    "version": "${VERSION}",
    "description": "Privacy-focused keyboard and mouse statistics tracker",
    "homepage": "https://github.com/${GITHUB_REPO}",
    "license": "MIT",
    "url": "${DOWNLOAD_URL}",
    "hash": "${SHA256}",
    "shortcuts": [
        ["KeyStats.exe", "KeyStats"]
    ],
    "checkver": "github",
    "autoupdate": {
        "url": "https://github.com/${GITHUB_REPO}/releases/download/v\$version/KeyStats-Windows-\$version.zip"
    }
}
EOF
)

echo "${MANIFEST}" | python3 -m json.tool > /dev/null 2>&1 || {
    echo "Error: generated manifest is not valid JSON."
    exit 1
}

echo "==> Updating Scoop bucket..."

if [[ -n "${BUCKET_DIR}" && -d "${BUCKET_DIR}/.git" ]]; then
    echo "    Using existing bucket dir: ${BUCKET_DIR}"
else
    BUCKET_DIR=$(mktemp -d)
    echo "    Cloning ${BUCKET_REPO} -> ${BUCKET_DIR}"

    if [[ -n "${SCOOP_BUCKET_TOKEN:-}" ]]; then
        HTTPS_URL="https://x-access-token:${SCOOP_BUCKET_TOKEN}@github.com/debugtheworldbot/scoop-keystats.git"
        git clone --depth 1 "${HTTPS_URL}" "${BUCKET_DIR}"
    else
        git clone --depth 1 "${BUCKET_REPO}" "${BUCKET_DIR}"
    fi
fi

mkdir -p "${BUCKET_DIR}/bucket"
echo "${MANIFEST}" > "${BUCKET_DIR}/bucket/keystats.json"
echo "    Wrote ${BUCKET_DIR}/bucket/keystats.json"

echo "==> Committing and pushing..."

cd "${BUCKET_DIR}"
git config user.name  "${GIT_USER_NAME:-github-actions[bot]}"
git config user.email "${GIT_USER_EMAIL:-github-actions[bot]@users.noreply.github.com}"

git add bucket/keystats.json

if git diff --cached --quiet; then
    echo "    No changes to commit (manifest already up to date)."
else
    git commit -m "chore: update keystats to v${VERSION}"
    git push origin HEAD
    echo "    Pushed to ${BUCKET_REPO}"
fi

echo ""
echo "=== Done ==="
echo "Users can install with:"
echo "  scoop bucket add keystats https://github.com/debugtheworldbot/scoop-keystats"
echo "  scoop install keystats"
