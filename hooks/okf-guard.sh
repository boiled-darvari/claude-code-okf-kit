#!/usr/bin/env bash
# Stop hook — enforce the OKF gate before the turn ends whenever the docs
# bundle is implicated. The plugin is installed once for every project, so the
# hook does nothing at all in a project without an OKF manifest
# (okf.config.json at the project root, or the file OKF_CONFIG names).
#
# Trigger (an honest approximation of "changed this turn"): the bundle root or
# the manifest is DIRTY (staged/unstaged/untracked) at stop time, OR the tree
# is clean and the LATEST commit touched them (covers docs committed mid-turn;
# idempotent — a green gate stays green).
#
# Dependency behavior (declared, tested):
#   - no manifest → silent exit 0: the project does not use OKF.
#   - node missing + bundle implicated → BLOCK once with a clear message
#     (fail-loud; the stop_hook_active loop-guard lets the next stop pass).
#     A project that sets "onMissingNode": "warn" in its manifest gets a
#     visible skip notice instead, and relies on CI to run the gate.
#   - jq missing → the loop guard and the manifest reads fall back to
#     whitespace-tolerant greps on the raw text; the gate itself still runs
#     (node does the real work).
#   - DECLARED fail-open (warn on stderr, allow), and nothing else: git not
#     installed, the project directory unreachable, or the directory not a
#     git work tree — in all three there is no repo claim to enforce.
#   - git ERRORS inside a real work tree (status/diff-tree failing) are
#     fail-CLOSED: the bundle is treated as implicated and the gate runs,
#     surfacing whatever is broken. So is a manifest whose docRoot cannot be
#     read.
# The hook is a convenience; CI running the gate is the authority.
set -uo pipefail

# The plugin's root: this script lives in its hooks/ folder.
SELF_DIR=${BASH_SOURCE[0]%/*}
[ "$SELF_DIR" = "${BASH_SOURCE[0]}" ] && SELF_DIR=.
PLUGIN_ROOT=$(cd "$SELF_DIR/.." 2>/dev/null && pwd -P)
CHECK_SCRIPT="$PLUGIN_ROOT/scripts/okf/check.mjs"

input=$(cat)

# Avoid loops: if we already blocked once this stop cycle, let it finish.
if command -v jq >/dev/null 2>&1; then
  active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)
else
  # HEURISTIC fallback (declared): flatten whitespace, then look for the
  # key:true pair. Tolerates newlines/tabs anywhere JSON allows them; it is
  # not a JSON parser (a nested same-name key could fool it) — jq is the
  # correct path, this only keeps the loop guard functional without it.
  if printf '%s' "$input" | tr -d '\n\r\t' | grep -qE '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
    active=true
  else
    active=false
  fi
fi
[ "$active" = "true" ] && exit 0

if ! cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null; then
  echo "okf-guard: cannot cd to project dir '${CLAUDE_PROJECT_DIR:-.}' — OKF gate skipped (declared fail-open)." >&2
  exit 0
fi

# No manifest: this project does not use OKF. Say nothing.
CONFIG_FILE="${OKF_CONFIG:-okf.config.json}"
[ -f "$CONFIG_FILE" ] || exit 0

if ! command -v git >/dev/null 2>&1; then
  echo "okf-guard: git not found — cannot scope doc changes; OKF gate skipped (declared fail-open)." >&2
  exit 0
fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "okf-guard: not a git work tree — no repo claim to enforce; OKF gate skipped (declared fail-open)." >&2
  exit 0
fi

# One string field of the manifest, on stdout; nothing when it is absent or
# not a string. With jq it is read as JSON; without, by a HEURISTIC (declared)
# that finds the first "key": "value" pair in the whitespace-flattened text.
manifest_field() { # $1 = key
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$1" '.[$k] | strings' "$CONFIG_FILE" 2>/dev/null
  else
    tr -d '\n\r\t' < "$CONFIG_FILE" 2>/dev/null |
      sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
  fi
}

implicated=0
# The gates default docRoot to "doc" when the manifest names none. A docRoot
# that is present but unusable here (not a plain relative path) fails CLOSED:
# the gate runs and reports what is wrong with the manifest.
DOC_ROOT=$(manifest_field docRoot)
if [ -z "$DOC_ROOT" ]; then
  if grep -q '"docRoot"' "$CONFIG_FILE" 2>/dev/null; then implicated=1; fi
  DOC_ROOT="doc"
fi
case "$DOC_ROOT" in
  /*|-*|..|../*|*/../*|*/..) implicated=1; DOC_ROOT="doc" ;;
esac
if ! [[ "$DOC_ROOT" =~ ^[A-Za-z0-9._/-]+$ ]]; then implicated=1; DOC_ROOT="doc"; fi

# Scope: the bundle itself and the manifest — a turn that edits the manifest
# must re-prove conformance even when no doc changed. --root covers a
# repository whose very first commit added the docs. Git ERRORS here (inside
# a confirmed work tree) fail CLOSED: treat as implicated so the gate runs
# and surfaces the breakage.
SCOPE=("$DOC_ROOT" "$CONFIG_FILE")
if [ "$implicated" = 0 ]; then
  status_out=$(git status --porcelain -- "${SCOPE[@]}" 2>/dev/null) || implicated=1
  printf '%s' "$status_out" | grep -q . && implicated=1
fi
if [ "$implicated" = 0 ]; then
  tree_out=$(git diff-tree --root --no-commit-id --name-only -r HEAD -- "${SCOPE[@]}" 2>/dev/null)
  rc=$?
  # rc!=0 with no commits yet is benign emptiness only when HEAD is unborn;
  # any other diff-tree failure fails closed.
  if [ "$rc" -ne 0 ]; then
    git rev-parse --verify HEAD >/dev/null 2>&1 && implicated=1
  else
    printf '%s' "$tree_out" | grep -q . && implicated=1
  fi
fi
[ "$implicated" = 1 ] || exit 0

if ! command -v node >/dev/null 2>&1; then
  if [ "$(manifest_field onMissingNode)" = "warn" ]; then
    # The project chose not to block without node: skip, and say so where the
    # person sees it (systemMessage) as well as on stderr.
    msg="OKF gate skipped: node is not installed, and '$DOC_ROOT/' changed this turn. The bundle is NOT validated here; CI must run the gate."
    echo "okf-guard: $msg" >&2
    printf '{"systemMessage":"%s"}\n' "$msg"
    exit 0
  fi
  {
    echo "OKF gate cannot run: node is not installed, but '$DOC_ROOT/' is implicated this turn."
    echo "Install node >= 18 (the gate scripts are Node), or set \"onMissingNode\": \"warn\" in $CONFIG_FILE to skip the gate here and rely on CI — do not treat the bundle as validated."
  } >&2
  exit 2
fi

if out=$(node "$CHECK_SCRIPT" 2>&1); then
  exit 0
fi

{
  echo "OKF gate failed — '$DOC_ROOT/' is implicated this turn but the bundle isn't conformant."
  echo "Fix before finishing (frontmatter / links / refs / stale index):"
  printf '%s\n' "$out" | tail -30
  echo
  echo "Usually: okf build-index && okf check"
} >&2
exit 2
