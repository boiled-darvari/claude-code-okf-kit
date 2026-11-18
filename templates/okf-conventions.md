---
type: reference
title: "OKF Conventions"
description: "House profile for this docs bundle: frontmatter fields, type vocabulary, naming, archive policy."
status: active
tags: [docs, conventions]
---

# OKF Conventions

<!-- This file lives at <docRoot>/okf-conventions.md (the name configured as
     conventionsFile in okf.config.json). EDIT-ME every section marked so.
     This starter ships a neutral example vocabulary — replace it with yours;
     the gate enforces only that `type` is non-empty, the vocabulary is house
     discipline. -->

This folder is an **Open Knowledge Format (OKF)** bundle. Every concept doc
lives under a domain folder and carries YAML frontmatter. Indexes
(`index.md` files and `README.md`) are **generated** by `okf build-index` —
never edit them by hand; regenerate and commit them.

## Frontmatter

```yaml
---
type: rule                 # REQUIRED — vocabulary below
title: "Human title"
description: "One-sentence summary; shown in generated index listings."
status: active             # active | deferred | archived | superseded
tags: [domain, topic]
timestamp: 2026-01-01T00:00:00Z
---
```

## `type` vocabulary (EDIT-ME)

Neutral starter set — adjust to your project's needs and keep this list
authoritative:

- `rule` — a binding invariant; read before touching the code path it names.
- `guide` — how-to material.
- `reference` — lookup material, external contracts.
- `runbook` — operational procedure.
- `spec` — feature/API specification.
- `adr` — architecture decision record.
- `audit` — findings of a review, with dates.

## Naming & structure

- Name files by **topic** (`retry-policy.md`), never by team or channel
  prefix — audience belongs in frontmatter if you need it (EDIT-ME: add an
  `audience` field and its values here if so).
- One H1 at the top of the body; structural markdown below.
- New domain folder ⇒ add its one-line description to `folders` in
  `okf.config.json` in the same change.

## Lifecycle

- Retiring a doc → move it to the archive folder with `status: archived`.
  Never delete — history is part of the bundle.
- Binding rules worth pinning at the top of the root index go into
  `rulesAndInvariants` in the config (docRoot-relative paths preferred).

## The gate

```bash
okf build-index   # after adding/moving/retitling docs
okf check         # the full gate — CI should run this too
```
