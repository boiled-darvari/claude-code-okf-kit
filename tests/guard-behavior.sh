#!/usr/bin/env bash
# Regression guard for the Stop hook's contract: silence in a project with no
# manifest; trigger semantics (bundle or manifest dirty, OR touched by the
# latest commit); the loop guard; the bundle root read from the manifest; and
# the declared dependency behavior — node missing blocks loudly unless the
# manifest says "onMissingNode": "warn", jq missing degrades to heuristic
# fallbacks (still enforcing), and exactly three DECLARED fail-opens (git
# missing, unreachable project dir, not a git work tree), each with a warning.
set -u
# Hermetic git: the user's global/system config (commit signing, hooks,
# defaults) must not leak into the fixtures — a global commit.gpgsign=true
# would fail setup commits and let later cases false-pass.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
unset OKF_CONFIG
ROOT=$(cd "$(dirname "$0")/.." && pwd)
GUARD="$ROOT/hooks/okf-guard.sh"
okf() { "$ROOT/bin/okf" "$@"; }
pass=0; fail=0
ok()  { echo "  ok:   $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }
commit() { git -C "$1" add -A && git -C "$1" -c user.email=t@t.t -c user.name=t commit -qm "$2"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/okf-guard-XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

write_manifest() { # $1 = file, $2 = docRoot, $3 = extra JSON members (each ending in a comma) or empty
  cat > "$1" <<EOF
{
  "template": false, "okfVersion": "0.1", "docRoot": "$2", "skipDirs": [],
  "reservedFiles": ["index.md", "log.md"], "conventionsFile": "okf-conventions.md",
  "bundleTitle": "Guard Test Bundle",
  "readmeStub": { "enabled": true, "title": "Guard Test Docs", "description": "Start at index.md." },
  "refExtensions": ["md"], "assetExcludeExts": [".png"], "activeStatus": "active",
  ${3:-}
  "folders": { "guides": "How-tos." }, "rulesAndInvariants": []
}
EOF
}
seed_bundle() { # $1 = project dir, $2 = docRoot
  mkdir -p "$1/$2/guides"
  cat > "$1/$2/okf-conventions.md" <<'EOF'
---
type: reference
title: "Conventions"
description: "Fixture conventions doc."
---
# Conventions
EOF
  cat > "$1/$2/guides/how-to.md" <<'EOF'
---
type: guide
title: "How To"
description: "Fixture."
---
# How To
EOF
}

proj="$tmp/proj"
mkdir -p "$proj/src"
write_manifest "$proj/okf.config.json" doc ""
seed_bundle "$proj" doc
( cd "$proj" && okf build-index >/dev/null 2>&1 ) || { echo "setup: build-index failed"; exit 1; }
git -C "$proj" init -q
commit "$proj" "docs baseline" || { echo "setup: baseline commit failed"; exit 1; }
echo "code" > "$proj/src/app.txt"
commit "$proj" "src only" || { echo "setup: src commit failed"; exit 1; }
export CLAUDE_PROJECT_DIR="$proj"

plain='{"stop_hook_active":false}'
active='{"stop_hook_active":true}'

# A minimal PATH: only what the hook needs, so a missing tool is a real absence.
bin="$tmp/bin"; mkdir -p "$bin"
for t in bash git node jq grep tail cat sed printf env tr; do
  p=$(command -v "$t" 2>/dev/null) && ln -s "$p" "$bin/$t" 2>/dev/null
done

# --- 1. clean tree, HEAD touches only src → silent pass ---------------------
out=$(printf '%s' "$plain" | "$GUARD" 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "clean tree + non-doc HEAD → exit 0 silent" || bad "clean-tree case rc=$rc out='$out'"

# --- 2. dirty doc + violation → blocks -------------------------------------
echo "no frontmatter" > "$proj/doc/guides/bad.md"
out=$(printf '%s' "$plain" | "$GUARD" 2>&1); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "OKF gate failed" && ok "dirty doc + violation → exit 2 with message" || bad "violation not blocked rc=$rc"

# --- 3. loop guard: stop_hook_active → pass even with violation -------------
out=$(printf '%s' "$active" | "$GUARD" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "stop_hook_active → exit 0 (loop guard)" || bad "loop guard broken rc=$rc"

# --- 4. no jq: loop guard falls back to grep; gate still enforces -----------
rm "$bin/jq"
out=$(printf '%s' "$plain" | PATH="$bin" "$GUARD" 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "no jq: still enforces (exit 2 on violation)" || bad "no-jq enforcement lost rc=$rc"
out=$(printf '%s' "$active" | PATH="$bin" "$GUARD" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "no jq: loop guard grep fallback works" || bad "no-jq loop guard broken rc=$rc"
spaced='{ "stop_hook_active"  :  true }'
out=$(printf '%s' "$spaced" | PATH="$bin" "$GUARD" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "no jq: fallback tolerates JSON whitespace variants" || bad "no-jq fallback missed spaced JSON rc=$rc"
newlined=$(printf '{ "stop_hook_active"\n  : true }')
out=$(printf '%s' "$newlined" | PATH="$bin" "$GUARD" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "no jq: fallback tolerates newline between key and colon" || bad "no-jq fallback missed newlined JSON rc=$rc"
p=$(command -v jq) && ln -s "$p" "$bin/jq"

# --- 5. no node + doc implicated → loud block -------------------------------
rm "$bin/node"
out=$(printf '%s' "$plain" | PATH="$bin" "$GUARD" 2>&1); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "node is not installed" && ok "no node: loud block, never a silent pass" || bad "no-node case rc=$rc"

# --- 5b. no node + "onMissingNode": "warn" → visible skip, no block ----------
write_manifest "$proj/okf.config.json" doc '"onMissingNode": "warn",'
out=$(printf '%s' "$plain" | PATH="$bin" "$GUARD" 2>"$tmp/err"); rc=$?
[ "$rc" -eq 0 ] && grep -q "OKF gate skipped" "$tmp/err" \
  && printf '%s' "$out" | jq -e '.systemMessage | test("NOT validated")' >/dev/null 2>&1 \
  && ok "no node + warn: exit 0 with a systemMessage and a stderr notice" || bad "warn mode rc=$rc out='$out'"
rm "$bin/jq"
out=$(printf '%s' "$plain" | PATH="$bin" "$GUARD" 2>"$tmp/err"); rc=$?
[ "$rc" -eq 0 ] && grep -q "OKF gate skipped" "$tmp/err" && ok "no node + warn, no jq: the fallback still reads the setting" || bad "warn mode without jq rc=$rc"
p=$(command -v jq) && ln -s "$p" "$bin/jq"
p=$(command -v node) && ln -s "$p" "$bin/node"
# With node present the setting changes nothing: the violation still blocks.
out=$(printf '%s' "$plain" | PATH="$bin" "$GUARD" 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "warn mode never weakens the gate when node is present" || bad "warn mode weakened the gate rc=$rc"
git -C "$proj" checkout -q -- okf.config.json

# --- 6. no git → the one declared fail-open (warn + allow) ------------------
rm "$bin/git"
out=$(printf '%s' "$plain" | PATH="$bin" "$GUARD" 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "git not found" && ok "no git: declared fail-open with warning" || bad "no-git case rc=$rc out='$out'"
p=$(command -v git) && ln -s "$p" "$bin/git"

# --- 7. dirty doc + conformant → pass ---------------------------------------
rm "$proj/doc/guides/bad.md"
printf '\nExtra body paragraph.\n' >> "$proj/doc/guides/how-to.md"
out=$(printf '%s' "$plain" | "$GUARD" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "dirty doc + conformant bundle → exit 0" || bad "conformant dirty doc blocked rc=$rc out='$(printf '%s' "$out" | tail -2)'"
git -C "$proj" checkout -q -- doc/guides/how-to.md

# --- 8. committed-mid-turn: clean tree, HEAD touched doc, violation ---------
echo "no frontmatter" > "$proj/doc/guides/bad.md"
commit "$proj" "bad doc committed" || { echo "setup: mid-turn commit failed"; exit 1; }
[ -z "$(git -C "$proj" status --porcelain)" ] \
  || { echo "setup: tree not clean after commit — case would not exercise the committed path"; exit 1; }
out=$(printf '%s' "$plain" | "$GUARD" 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "clean tree but HEAD touched doc → still gated (exit 2)" || bad "committed-doc bypass rc=$rc"
git -C "$proj" reset -q --hard HEAD~1

# --- 9. non-doc dirty file only → silent pass -------------------------------
echo "more code" >> "$proj/src/app.txt"
out=$(printf '%s' "$plain" | "$GUARD" 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "non-doc dirt only → exit 0 silent" || bad "non-doc dirt triggered gate rc=$rc"
git -C "$proj" checkout -q -- src/app.txt

# --- 10. manifest changes are in scope (dirty manifest, clean docs) ----------
sed 's/"template": false/"template": true/' "$proj/okf.config.json" > "$tmp/m.json" && cp "$tmp/m.json" "$proj/okf.config.json"
out=$(printf '%s' "$plain" | "$GUARD" 2>&1); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "template" \
  && ok "dirty manifest with clean docs → still gated (broken config caught)" \
  || bad "manifest change bypassed the guard rc=$rc"
git -C "$proj" checkout -q -- okf.config.json

# --- 11. docs added in the repository's ROOT commit are in scope ------------
proj2="$tmp/proj2"
mkdir -p "$proj2/doc/guides"
cp "$proj/okf.config.json" "$proj2/"
cp "$proj/doc/okf-conventions.md" "$proj2/doc/"
echo "no frontmatter" > "$proj2/doc/guides/bad.md"
git -C "$proj2" init -q
commit "$proj2" "root commit with bad doc" || { echo "setup: proj2 root commit failed"; exit 1; }
out=$(printf '%s' "$plain" | CLAUDE_PROJECT_DIR="$proj2" "$GUARD" 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "root-commit docs → still gated (diff-tree --root)" || bad "root-commit docs bypassed rc=$rc"

# --- 12. non-repo project dir → declared fail-open with warning -------------
norepo="$tmp/norepo"; mkdir -p "$norepo"
cp "$proj/okf.config.json" "$norepo/"
out=$(printf '%s' "$plain" | CLAUDE_PROJECT_DIR="$norepo" "$GUARD" 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "not a git work tree" \
  && ok "non-repo dir: declared fail-open with warning" || bad "non-repo dir rc=$rc out='$out'"

# --- 13. a project with NO manifest is none of the hook's business -----------
nocfg="$tmp/nocfg"; mkdir -p "$nocfg/doc/guides"
git -C "$nocfg" init -q
echo "no frontmatter" > "$nocfg/doc/guides/bad.md"
out=$(printf '%s' "$plain" | CLAUDE_PROJECT_DIR="$nocfg" "$GUARD" 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "no manifest → exit 0 silent, even with a nonconformant doc/" || bad "no-manifest project touched rc=$rc out='$out'"

# --- 14. the bundle root comes from the manifest ------------------------------
proj3="$tmp/proj3"
mkdir -p "$proj3/doc"
write_manifest "$proj3/okf.config.json" docs ""
seed_bundle "$proj3" docs
( cd "$proj3" && okf build-index >/dev/null 2>&1 ) || { echo "setup: proj3 build-index failed"; exit 1; }
git -C "$proj3" init -q
commit "$proj3" "docs baseline" || { echo "setup: proj3 commit failed"; exit 1; }
echo "x" > "$proj3/keep.txt"
commit "$proj3" "non-doc commit" || { echo "setup: proj3 second commit failed"; exit 1; }
echo "not part of the bundle" > "$proj3/doc/stray.md"
out=$(printf '%s' "$plain" | CLAUDE_PROJECT_DIR="$proj3" "$GUARD" 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "docRoot docs: dirt under doc/ is out of scope" || bad "wrong folder gated rc=$rc out='$out'"
echo "no frontmatter" > "$proj3/docs/guides/bad.md"
out=$(printf '%s' "$plain" | CLAUDE_PROJECT_DIR="$proj3" "$GUARD" 2>&1); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "'docs/'" && ok "docRoot docs: a violation under docs/ is gated" || bad "configured docRoot not gated rc=$rc"
rm "$bin/jq"
out=$(printf '%s' "$plain" | CLAUDE_PROJECT_DIR="$proj3" PATH="$bin" "$GUARD" 2>&1); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "'docs/'" && ok "docRoot docs, no jq: the fallback reads the manifest" || bad "no-jq docRoot fallback rc=$rc"
p=$(command -v jq) && ln -s "$p" "$bin/jq"
rm "$proj3/docs/guides/bad.md" "$proj3/doc/stray.md"

# --- 15. a docRoot the hook cannot use fails CLOSED ---------------------------
sed 's/"docRoot": "docs"/"docRoot": 5/' "$proj3/okf.config.json" > "$tmp/m.json" && cp "$tmp/m.json" "$proj3/okf.config.json"
commit "$proj3" "broken manifest committed" || { echo "setup: proj3 broken-manifest commit failed"; exit 1; }
echo "y" >> "$proj3/keep.txt"
commit "$proj3" "non-doc commit after it" || { echo "setup: proj3 third commit failed"; exit 1; }
out=$(printf '%s' "$plain" | CLAUDE_PROJECT_DIR="$proj3" "$GUARD" 2>&1); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "docRoot must be" \
  && ok "unusable docRoot → gate runs and names the manifest error (clean tree, HEAD elsewhere)" \
  || bad "unusable docRoot slipped through rc=$rc out='$(printf '%s' "$out" | tail -2)'"

echo "guard-behavior: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
