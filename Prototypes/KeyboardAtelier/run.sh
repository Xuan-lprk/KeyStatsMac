#!/bin/zsh
set -euo pipefail
prototype_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$prototype_dir/../.." && pwd)"
app_dir="$prototype_dir/.build/KeyboardAtelier.app"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
xcrun swiftc -O -target arm64-apple-macos13.0 \
    -module-cache-path "$prototype_dir/.build/ModuleCache" \
    "$repo_dir/KeyStats/AppStats.swift" "$repo_dir/KeyStats/StatsModels.swift" \
    "$repo_dir/KeyStats/KeyboardLayout.swift" "$repo_dir/KeyStats/PhysicalKeyMapping.swift" \
    "$repo_dir/KeyStats/CumulativeKeyboardSnapshot.swift" \
    "$repo_dir/KeyStats/KeyboardTrackingPeriod.swift" "$repo_dir/KeyStats/KeyboardUsageProgress.swift" \
    "$prototype_dir/AtelierData.swift" "$prototype_dir/PorcelainSceneRenderer.swift" \
    "$prototype_dir/AtelierView.swift" "$prototype_dir/main.swift" \
    -o "$app_dir/Contents/MacOS/KeyboardAtelier"
cp "$prototype_dir/Info.plist" "$app_dir/Contents/Info.plist"
for language in en zh-Hans zh-Hant; do
    mkdir -p "$app_dir/Contents/Resources/$language.lproj"
    cp "$prototype_dir/$language.lproj/Localizable.strings" "$app_dir/Contents/Resources/$language.lproj/"
done
codesign --force --sign - "$app_dir" >/dev/null 2>&1
if [[ "${1:-}" == "--build-only" ]]; then
    print -r -- "$app_dir"
elif [[ "${1:-}" == "--render-dir" || "${1:-}" == "--geometry-check" ]]; then
    "$app_dir/Contents/MacOS/KeyboardAtelier" "$@"
else
    open -n "$app_dir"
fi
