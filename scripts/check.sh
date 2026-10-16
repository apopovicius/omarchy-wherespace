#!/usr/bin/env bash
# Pre-release checks. Run on every push and before every release; a failure
# stops the release before anything is bumped or published.
#
#   1. manifest + marketplace rules (scripts/validate.sh)
#   2. QML lint: syntax errors, duplicate bindings and similar fail the build
#   3. README install/remove commands match the manifest id and this repo,
#      and every Text renders plain text (untrusted titles, names)
#   4. install simulation: a fresh clone, like `omarchy plugin add`, validates
#
# Usage: scripts/check.sh   (QMLLINT=/path/to/qmllint to pick a Qt 6 qmllint)
set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
  echo "check: $*" >&2
  exit 1
}

step() {
  echo "== $*"
}

# 1 ----------------------------------------------------------------------
step "manifest and marketplace rules"
scripts/validate.sh

# 2 ----------------------------------------------------------------------
step "QML lint"
QMLLINT="${QMLLINT:-}"
if [[ -z $QMLLINT ]]; then
  for candidate in /usr/lib/qt6/bin/qmllint /usr/lib/x86_64-linux-gnu/qt6/bin/qmllint qmllint6 qmllint; do
    if command -v "$candidate" >/dev/null 2>&1; then QMLLINT=$(command -v "$candidate"); break; fi
  done
fi
[[ -n $QMLLINT ]] || fail "qmllint (Qt 6) not found; set QMLLINT"

# Omarchy's own modules (qs.*, Quickshell) aren't available here, so import
# warnings are expected noise; these categories are real bugs.
fatal='\[(duplicate-property-binding|duplicated-name|read-only-property|syntax)\]'

lint() {
  # Exit codes differ between Qt versions (some fail on any warning), so only
  # the categories above decide.
  local out
  out=$("$QMLLINT" "$1" 2>&1) || true
  if grep -qE "$fatal" <<<"$out"; then
    grep -E "$fatal" <<<"$out" | head -20 >&2
    return 1
  fi
}

# The linter must catch known-bad files, or a silently broken setup would
# pass everything.
for fixture in scripts/fixtures/*.qml; do
  if lint "$fixture" 2>/dev/null; then
    fail "qmllint did not flag $fixture; is it a recent Qt 6?"
  fi
done

for file in *.qml; do
  lint "$file" || fail "QML lint failed in $file"
done

step "untrusted text renders as plain text"
# Window titles, app names and monitor names come from other programs. A Text
# left in the default AutoText format parses them as rich text, so a web page
# title with <img src=...> would make the shell fetch that URL. Every Text
# must declare textFormat: Text.PlainText.
python3 - *.qml <<'PY'
import re, sys
bad = []
for path in sys.argv[1:]:
    lines = open(path).read().split("\n")
    for i, line in enumerate(lines):
        if re.match(r"\s*Text\s*\{\s*$", line):
            depth, body = 0, []
            for j in range(i, len(lines)):
                depth += lines[j].count("{") - lines[j].count("}")
                body.append(lines[j])
                if depth == 0:
                    break
            own = [b for b in body[1:] if re.match(r"\s*textFormat\s*:\s*Text\.PlainText\b", b)]
            if not own:
                bad.append(f"{path}:{i + 1}")
if bad:
    sys.exit("check: Text without textFormat: Text.PlainText at " + ", ".join(bad))
PY

step "no shell commands, no shared temp paths"
# Commands run as argument lists through the widget's queue, never as shell
# strings; state lives in $XDG_RUNTIME_DIR, never in a shared /tmp.
code_only() { sed -E 's#//.*$##' "$@"; }
if code_only *.qml | grep -nE '\bbar\.run\(|"(bash|sh)", *"-c", *[^ `]' >/dev/null; then
  fail "a command is run through a shell string; use runCommand([...])"
fi
if code_only *.qml | grep -nE '"/tmp' >/dev/null; then
  fail "a shared /tmp path is used; keep state in XDG_RUNTIME_DIR"
fi

# 3 ----------------------------------------------------------------------
step "README install and remove commands"
id=$(jq -r .id manifest.json)
repo="${GITHUB_REPOSITORY:-$(git remote get-url origin 2>/dev/null | sed -E 's#^(git@github.com:|https://github.com/)##; s#\.git$##')}"
[[ -n $repo ]] || fail "cannot tell which GitHub repo this is"
grep -qF "omarchy plugin add https://github.com/${repo}" README.md || fail "README install command doesn't use https://github.com/${repo}"
grep -qF "omarchy plugin enable ${id} " README.md || fail "README enable command doesn't use ${id}"
grep -qF "omarchy plugin remove ${id}" README.md || fail "README remove command doesn't use ${id}"
if grep -oE 'io\.github\.[A-Za-z0-9._-]+' README.md | grep -vxF "$id" | grep -q .; then
  fail "README mentions a plugin id other than ${id}"
fi

# 4 ----------------------------------------------------------------------
step "install simulation (fresh clone)"
untracked=$(git ls-files --others --exclude-standard -- ':(glob)*.qml' manifest.json)
[[ -z $untracked ]] || fail "not committed, so users would not get it: $untracked"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git clone --quiet --no-hardlinks "file://$PWD" "$tmp/$id"
(cd "$tmp/$id" && scripts/validate.sh)
for file in *.qml; do
  [[ -f $tmp/$id/$file ]] || fail "$file is missing from a fresh install"
done

echo "check: all checks passed"
