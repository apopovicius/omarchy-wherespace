#!/usr/bin/env bash
# Validates the plugin the way Omarchy and the plugin marketplace will:
# - the manifest checks from `omarchy plugin validate` (schema, id, entry
#   points, kinds, no symlinks), so CI can run them without Omarchy installed;
# - the marketplace's listing rules (README, LICENSE, preview limits, author,
#   description, version);
# - optionally, that a release tag matches the manifest version.
#
# Usage: scripts/validate.sh [--tag vX.Y.Z]
set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
  echo "validate: $*" >&2
  exit 1
}

TAG=""
if [[ ${1:-} == --tag ]]; then
  TAG="${2:-}"
  [[ -n $TAG ]] || fail "--tag needs a value"
fi

MANIFEST=manifest.json
[[ -f $MANIFEST ]] || fail "missing manifest.json in the repository root"
jq -e . "$MANIFEST" >/dev/null 2>&1 || fail "manifest.json is not valid JSON"

# --- Omarchy manifest checks (mirrors omarchy-plugin-validate) -------------
jq -e '.schemaVersion == 1' "$MANIFEST" >/dev/null || fail "schemaVersion must be the number 1"
for field in id name version author description kinds entryPoints; do
  jq -e --arg f "$field" 'has($f) and (.[$f] != "")' "$MANIFEST" >/dev/null \
    || fail "manifest is missing '$field'"
done

ID=$(jq -r '.id' "$MANIFEST")
[[ $ID =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $ID != *".."* ]] || fail "invalid plugin id '$ID'"
[[ $ID != omarchy.* ]] || fail "plugin id '$ID' uses the reserved omarchy.* namespace"

jq -e '(.kinds | type) == "array" and (.kinds | length) > 0' "$MANIFEST" >/dev/null \
  || fail "'kinds' must be a non-empty array"
jq -e '(.entryPoints | type) == "object"' "$MANIFEST" >/dev/null || fail "'entryPoints' must be an object"
jq -e '
  if ((.barWidget? | type) == "object" and (.barWidget | has("defaultSection")))
  then .barWidget.defaultSection as $section | (["left", "center", "right"] | index($section)) != null
  else true end
' "$MANIFEST" >/dev/null || fail "'barWidget.defaultSection' must be left, center or right"

while IFS= read -r ep; do
  [[ -n $ep && $ep != /* && $ep != *".."* ]] || fail "unsafe entry point '$ep'"
  [[ -f $ep ]] || fail "entry point file not found: '$ep'"
done < <(jq -r '.entryPoints | to_entries[] | .value' "$MANIFEST")

for pair in bar:bar bar-widget:barWidget menu:menu overlay:overlay panel:panel service:service; do
  kind=${pair%%:*}
  key=${pair##*:}
  if jq -e --arg k "$kind" '(.kinds | index($k)) != null' "$MANIFEST" >/dev/null; then
    jq -e --arg e "$key" '.entryPoints | has($e)' "$MANIFEST" >/dev/null \
      || fail "kind '$kind' requires entryPoints.$key"
  fi
done

link=$(find . -name .git -prune -o -type l -print -quit)
[[ -z $link ]] || fail "symlinks are not allowed: $link"

# --- Marketplace listing rules ---------------------------------------------
[[ -f README.md ]] || fail "missing README.md in the repository root"
ls LICENSE* >/dev/null 2>&1 || fail "missing a LICENSE file in the repository root"
grep -q "omarchy plugin add" README.md || fail "README.md has no install instructions"
grep -q "omarchy plugin remove" README.md || fail "README.md has no removal instructions"

VERSION=$(jq -r '.version' "$MANIFEST")
(( ${#VERSION} <= 64 )) || fail "version is longer than 64 characters"
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+].*)?$ ]] || fail "version '$VERSION' is not semantic (X.Y.Z)"

previews=(preview.png preview.jpg preview.jpeg preview.webp preview.avif)
found=()
for p in "${previews[@]}"; do [[ -f $p ]] && found+=("$p"); done
(( ${#found[@]} <= 1 )) || fail "only one root preview is allowed, found: ${found[*]}"
if (( ${#found[@]} == 1 )); then
  size=$(stat -c %s "${found[0]}")
  (( size <= 50 * 1024 * 1024 )) || fail "${found[0]} is larger than 50 MB"
  if [[ ${found[0]} == preview.png ]]; then
    python3 - "${found[0]}" <<'PY' || exit 1
import struct, sys
with open(sys.argv[1], "rb") as f:
    head = f.read(24)
if head[:8] != b"\x89PNG\r\n\x1a\n":
    sys.exit("validate: preview.png is not a PNG file")
w, h = struct.unpack(">II", head[16:24])
if w * h > 40_000_000:
    sys.exit(f"validate: preview.png is {w}x{h}, over 40 megapixels")
PY
  fi
fi

# --- Release tag ------------------------------------------------------------
if [[ -n $TAG ]]; then
  [[ ${TAG#v} == "$VERSION" ]] || fail "tag '$TAG' does not match manifest version '$VERSION'"
fi

echo "validate: $ID $VERSION is valid"
