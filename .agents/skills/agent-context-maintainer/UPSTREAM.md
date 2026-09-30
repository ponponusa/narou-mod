# Upstream provenance

- Repository: https://github.com/ponponusa/agent-context-maintainer
- Imported commit: `25354c94db194f9c09bfaa3108542e9674325c7b` (tag `v0.1.1`)
- Imported on: 2026-08-06
- License: MIT; see `LICENSE` in this directory.

## Imported payload

This project-scoped installation contains the runtime and the documents referenced by `SKILL.md`:

- `SKILL.md` and `SKILL.ja.md`
- `agents/openai.yaml`
- `scripts/agent_context.py`
- `references/*.md`
- `reports/provider-review-2026-07.md` and `reports/provider-review-2026-08.md`
- `LICENSE`

Upstream examples, tests, workflows, and development-only files are intentionally omitted so they do not appear as `narou-mod` documentation or tests during repository inventory.

## Update procedure

1. Resolve and review a specific upstream commit; do not vendor a moving branch.
2. Compare every imported path with that commit and review upstream `CHANGELOG.md`.
3. Update the payload and this file in the same change.
4. Run `python3 scripts/agent_context.py check <repo-root>` and the SkillOps checks documented in `SKILL.md`.
5. Confirm a second scaffold/sync run is idempotent before committing.

English upstream documentation is authoritative; Japanese companion files follow it.

## Local integration patch

Status: one active local patch on top of `v0.1.1` (added 2026-09-30). It is not yet upstream; propose it to https://github.com/ponponusa/agent-context-maintainer and drop it here once a pinned upstream release contains an equivalent fix.

### Active: test detection and the `Detected Tests` routing section (`scripts/agent_context.py`)

Upstream `v0.1.1` treated any file with a `test`/`tests` path component, a `test_` name prefix, or a `_test.go` suffix as a test. In this repository that listed conversion fixture texts (`spec/data/convert_test/*/test_*.txt`) and a jQuery demo page (`lib/web/public/test/*.html`) while missing every `spec/**/*_spec.rb` and `frontend/e2e/*.spec.ts`. The patch:

- Adds `test_pattern()`: only files with a known code suffix (`TEST_CODE_SUFFIXES`) qualify; conventional names are recognized across ecosystems (`*_spec.*`, `*_test.*`, `*.spec.*`, `*.test.*`, `test_*.*`, and `*Test`/`*Tests`/`*Spec` for JVM, .NET (C#, F#), Swift, and PHP suffixes); other code files count only under a `TEST_DIR_NAMES` directory (`test`, `tests`, `spec`, `specs`, `__tests__`, `e2e`).
- Excludes any path inside `TEST_DATA_DIR_NAMES` (`fixtures`, `fixture`, `__fixtures__`, `testdata`, `test_data`, `snapshots`, `__snapshots__`, `node_modules`, `vendor`), because those trees hold test inputs rather than tests.
- Treats `data` and `public` (`TEST_DATA_DIR_NAMES_SOFT`) as exclusions only when they sit directly inside a `TEST_DIR_NAMES` directory (`spec/data/x_spec.rb`) or the file lacks a conventional test name (`lib/web/public/test/helper.js`). Conventionally named tests in ordinary application packages such as `src/data/foo.test.ts`, `internal/data/store_test.go`, or `src/test/java/com/x/data/FooTest.java` are still detected.
- Adds `test_root()`, `test_locations()`, and `test_location_list()`: `routing.md` now renders one bullet per test root (nearest test-named ancestor, else the parent directory) with per-convention counts, sorted by path and capped at `MAX_TEST_LOCATIONS` with an explicit `... and N more locations (M files)` line. The empty-state message is unchanged.
- `inventory` keeps its `tests` file list (still capped at 30, now using the corrected detection) and adds `test_count` and `test_locations`; the text output prints `... and N more` when the file list is truncated and adds a `test_locations:` section listing each test root with its file count (`  - <path>: <count>`, uncapped).

After updating the pinned upstream commit, re-apply or drop this patch, then re-run scaffold and confirm the `Detected Tests` block still lists `spec/` and `frontend/e2e/` only.

### Previously upstreamed

The three earlier local integration patches were upstreamed in `v0.1.1` and removed:

- Line boundary preservation following replaced managed blocks and final newline preservation at EOF (`replace_generated_block`).
- Unchanged skill-route block no-op handling (`sync_skill_routes`).
- Removal of non-repository-stable checkout-directory basename (`Root:` line) from `core.md` and `skill-health.md`.

Verified against `v0.1.1` on 2026-08-06 with zero local patches; `scripts/agent_context.py` now differs from `v0.1.1` only by the active patch above.

## Known validation warnings

The pinned upstream payload is valid but currently reports these non-blocking SkillOps warnings:

- `missing-evals`: upstream does not ship `evals/evals.json`.
- `script-without-compatibility`: upstream frontmatter does not declare its Python compatibility field.
- `codex-metadata-unparsed`: SkillOps records the Codex adapter but does not parse its schema.

Keep these as upstream facts rather than patching the vendored `SKILL.md` locally. Re-evaluate them when updating the pinned commit. Re-confirmed unchanged with `v0.1.1` on 2026-08-06; the `v0.1.0` listing-budget checks (`long-listing-entry`, `listing-budget-estimate`) report nothing for this repository.
