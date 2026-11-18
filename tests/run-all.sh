#!/usr/bin/env bash
# Run the okf self-tests: syntax-check the shell, Node and JSON files, then
# the behavior suites. Green here = the gates' and the hook's safety contracts
# hold on THIS machine. Requires git and node (the gates are Node scripts).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
overall=0

command -v git  >/dev/null 2>&1 || { echo "run-all: git is required"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "run-all: node is required (>= 18) — the OKF gates are Node scripts"; exit 1; }

echo "== syntax check (bash -n, node --check, JSON) =="
bad=0
while IFS= read -r f; do
  bash -n "$f" 2>/dev/null || { echo "  SYNTAX FAIL: $f"; bad=1; }
done < <( { find "$ROOT/hooks" "$HERE" -name '*.sh' -type f 2>/dev/null; echo "$ROOT/bin/okf"; } | sort)
while IFS= read -r f; do
  node --check "$f" 2>/dev/null || { echo "  SYNTAX FAIL: $f"; bad=1; }
done < <(find "$ROOT/scripts" -name '*.mjs' -type f 2>/dev/null | sort)
while IFS= read -r f; do
  node -e 'JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"))' "$f" 2>/dev/null \
    || { echo "  JSON FAIL: $f"; bad=1; }
done < <(find "$ROOT/.claude-plugin" "$ROOT/hooks" "$ROOT/templates" -name '*.json' -type f 2>/dev/null | sort)
if [ "$bad" -eq 0 ]; then echo "  all shell, node and JSON files parse."; else overall=1; fi

for t in okf-gates guard-behavior; do
  echo "== $t =="
  bash "$HERE/$t.sh" || overall=1
done

if [ "$overall" -eq 0 ]; then
  echo "ALL SELF-TESTS PASSED"
else
  echo "SELF-TEST FAILURES — see above"
fi
exit "$overall"
