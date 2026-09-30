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

All three previous local integration patches have been upstreamed in `v0.1.1` and removed:

- Line boundary preservation following replaced managed blocks and final newline preservation at EOF (`replace_generated_block`).
- Unchanged skill-route block no-op handling (`sync_skill_routes`).
- Removal of non-repository-stable checkout-directory basename (`Root:` line) from `core.md` and `skill-health.md`.

Re-verified against `v0.1.1` on 2026-08-06: payload matches upstream `v0.1.1` cleanly with zero local patches.

## Known validation warnings

The pinned upstream payload is valid but currently reports these non-blocking SkillOps warnings:

- `missing-evals`: upstream does not ship `evals/evals.json`.
- `script-without-compatibility`: upstream frontmatter does not declare its Python compatibility field.
- `codex-metadata-unparsed`: SkillOps records the Codex adapter but does not parse its schema.

Keep these as upstream facts rather than patching the vendored `SKILL.md` locally. Re-evaluate them when updating the pinned commit. Re-confirmed unchanged with `v0.1.1` on 2026-08-06; the `v0.1.0` listing-budget checks (`long-listing-entry`, `listing-budget-estimate`) report nothing for this repository.
