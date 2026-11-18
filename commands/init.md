---
description: Set up an OKF docs bundle in this repository — create okf.config.json and the conventions doc from the plugin's templates (never overwriting), build the first indexes and run the gate.
---

Set up the OKF docs bundle in this repository. Work from the repository root.

1. **Manifest.** If `okf.config.json` already exists, read it and keep it:
   never overwrite it. Otherwise copy
   `${CLAUDE_PLUGIN_ROOT}/templates/okf.config.json` to `okf.config.json`,
   then fill it in with the user:
   - `docRoot` — the docs folder (default `doc`). If the repository already
     keeps its docs somewhere, use that folder.
   - `folders` — the domain folders, each with a one-line description. Propose
     them from what is already under the docs folder; the order here is the
     order in the root index.
   - `bundleTitle` and `readmeStub` — set `readmeStub.enabled` to `false` if
     the project already owns `<docRoot>/README.md` and wants to keep it.
   - `rulesAndInvariants` — docs to pin at the top of the root index; leave
     empty if there are none yet.
   - Set `"template": false` last. Every gate refuses to run until it is
     explicitly false.

2. **Conventions.** If `<docRoot>/okf-conventions.md` does not exist, create
   the docs folder if needed and copy
   `${CLAUDE_PLUGIN_ROOT}/templates/okf-conventions.md` there. Go through its
   `EDIT-ME` sections with the user (the `type` vocabulary above all). A
   project that wants no conventions doc sets `"conventionsFile": ""`.

3. **Existing docs.** Every `.md` under the docs folder needs YAML
   frontmatter with a non-empty `type`. If there are docs without it, list
   them and offer to add frontmatter; do not guess a `type` silently.

4. **First build.** Run `okf build-index`. If it refuses because `index.md`
   or `README.md` files already exist that it did not generate, show the user
   the list and ask before running `okf build-index --adopt`: adopting
   replaces their content with generated listings.

5. **Gate.** Run `okf check` and fix what it reports until it is green.

6. **Report.** Say what was created, what the user still has to decide, and
   the gate's final line. Then tell the user:
   - The generated `index.md` files, `okf.config.json` and the conventions doc
     are part of the tree: commit them.
   - From now on the plugin's Stop hook runs the gate whenever a turn changes
     the docs folder or the manifest.
   - The hook is a convenience and CI is the authority: offer to add the CI
     step (the plugin's README has a GitHub Action snippet and a generic one).
   - The gates need node >= 18. If `node` is not on PATH here, say so, and
     explain the choice: install node, or set `"onMissingNode": "warn"` so the
     hook skips with a visible notice and CI enforces the gate.
