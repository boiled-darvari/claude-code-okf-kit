# okf

Open Knowledge Format (OKF) docs bundles for a repository, as a Claude Code
plugin: every doc carries frontmatter, the indexes are generated, and a gate
keeps the bundle honest every time the docs change.

In an OKF bundle each concept doc lives in a domain folder and starts with
YAML frontmatter. The `index.md` files and the bundle `README.md` are
generated from that frontmatter, never written by hand. A four-part gate
checks frontmatter, links, prose references and index staleness.

## What you get

| Piece | What it does |
|---|---|
| `/okf:init` | Sets up a bundle in the repository: manifest, conventions doc, first index build |
| `/okf:check` | Runs the gate and fixes what it reports |
| `okf:doc-scribe` agent | Writes and updates docs to your conventions and leaves the gate green |
| Stop hook | Runs the gate before a turn ends, when the turn changed the docs or the manifest |
| `okf` command | The gates as a command line tool, on Claude's PATH through the plugin |
| GitHub Action | Runs the same gate in CI |

The hook does nothing in a repository that has no `okf.config.json`, so
installing the plugin does not affect your other projects.

## Install

At the prompt of a terminal session:

```
/plugin install okf --marketplace boiled-darvari/claude-code-okf-kit
```

From a shell:

```
claude plugin install okf --marketplace boiled-darvari/claude-code-okf-kit
```

In the desktop app, where `/plugin` does not run: click + next to the prompt
box, then Plugins, Add marketplace with `boiled-darvari/claude-code-okf-kit`,
then Add plugin.

## Set up a project

Run `/okf:init` in the repository. It creates two files with you, builds the
first indexes and runs the gate:

| File | What it holds |
|---|---|
| `okf.config.json` | The manifest: where the docs live, the domain folders, pinned rules |
| `<docRoot>/okf-conventions.md` | The house conventions: frontmatter fields and the `type` vocabulary |

Commit both, together with the generated `index.md` files.

## The gate

`okf check` runs four checks in order and stops at the first that fails:

| Check | Passes when |
|---|---|
| `okf validate` | Every concept doc has frontmatter with a non-empty `type` |
| `okf check-links` | Every relative markdown link inside the bundle resolves to a file |
| `okf check-refs` | Every prose mention of a bundle path points at the file's real path |
| `okf build-index --check` | The generated indexes match the tree |

`okf build-index` regenerates the indexes. `okf check-refs --fix` repoints
prose mentions whose file moved, and never rewrites inside URLs.

`okf build-index` refuses to overwrite an `index.md` or `README.md` it did not
generate. `--adopt` takes ownership of them, replacing their content with
generated listings, so run it only after you have looked at the list.

## The manifest

`okf.config.json` sits at the repository root. Only `template` is required.

| Field | Meaning | Default |
|---|---|---|
| `template` | Must be `false`. Every gate refuses to run until it is | — |
| `docRoot` | The bundle's folder, relative to the repository root | `doc` |
| `folders` | Domain folder → one-line description; the order is the root index order | `{}` |
| `rulesAndInvariants` | Docs pinned at the top of the root index; a missing one fails the build | `[]` |
| `bundleTitle` | Heading of the root index | `Project Knowledge Bundle (OKF)` |
| `readmeStub` | `enabled`, `title`, `description` of the generated `README.md` | enabled |
| `conventionsFile` | The conventions doc at the bundle root; `""` for none | `okf-conventions.md` |
| `skipDirs` | Folder names the gates skip entirely | `[]` |
| `reservedFiles` | Files that carry no frontmatter | `index.md`, `log.md` |
| `refExtensions` | Extensions the prose-reference check treats as bundle files | `md`, `json`, `html` |
| `assetExcludeExts` | Asset extensions left out of basename resolution | common image types |
| `activeStatus` | The frontmatter `status` that means current | `active` |
| `onMissingNode` | What the Stop hook does without Node: `block` or `warn` | `block` |

The file is data: it is parsed as JSON and never executed. A misspelled key is
reported and ignored; keys starting with `_` are yours to use as notes.
`OKF_CONFIG=<path>` points the gates at another manifest.

## CI

The hook is a convenience; CI is the authority. On GitHub:

```yaml
jobs:
  docs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: boiled-darvari/claude-code-okf-kit@main
```

The action takes two optional inputs: `working-directory` (where the manifest
is) and `config` (the manifest's path). Pin it to a commit instead of `main`
if you want the gate's version fixed.

On any other CI, fetch the repository and run the gate with Node:

```bash
git clone --depth 1 https://github.com/boiled-darvari/claude-code-okf-kit /tmp/okf
node /tmp/okf/scripts/okf/check.mjs
```

## Node

The gates are Node scripts and need Node 18 or newer. They use no npm
packages.

If a turn changes the docs on a machine without Node, the Stop hook blocks
once with a message saying the bundle is not validated. A project that prefers
not to block sets `"onMissingNode": "warn"` in its manifest: the hook then
skips with a visible notice, and CI enforces the gate. The setting changes
nothing when Node is present.

## Without Claude Code

The gates do not depend on Claude Code. Clone the repository and run
`bin/okf check` from your project's root, or call it from a git pre-commit
hook.

## Honesty notes

- The Stop hook's trigger is an approximation: the bundle or the manifest is
  dirty at stop time, or was touched by the latest commit. That is not
  literally "changed this turn": a bundle someone else left dirty fires it
  too. That is by design, since the bundle is nonconformant either way, but it
  can surprise.
- The link check validates that the target file exists. `#anchor` fragments
  are not checked against headings, because slug rules differ between
  renderers.
- The prose-reference check treats a mention whose basename exists nowhere in
  the bundle as a planned or external doc and ignores it. It verifies that
  resolvable mentions point at the right path, not that every mention resolves.
- The generator owns only the files that carry its marker. Everything else
  needs an explicit `--adopt`.
- Without `jq`, the hook reads the manifest with a text heuristic that expects
  `"docRoot"` and its value to be an ordinary `"key": "value"` pair.

## Tests

```
bash tests/run-all.sh
```

The suite runs the gates and the hook against scratch projects. It pins the
refusals (missing, template, malformed or unsafe manifest), every violation
class, the URL-safe `--fix`, pin resolution, the `--adopt` refusal, the hook's
trigger and its behavior without `jq`, `node` or `git`. It needs `git` and
Node.

## Not included

Patterns worth adding to a project that this plugin does not ship:

- **Generated reference docs**: one doc per table, collection or endpoint,
  generated from your schema definitions and run before `okf build-index`.
- **A rendered site**: the bundle is plain markdown; rendering it is yours.
- **A client-contract changelog**: a dated, newest-on-top changelog for API
  consumers, updated in the same commit as any contract change. It is a
  convention plus one file and needs no tooling.
