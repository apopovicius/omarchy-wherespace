#!/usr/bin/env bash
# Snapshots the current screenshots into docs/history/<version>/ and rebuilds
# the docs/history/README.md gallery (newest first), so every release keeps
# a record of how wherespace looked.
#
# Usage: scripts/snapshot-screens.sh vX.Y.Z   snapshot, then rebuild the gallery
#        scripts/snapshot-screens.sh --gallery  only rebuild the gallery
set -euo pipefail

cd "$(dirname "$0")/.."

version="${1:?usage: scripts/snapshot-screens.sh vX.Y.Z | --gallery}"
if [[ $version != --gallery ]]; then
  dir="docs/history/${version}"
  mkdir -p "$dir"
  cp preview.png "$dir/preview.png"
  for shot in docs/screens/*.png; do
    [[ -e $shot ]] && cp "$shot" "$dir/"
  done
fi

{
  echo "# wherespace through its releases"
  echo
  echo "Screenshots captured for each release, newest first."
  for release in $(ls docs/history | grep -E '^v[0-9]' | sort -rV); do
    echo
    echo "## ${release}"
    echo
    echo "![${release}](${release}/preview.png)"
    [[ -f docs/history/${release}/settings.png ]] && echo && echo "<img src=\"${release}/settings.png\" alt=\"${release} settings\" width=\"280\">"
  done
} > docs/history/README.md
