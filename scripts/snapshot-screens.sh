#!/usr/bin/env bash
# Snapshots the staged screenshots (preview.png + docs/screens/) into
# docs/history/<version>/, refreshes docs/history/latest/ as a copy of it (the
# README links there, so it never needs editing per release), and rebuilds the
# docs/history/README.md gallery, newest first. A copy, not a symlink:
# symlinks are not allowed inside a plugin.
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
  rm -rf docs/history/latest
  cp -r "$dir" docs/history/latest
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
