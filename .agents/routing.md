# Agent Routing

Use this file to choose only the additional context needed for the current task.

<!-- agent-context-maintainer:begin -->
## Universal First Reads

- `AGENTS.md`
- `.agents/core.md`
- Matching provider profile in `.agents/profiles/`

## Task Routes

- Code review: inspect changed files first, then relevant tests and docs.
- Implementation: inspect manifests, existing patterns, and nearest tests before editing.
- Documentation: reconcile private planning docs with public docs when both exist.
- Security or privacy: read security guidance before changing storage, logging, sync, or agent-context behavior.
- Changing or adding custom subagent definitions: read the provider's native agents directory listed in your profile.
- New repeated workflow: create or update `.agents/skills/<task>/SKILL.md`.

## Detected Tests

- `frontend/e2e/` — 5 files: 3 `*.spec.ts`, 2 other `*.ts`
- `spec/` — 67 files: 59 `*_spec.rb`, 1 `*_test.rb`, 7 other `*.rb`

## Missing Context Rule

If required context is absent, state the gap clearly, make the safest local assumption, and avoid broad rewrites.
<!-- agent-context-maintainer:end -->
## Repository Task Routes

RSpec examples live in `spec/**/*_spec.rb`; `spec/generator/` and `spec/performance/` hold scripts, not examples. Playwright specs are `frontend/e2e/*.spec.ts`.

### Ruby core, CLI, download, and conversion

- Read the nearest implementation under `lib/` and its matching specs under `spec/`.
- CLI commands follow the patterns in `lib/cli/command/`; bootstrap work must also inspect `narou.rb`, `bin/narou-mod`, and `lib/loading/`.
- Novel download/conversion work usually spans `lib/narou/`, `lib/novel/`, `lib/conversion/`, `lib/ebook/`, and the matching fixture-backed specs.
- Converter behavior changes need a golden-file case under `spec/data/convert_test/` and a regenerated `spec/novel/convert_spec.rb` (see `.agents/core.md`).

### Supported sites and parsers

- Decide which layer the bug lives in before editing (see the site-definition rules in `.agents/core.md`): URL, TOC, and metadata issues belong in `webnovel/<domain>.yaml`; section-body issues on the three preset domains belong in `preset/parsers/<domain>.yaml` or `lib/narou/parsers/`.
- When changing parser architecture, consult `docs/_tmp/html_parser_analysis.md` if the local documentation repository contains it; do not require that private plan for a narrow selector or fixture fix.
- Validate network-dependent behavior with fixtures first and keep adult/non-adult or legacy variants aligned when they share behavior.

### Sinatra Web UI and REST API

- Read `lib/web/appserver.rb` and the relevant modules under `lib/web/api/`, `lib/web/routes/`, `lib/web/helpers/`, `lib/web/workers/`, or `lib/web/server/`.
- `lib/web/api/v1/` implements the legacy unversioned `/api/*` endpoints, which `docs/openapi.yaml` does not cover; `lib/web/api/v2/` implements `/api/v2/*`, the documented surface.
- `docs/openapi.yaml` documents every `/api/v2` method and path with the `{success, data | error, timestamp}` envelope built in `v2/base.rb`. When they disagree, the v2 code is the source of truth; update the OpenAPI entries for the routes you change in the same change.
- API contract changes require `docs/openapi.yaml` and relevant `spec/web/` coverage. If present, `docs/_tmp/web_api_endpoints.md` is an unverified historical aid, not a contract source.
- Legacy Haml/static UI changes use `lib/web/views/` and `lib/web/public/`; do not apply frontend conventions there.

### Astro/Svelte frontend

- Read `frontend/AGENTS.md` before any file under `frontend/`; it owns the frontend stack, commands, and rules.
- An API contract change crosses both sides in the same change: the Ruby module, `spec/web/`, and `docs/openapi.yaml`, plus `frontend/src/lib/api.ts` and `frontend/src/types/api.ts`. When a page calls the endpoint on load, also give it a realistic response in `apiResponse()` in `frontend/e2e/support/network.ts`; unknown paths there return an empty `data` object. This applies whichever side you started from.
- A new Astro page also needs its Sinatra route in `lib/web/routes/static_file.rb` and an entry in the `frontend/e2e/smoke.spec.ts` routes table.

### Process management and local development

- Read `scripts/process_control.sh` and `scripts/process_control.ps1` as applicable to the host platform. Local documents such as `docs/_tmp/process_management.md` and `docs/_tmp/development_environment_setup.md` are unverified aids only.
- Treat port files, PID files, and logs as runtime output, not source.

### CI, dependency, and release work

- Read `.github/workflows/ci.yml`, both lockfiles, `narou-mod.gemspec`, `lib/core/version.rb`, and `CHANGELOG.md` as applicable.
- Separate local sandbox/tooling failures from regressions, and confirm remote CI before release promotion.
- For publishing, verify branch, worktree, remote, computed version/tag, and uploaded platform artifacts.

### Documentation

- Follow the Documentation Lifecycle in `.agents/core.md`, verify documentation claims against current code and manifests, and record new `docs/_tmp/` documents in `docs/_tmp/documentation-review-index.md`.
- Keep `README.md` focused on the project introduction and end-user usage; developer setup, build, and workflow documentation belongs in `docs/development.md` and must stay aligned with CI and the scripts it describes.
- Keep `docs/openapi.yaml` synchronized with the implemented API for the routes you change.

### Agent context

- Read `.agents/skills/agent-context-maintainer/SKILL.md` before changing `AGENTS.md`, provider bridges, `.agents/core.md`, `.agents/routing.md`, profiles, or project skills.
- `.claude/` is tracked except `.claude/settings.local.json` and `.claude/worktrees/`, so shared Claude Code settings, rules, skills, and subagents can live there; keep repository policy in `.agents/` and import it rather than copying it.
- Claude Code reads nothing under `.agents/` on its own. Root `CLAUDE.md` imports `core.md`, `routing.md`, and the Claude profile with hand-written `@` lines outside the managed block, and `frontend/CLAUDE.md` imports `frontend/AGENTS.md`. Keep those imports when renaming or splitting these files.
- Keep hand-written repository policy outside managed markers and let the project-scoped script own generated blocks.
- Update `.agents/skills/agent-context-maintainer/UPSTREAM.md` whenever the vendored upstream commit or payload changes.

## Provider Profile Selection

- Codex/OpenAI: `.agents/profiles/codex.md`
- Claude Code: `.agents/profiles/claude.md`
- Gemini CLI: `.agents/profiles/gemini.md`
- Cursor/IDE agents: `.agents/profiles/cursor.md`
- GitHub Copilot: `.agents/profiles/copilot.md`
- Antigravity: `.agents/profiles/antigravity.md`
- Unknown runtime: `.agents/profiles/generic.md`

## Missing Context Rule

If a referenced path is absent or code contradicts context, verify the nearest source and manifest, state the discrepancy, and avoid inventing policy. Update stale context when that reconciliation is part of the task.


## Skill Routes

<!-- agent-context-maintainer:skills-begin -->
- Agent context maintenance: read `.agents/skills/agent-context-maintainer/SKILL.md`.
<!-- agent-context-maintainer:skills-end -->
