#!/bin/bash

set -euo pipefail

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "Not inside a git repository." >&2
    exit 1
fi

pick_tags() {
    git tag --list \
        | sort -V \
        | tail -n 2
}

if [[ $# -eq 0 ]]; then
    TAG_OUTPUT="$(pick_tags)"
    FROM_TAG="$(printf '%s\n' "${TAG_OUTPUT}" | sed -n '1p')"
    TO_TAG="$(printf '%s\n' "${TAG_OUTPUT}" | sed -n '2p')"
    if [[ -z "${FROM_TAG:-}" || -z "${TO_TAG:-}" ]]; then
        echo "Need at least two git tags." >&2
        exit 1
    fi
elif [[ $# -eq 2 ]]; then
    FROM_TAG="$1"
    TO_TAG="$2"
else
    echo "Usage: $0 [from_tag to_tag]" >&2
    exit 1
fi

if ! git rev-parse "$FROM_TAG" >/dev/null 2>&1; then
    echo "Unknown tag: $FROM_TAG" >&2
    exit 1
fi

if ! git rev-parse "$TO_TAG" >/dev/null 2>&1; then
    echo "Unknown tag: $TO_TAG" >&2
    exit 1
fi

echo "FROM_TAG=$FROM_TAG"
echo "TO_TAG=$TO_TAG"
echo
echo "[COMMITS]"
git log --reverse --pretty=format:'%h%x09%s' "${FROM_TAG}..${TO_TAG}"
echo
echo
echo "[FILES]"
git diff --name-only "${FROM_TAG}..${TO_TAG}"
echo
echo "[STAT]"
git diff --stat "${FROM_TAG}..${TO_TAG}"
