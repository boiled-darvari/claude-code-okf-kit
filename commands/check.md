---
description: Run the OKF docs gate (frontmatter, links, prose references, index staleness) and fix what it reports.
argument-hint: "[fix]"
---

Run the OKF gate for this repository, from the repository root:

```bash
okf check
```

Arguments: $ARGUMENTS

- If there is no `okf.config.json`, say the project has no OKF bundle set up
  and offer `/okf:init`. Do not create a config here.
- If the gate is green, report its last line and stop.
- If it fails, report which gate failed and its findings, then fix them — or,
  when the argument is not `fix` and the fix is not obvious, ask first:
  - **frontmatter**: add the missing block or `type`; take the vocabulary from
    the bundle's conventions doc, never invent a type.
  - **broken links**: correct the target, or remove a link to a doc that is
    truly gone.
  - **stale prose references**: `okf check-refs --fix` repoints mentions whose
    file moved; it never rewrites inside URLs.
  - **stale index**: `okf build-index`, then commit the regenerated files.
    Use `--adopt` only after the user has seen the list of pre-existing files
    it would replace.
- Run `okf check` again and report the final line. Never report a green gate
  you did not see.
