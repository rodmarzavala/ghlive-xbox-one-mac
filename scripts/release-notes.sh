#!/usr/bin/env bash
# Prints the CHANGELOG.md section for a version ("## [0.1.0] ..." or "## 0.1.0 ..."), or a fallback line.
# Usage: scripts/release-notes.sh <version> [changelog]
set -euo pipefail

version="${1:?usage: release-notes.sh <version> [changelog]}"
changelog="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/CHANGELOG.md}"

section=""
if [[ -f "$changelog" ]]; then
    section="$(awk -v version="$version" '
        /^## / {
            if (inside) exit
            heading = $0
            sub(/^## \[?v?/, "", heading)
            if (index(heading, version) == 1) {
                rest = substr(heading, length(version) + 1)
                if (rest == "" || rest ~ /^[] (]/) { inside = 1; next }
            }
        }
        inside { print }
    ' "$changelog")"
fi

if [[ -n "${section//[[:space:]]/}" ]]; then
    printf '%s\n' "$section"
else
    printf 'GHLive %s\n' "$version"
fi
