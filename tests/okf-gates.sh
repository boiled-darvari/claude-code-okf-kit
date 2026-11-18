#!/usr/bin/env bash
# Regression guard for the four OKF gates + orchestrator, run from a scratch
# project that holds only a manifest and a bundle — the gates themselves stay
# in the plugin, as they do in a real install. Pins the fail-loud and safety
# contracts: a missing, template, malformed or unsafe manifest refuses; each
# violation class fails its gate; --fix repoints prose refs but never rewrites
# URLs; pins fail on missing/ambiguous; pre-existing files are refused without
# --adopt; reserved files are exempt; the orchestrator is chain-safe.
set -u
# Hermetic git (none of these fixtures use git, but keep the suite immune to
# any future git usage inheriting user/system config).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
unset OKF_CONFIG
ROOT=$(cd "$(dirname "$0")/.." && pwd)
okf() { "$ROOT/bin/okf" "$@"; }
pass=0; fail=0
ok()  { echo "  ok:   $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/okf-gates-XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

proj="$tmp/proj"
mkdir -p "$proj/doc/guides"
cd "$proj" || exit 1
MARKER=$(grep -o '<!-- generated-by:.*-->' "$ROOT/scripts/okf/build-index.mjs" | head -1)

# --- 0. the wrapper: usage, unknown command ----------------------------------
okf --help >"$tmp/o" 2>&1
[ $? -eq 0 ] && grep -q "Usage" "$tmp/o" && ok "okf --help prints usage, exit 0" || bad "okf --help broken"
okf >"$tmp/o" 2>&1
[ $? -eq 2 ] && ok "okf with no command → exit 2" || bad "bare okf did not exit 2"
okf nonsense >"$tmp/o" 2>&1
[ $? -eq 2 ] && grep -q "unknown command" "$tmp/o" && ok "unknown command → exit 2, named" || bad "unknown command accepted"

# --- 0b. no manifest → the gate refuses with guidance ------------------------
okf check >"$tmp/o" 2>&1
if [ $? -ne 0 ] && grep -q "no okf.config.json" "$tmp/o"; then
  ok "no manifest → gate fails with guidance"
else bad "missing manifest was accepted"; fi

# --- 1. template config refuses to run ---------------------------------------
cp "$ROOT/templates/okf.config.json" okf.config.json
okf check >"$tmp/o" 2>&1
if [ $? -ne 0 ] && grep -q "template" "$tmp/o"; then
  ok "template config → gate fails with guidance"
else bad "template config was accepted"; fi

# --- 1b. template flag must be EXPLICITLY false — removing the line refuses --
grep -v '"template"' okf.config.json > "$tmp/noflag.json" && cp "$tmp/noflag.json" okf.config.json
okf check >"$tmp/o" 2>&1
if [ $? -ne 0 ] && grep -q "EXPLICITLY" "$tmp/o"; then
  ok "missing template flag → gate still refuses"
else bad "deleted template line armed the gate"; fi

# --- 1c. a manifest that is not JSON, or not an object, refuses --------------
printf '{ "template": false, ' > okf.config.json
okf check >"$tmp/o" 2>&1
[ $? -ne 0 ] && grep -q "not valid JSON" "$tmp/o" && ok "malformed JSON → gate refuses" || bad "malformed JSON accepted"
printf '[]\n' > okf.config.json
okf check >"$tmp/o" 2>&1
[ $? -ne 0 ] && grep -q "one JSON object" "$tmp/o" && ok "non-object manifest → gate refuses" || bad "array manifest accepted"

# --- 1d. a docRoot outside the repository is refused (the generator writes there)
for d in '../elsewhere' '/tmp/elsewhere' 'doc/../..'; do
  printf '{ "template": false, "docRoot": "%s" }\n' "$d" > okf.config.json
  okf build-index >"$tmp/o" 2>&1
  [ $? -ne 0 ] && grep -q "docRoot must be a path inside the repository" "$tmp/o" && ok "docRoot $d → refused" || bad "docRoot $d accepted"
done

# --- 1e. a field of the wrong type is named, not crashed on ------------------
printf '{ "template": false, "skipDirs": "assets", "onMissingNode": "maybe" }\n' > okf.config.json
okf validate >"$tmp/o" 2>&1
[ $? -ne 0 ] && grep -q "skipDirs must be a list of strings" "$tmp/o" && grep -q "onMissingNode must be" "$tmp/o" \
  && ok "wrong field types → refused, every bad field named" || bad "wrong field types accepted or unnamed"

write_config() { # $1 = rulesAndInvariants JSON array, $2 = readmeStub enabled (default true)
  cat > okf.config.json <<EOF
{
  "template": false,
  "okfVersion": "0.1",
  "docRoot": "doc",
  "skipDirs": [],
  "reservedFiles": ["index.md", "log.md"],
  "conventionsFile": "okf-conventions.md",
  "bundleTitle": "Test Bundle",
  "readmeStub": { "enabled": ${2:-true}, "title": "Test Docs", "description": "Start at index.md." },
  "refExtensions": ["md", "json"],
  "assetExcludeExts": [".png"],
  "activeStatus": "active",
  "folders": { "guides": "How-tos.", "reference": "Lookup." },
  "rulesAndInvariants": ${1}
}
EOF
}
write_config "[]"

cat > doc/okf-conventions.md <<'EOF'
---
type: reference
title: "Conventions"
description: "Fixture conventions doc."
---
# Conventions
EOF

cat > doc/guides/how-to.md <<'EOF'
---
type: guide
title: "How To"
description: "A fixture guide."
status: active
---

# How To

Body.
EOF

# --- 2. green path ----------------------------------------------------------
okf build-index >"$tmp/o" 2>&1 && okf check >"$tmp/o2" 2>&1 \
  && ok "configured bundle: build + full gate green" \
  || { bad "green path failed: $(tail -3 "$tmp/o" "$tmp/o2" 2>/dev/null | tr '\n' ' ')"; }

# --- 2b. a docRoot written as ./doc/ is the same bundle -----------------------
sed 's|"docRoot": "doc"|"docRoot": "./doc/"|' okf.config.json > "$tmp/c.json" && cp "$tmp/c.json" okf.config.json
okf check >"$tmp/o" 2>&1 && ok "docRoot ./doc/ is normalized; gate still green" || bad "docRoot ./doc/ broke the gate: $(tail -2 "$tmp/o" | tr '\n' ' ')"
write_config "[]"

# --- 2c. a minimal manifest runs on the defaults ------------------------------
printf '{ "template": false }\n' > okf.config.json
okf build-index >"$tmp/o" 2>&1 && okf check >"$tmp/o2" 2>&1 \
  && ok "minimal manifest: defaults fill every other field" \
  || bad "minimal manifest failed: $(tail -3 "$tmp/o" "$tmp/o2" 2>/dev/null | tr '\n' ' ')"

# --- 2d. an unknown key is reported, never fatal; _notes are silent -----------
printf '{ "template": false, "skipDir": ["x"], "_note": "ours" }\n' > okf.config.json
okf validate >"$tmp/o" 2>&1
rc=$?
[ "$rc" -eq 0 ] && grep -q 'unknown key "skipDir"' "$tmp/o" && ! grep -q '_note' "$tmp/o" \
  && ok "unknown key → warned and ignored; _note keys silent" || bad "unknown-key handling wrong rc=$rc"

# --- 2e. OKF_CONFIG names another manifest ------------------------------------
mkdir -p conf
write_config "[]"; mv okf.config.json conf/okf.json
cp "$ROOT/templates/okf.config.json" okf.config.json
okf validate >"$tmp/o" 2>&1 && bad "template manifest accepted while testing OKF_CONFIG" || true
OKF_CONFIG=conf/okf.json okf validate >"$tmp/o" 2>&1 \
  && ok "OKF_CONFIG=<path> selects the manifest" || bad "OKF_CONFIG ignored: $(tail -2 "$tmp/o" | tr '\n' ' ')"
rm -rf conf
write_config "[]"
okf build-index >"$tmp/o" 2>&1

# --- 3. missing frontmatter fails validate ---------------------------------
echo "no frontmatter here" > doc/guides/bad.md
okf validate >"$tmp/o" 2>&1
[ $? -ne 0 ] && grep -q "frontmatter" "$tmp/o" && ok "missing frontmatter → validate fails" || bad "frontmatter violation passed"
rm doc/guides/bad.md

# --- 3b. semantically empty `type` values fail validate ----------------------
for t in '""' '~' 'NULL' '"" # looks set' '!!null null' '|-' '[]'; do
  printf -- '---\ntype: %s\ntitle: "X"\n---\n# X\n' "$t" > doc/guides/empty-type.md
  okf validate >"$tmp/o" 2>&1
  [ $? -ne 0 ] && grep -q "empty" "$tmp/o" && ok "type: $t → validate fails" || bad "type: $t passed validate"
done
rm doc/guides/empty-type.md

# --- 3c. configured conventions doc is enforced -----------------------------
mv doc/okf-conventions.md "$tmp/conv-away.md"
okf validate >"$tmp/o" 2>&1
[ $? -ne 0 ] && grep -q "conventionsFile" "$tmp/o" && ok "missing configured conventions doc → validate fails" || bad "missing conventions doc passed"
mv "$tmp/conv-away.md" doc/okf-conventions.md

# --- 4. broken link fails check-links --------------------------------------
cat > doc/guides/linky.md <<'EOF'
---
type: guide
title: "Linky"
description: "Has a broken link."
---
# Linky
See [gone](./nope.md).
EOF
okf check-links >"$tmp/o" 2>&1
[ $? -ne 0 ] && grep -q "nope.md" "$tmp/o" && ok "broken link → check-links fails" || bad "broken link passed"
rm doc/guides/linky.md

cat > doc/guides/reflink.md <<'EOF'
---
type: guide
title: "Reflink"
description: "Broken reference-style link."
---
# Reflink
See [the ref][r].

[r]: ./nope2.md
EOF
okf check-links >"$tmp/o" 2>&1
[ $? -ne 0 ] && grep -q "nope2.md" "$tmp/o" && ok "broken reference-style link → check-links fails" || bad "reference-style link passed"
rm doc/guides/reflink.md

cat > doc/guides/refuse.md <<'EOF'
---
type: guide
title: "Refuse"
description: "Reference usage without a definition."
---
# Refuse
See [the guide][missing].
EOF
okf check-links >"$tmp/o" 2>&1
[ $? -ne 0 ] && grep -q "never defined" "$tmp/o" && ok "reference usage without definition → check-links fails" || bad "undefined reference usage passed"
rm doc/guides/refuse.md

cat > doc/guides/angle.md <<'EOF'
---
type: guide
title: "Angle"
description: "Angle-bracket destination and code-fence examples."
---
# Angle
See [the target][t].

[t]: <./angle.md>

Example (must NOT be treated as a live reference):

```
See [example][not-a-real-ref] and [gone](./nope3.md).
```
EOF
okf check-links >"$tmp/o" 2>&1 \
  && ok "angle-bracket target resolves; fenced-code examples ignored" \
  || bad "angle/fence handling broken: $(tail -2 "$tmp/o" | tr '\n' ' ')"
rm doc/guides/angle.md

# --- 5. stale prose ref fails; --fix repoints but never touches URLs --------
mkdir -p doc/reference
cat > doc/reference/target.md <<'EOF'
---
type: reference
title: "Target"
description: "Moved here."
---
# Target
EOF
cat > doc/guides/mentions.md <<'EOF'
---
type: guide
title: "Mentions"
description: "Mentions a moved file and a URL."
---
# Mentions
See `doc/old/target.md` for details.
External: https://example.com/doc/old/target.md stays untouched.
EOF
okf check-refs >"$tmp/o" 2>&1
[ $? -ne 0 ] && grep -q "doc/old/target.md" "$tmp/o" && ok "stale prose ref → check-refs fails" || bad "stale ref passed"
okf check-refs --fix >"$tmp/o" 2>&1
grep -q '`doc/reference/target.md`' doc/guides/mentions.md \
  && ok "--fix repointed the prose ref" || bad "--fix did not repoint"
grep -q "https://example.com/doc/old/target.md" doc/guides/mentions.md \
  && ok "--fix left the URL untouched" || bad "--fix corrupted a URL"
okf check-refs >"$tmp/o" 2>&1 && ok "refs green after --fix" || bad "refs still stale after --fix"

# --- 5b. URL query strings and mailto bodies are never flagged or rewritten -
cat > doc/guides/url-edge.md <<'EOF'
---
type: guide
title: "URL Edge"
description: "Stale-looking paths inside URLs must be left alone."
---
# URL Edge
Query: https://example.com/?next=doc/old/target.md
Mail: mailto:team@example.com?body=doc/old/target.md
Root-relative: /redirect?next=doc/old/target.md
Scheme-relative: //example.com/?next=doc/old/target.md
Parenthesized: https://example.com/?next=(doc/old/target.md)
Relative parenthesized: /redirect?next=(doc/old/target.md)
Scheme-relative parenthesized: //host/?next=(doc/old/target.md)
EOF
okf check-refs >"$tmp/o" 2>&1 && ok "paths inside URL query/mailto → not flagged" || bad "URL-embedded path flagged: $(tail -2 "$tmp/o" | tr '\n' ' ')"
cp doc/guides/url-edge.md "$tmp/url-edge.before"
okf check-refs --fix >"$tmp/o" 2>&1
cmp -s doc/guides/url-edge.md "$tmp/url-edge.before" && ok "--fix left URL-embedded paths untouched" || bad "--fix rewrote inside a URL"
rm doc/guides/url-edge.md

# --- 6. unknown basename = planned/external, ignored ------------------------
cat >> doc/guides/mentions.md <<'EOF'
Planned: doc/planned/future-thing.md (does not exist anywhere).
EOF
okf check-refs >"$tmp/o" 2>&1 && ok "unknown basename ignored (planned/external)" || bad "unknown basename flagged"

# --- 7. stale index fails --check; rebuild recovers -------------------------
okf build-index >"$tmp/o" 2>&1
okf check >"$tmp/o" 2>&1 || bad "expected green before staleness case: $(tail -2 "$tmp/o" | tr '\n' ' ')"
cat > doc/guides/new-doc.md <<'EOF'
---
type: guide
title: "New Doc"
description: "Freshly added."
---
# New Doc
EOF
okf build-index --check >"$tmp/o" 2>&1
[ $? -ne 0 ] && grep -q "STALE" "$tmp/o" && ok "new doc without rebuild → index stale" || bad "stale index passed --check"
okf build-index >"$tmp/o" 2>&1 && okf build-index --check >"$tmp/o" 2>&1 \
  && ok "rebuild recovers to green" || bad "rebuild did not recover"

# --- 8. orphan index detected AND removed by a build (convergence) ----------
mkdir -p doc/empty
printf '%s\n\n# empty/\n' "$MARKER" > doc/empty/index.md
okf build-index --check >"$tmp/o" 2>&1
[ $? -ne 0 ] && grep -q "orphan" "$tmp/o" && ok "orphan index → --check fails" || bad "orphan index passed"
okf build-index >"$tmp/o" 2>&1
[ ! -e doc/empty/index.md ] && okf build-index --check >"$tmp/o" 2>&1 \
  && ok "build removes the orphan; check converges to green" || bad "orphan not removed by build"
rmdir doc/empty

# --- 8b. disabling the README stub removes the generated README --------------
write_config "[]" false
okf build-index >"$tmp/o" 2>&1
[ ! -e doc/README.md ] && ok "readmeStub disabled → generated README removed" || bad "generated README left behind"
write_config "[]" true
okf build-index >"$tmp/o" 2>&1

# --- 8c. an index under a NEWLY skipped dir is still found and removed -------
mkdir -p doc/oldstuff
printf '%s\n\n# oldstuff/\n' "$MARKER" > doc/oldstuff/index.md
cat > okf.config.json <<'EOF'
{
  "template": false, "okfVersion": "0.1", "docRoot": "doc", "skipDirs": ["oldstuff"],
  "reservedFiles": ["index.md", "log.md"], "conventionsFile": "okf-conventions.md",
  "bundleTitle": "Test Bundle",
  "readmeStub": { "enabled": true, "title": "Test Docs", "description": "Start at index.md." },
  "refExtensions": ["md", "json"], "assetExcludeExts": [".png"], "activeStatus": "active",
  "folders": { "guides": "How-tos.", "reference": "Lookup." },
  "rulesAndInvariants": []
}
EOF
okf build-index >"$tmp/o" 2>&1
[ ! -e doc/oldstuff/index.md ] && ok "orphan under newly skipped dir removed" || bad "skipped-dir orphan survived"
rmdir doc/oldstuff
write_config "[]"
okf build-index >"$tmp/o" 2>&1

# --- 8d. conventionsFile "" → no bogus empty link, gate still green ----------
cat > okf.config.json <<'EOF'
{
  "template": false, "okfVersion": "0.1", "docRoot": "doc", "skipDirs": [],
  "reservedFiles": ["index.md", "log.md"], "conventionsFile": "",
  "bundleTitle": "Test Bundle",
  "readmeStub": { "enabled": true, "title": "Test Docs", "description": "Start at index.md." },
  "refExtensions": ["md", "json"], "assetExcludeExts": [".png"], "activeStatus": "active",
  "folders": { "guides": "How-tos.", "reference": "Lookup." },
  "rulesAndInvariants": []
}
EOF
okf build-index >"$tmp/o" 2>&1
if grep -q '\[\](\./)'  doc/index.md; then bad "empty conventions link emitted"; else ok "conventionsFile \"\" → no bogus link"; fi
okf check >"$tmp/o" 2>&1 && ok "conventionsFile \"\" → full gate green" || bad "no-conventions mode red: $(tail -2 "$tmp/o" | tr '\n' ' ')"
sed 's|"conventionsFile": ""|"conventionsFile": null|' okf.config.json > "$tmp/c.json" && cp "$tmp/c.json" okf.config.json
okf check >"$tmp/o" 2>&1 && ok "conventionsFile null means the same" || bad "conventionsFile null red: $(tail -2 "$tmp/o" | tr '\n' ' ')"
write_config "[]"
okf build-index >"$tmp/o" 2>&1

# --- 9. pinned rules: path works; missing and ambiguous fail -----------------
write_config '["guides/how-to.md"]'
okf build-index >"$tmp/o" 2>&1 \
  && grep -q "Rules & Invariants" doc/index.md && grep -q "guides/how-to.md" doc/index.md \
  && ok "path-pinned rule lands in the root index" || bad "path pin failed: $(tail -2 "$tmp/o" | tr '\n' ' ')"
write_config '["nope.md"]'
okf build-index >"$tmp/o" 2>&1
[ $? -ne 0 ] && grep -q "not found" "$tmp/o" && ok "missing pin → build fails" || bad "missing pin passed"
cat > doc/reference/how-to.md <<'EOF'
---
type: reference
title: "Other How To"
description: "Same basename, different folder."
---
# Other
EOF
write_config '["how-to.md"]'
okf build-index >"$tmp/o" 2>&1
[ $? -ne 0 ] && grep -q "ambiguous" "$tmp/o" && ok "ambiguous basename pin → build fails" || bad "ambiguous pin passed"
rm doc/reference/how-to.md
write_config '["../escape.md"]'
okf build-index >"$tmp/o" 2>&1
[ $? -ne 0 ] && grep -q "not a concept doc" "$tmp/o" && ok "traversal pin (../) → build fails" || bad "traversal pin escaped the bundle"
write_config '["guides/log.md"]'
printf 'free-form\n' > doc/guides/log.md
okf build-index >"$tmp/o" 2>&1
[ $? -ne 0 ] && grep -q "not a concept doc" "$tmp/o" && ok "reserved-file pin → build fails" || bad "reserved-file pin accepted"
rm doc/guides/log.md
write_config "[]"
okf build-index >"$tmp/o" 2>&1 || bad "cleanup rebuild failed"

# --- 9b. root-index domain order follows the config, not the alphabet --------
cat > okf.config.json <<'EOF'
{
  "template": false, "okfVersion": "0.1", "docRoot": "doc", "skipDirs": [],
  "reservedFiles": ["index.md", "log.md"], "conventionsFile": "okf-conventions.md",
  "bundleTitle": "Test Bundle",
  "readmeStub": { "enabled": true, "title": "Test Docs", "description": "Start at index.md." },
  "refExtensions": ["md", "json"], "assetExcludeExts": [".png"], "activeStatus": "active",
  "folders": { "reference": "Lookup.", "guides": "How-tos." },
  "rulesAndInvariants": []
}
EOF
okf build-index >"$tmp/o" 2>&1
first=$(grep -oE '^- \[[a-z]+/' doc/index.md | head -1)
[ "$first" = "- [reference/" ] && ok "domain order follows config order" || bad "domain order ignored config (first: $first)"
write_config "[]"
okf build-index >"$tmp/o" 2>&1

# --- 10. pre-existing files are refused without --adopt ----------------------
printf '# Hand-written README\n' > doc/README.md
okf build-index >"$tmp/o" 2>&1
[ $? -ne 0 ] && grep -q "REFUSING" "$tmp/o" && ok "unmarked pre-existing file → build refuses" || bad "pre-existing file clobbered silently"
okf build-index --adopt >"$tmp/o" 2>&1 \
  && grep -q "generated-by" doc/README.md \
  && ok "--adopt takes ownership (marker present)" || bad "--adopt failed"

# --- 11. reserved files are exempt from frontmatter --------------------------
printf 'free-form log, no frontmatter\n' > doc/guides/log.md
okf validate >"$tmp/o" 2>&1 && ok "reserved log.md without frontmatter passes validate" || bad "reserved file flagged"
rm doc/guides/log.md

# --- 12. orchestrator is chain-safe ------------------------------------------
echo "no frontmatter" > doc/guides/bad.md
OKF_BIN="$ROOT/bin/okf" sh -c 'true && "$OKF_BIN" check' >"$tmp/o" 2>&1
[ $? -ne 0 ] && ok "okf check propagates failure through a && chain" || bad "chained okf check swallowed the failure"
rm doc/guides/bad.md
okf check >"$tmp/o" 2>&1 && ok "final state green" || bad "final state not green: $(tail -3 "$tmp/o" | tr '\n' ' ')"

# --- 13. the gates are also runnable without the wrapper (CI form) -----------
node "$ROOT/scripts/okf/check.mjs" >"$tmp/o" 2>&1 && ok "node <plugin>/scripts/okf/check.mjs runs the same gate" || bad "direct node invocation failed: $(tail -2 "$tmp/o" | tr '\n' ' ')"

echo "okf-gates: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
