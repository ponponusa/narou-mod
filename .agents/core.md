# Core Agent Context

This file is the source of truth for repository-wide policy. Keep provider-specific behavior in `.agents/profiles/` and path-specific instructions in routed files.

<!-- agent-context-maintainer:begin -->
## Repository Snapshot

- Detected languages: Ruby, Markdown, TypeScript, JavaScript, Python
- Approximate tracked context files scanned: 572

## Detected Manifests

- `Gemfile`
- `frontend/package.json`

## Detected Documentation

- `AGENTS.md`
- `CLAUDE.md`
- `GEMINI.md`
- `README.md`
- `.github/copilot-instructions.md`
- `docs/development.md`
- `docs/openapi.yaml`
- `frontend/AGENTS.md`
- `frontend/CLAUDE.md`
- `frontend/GEMINI.md`
- `frontend/README.md`
- `scripts/README_dummy_data.md`
- `spec/fixtures/.test_dot_narou/README.md`
- `spec/performance/README.md`

## Context Boundaries

- Keep shared rules in this file.
- Keep provider-specific behavior in `.agents/profiles/`.
- Keep task-specific procedures in `.agents/skills/*/SKILL.md`.
- Do not copy secrets, credentials, raw logs, private keys, or `.env*` values into context files.

## Editing Rules

- Preserve unrelated user changes.
- Prefer small patches that follow existing repository style.
- Update public-facing docs when private planning changes affect public behavior.

## Validation

- Prefer focused validation for the changed slice.
- Record exact commands run and any failures that appear unrelated.

## Handoff Notes

- Leave durable restart notes when work spans multiple sessions.
- Point future agents to the most current implementation or planning checkpoint.
<!-- agent-context-maintainer:end -->
## Repository Purpose and Architecture

`narou-mod` is a Ruby gem and CLI for downloading, maintaining, and converting Japanese web novels. It also ships a Sinatra server and an Astro/Svelte frontend that is built into the gem.

- Runtime baseline: Ruby 3.4 or newer; Bundler 2.7.2 in CI.
- Backend: Sinatra 4, Rack 3, Puma, ActiveSupport 8, Nokogiri, rubyzip, Haml/Tilt, and sass-embedded.
- Frontend: Astro 7, Svelte 5, Tailwind CSS 4, and strict TypeScript; CI uses Node.js 24 and npm.
- Ruby entry points: `narou.rb` for the checkout and `bin/narou-mod` for the packaged executable.
- Domain and CLI code: `lib/core/`, `lib/narou/`, `lib/novel/`, `lib/conversion/`, `lib/ebook/`, `lib/output/`, and `lib/cli/`.
- Web server: `lib/web/appserver.rb`, with API v1 and v2 under `lib/web/api/` and legacy Haml/static UI under `lib/web/views/` and `lib/web/public/`.
- Modern UI: `frontend/`; its path-local rules live in `frontend/AGENTS.md`.
- Tests: RSpec under `spec/`; Playwright flows under `frontend/e2e/`.

Exact dependency versions belong to `Gemfile.lock` and `frontend/package-lock.json`. Do not copy version guesses into implementation decisions when the locks are cheap to inspect.

## Common Backend Commands

Run these from the repository root:

- `bundle install`: install Ruby dependencies.
- `bundle exec ruby narou.rb web`: start the Web UI/API from the checkout.
- `bundle exec ruby narou.rb download <novel_id>`: exercise a download/conversion path.
- `bundle exec rspec [spec/path_spec.rb]`: run all or focused RSpec tests.
- `bundle exec rake`: run the default RSpec task.
- `bundle exec rubocop` and `bundle exec reek`: run Ruby static analysis.
- `./scripts/process_control.sh --restart` on Unix or `.\scripts\process_control.ps1 -Restart` on Windows: restart the integrated local processes when that side effect is intended.

## Repository-Specific Boundaries

- Always read `AGENTS.md`, this file, `.agents/routing.md`, and the matching provider profile before editing.
- Follow `frontend/AGENTS.md` for every change under `frontend/`.
- Treat `README.md`, `CHANGELOG.md`, `docs/openapi.yaml`, and `docs/development.md` as publishable product documentation, not substitutes for current code verification. Other project Markdown documents remain unreviewed under `docs/_tmp/` until explicitly promoted.
- Do not read or summarize `.env*`, credentials, private keys, local databases, raw logs, dependency caches, coverage output, or build output unless the user explicitly places them in scope.
- Do not edit generated artifacts such as `frontend/dist/`, coverage reports, built `.gem` files, `commitversion`, or runtime-generated `frontend/public/backend-port.json` as source files.

## Documentation Lifecycle

- Keep only reviewed, publishable documentation in the parent repository's tracked `docs/` tree. At present, `docs/openapi.yaml` and `docs/development.md` are the reviewed documents there.
- Use `docs/_tmp/` for local-only investigations, implementation plans, design drafts, decision notes, performance reports, and handoff material that should not be published with the project.
- Treat every Markdown document currently under `docs/_tmp/` as unverified until its claims have been checked against current code, manifests, tests, and runtime behavior.
- Treat `docs/_tmp/` as an independent local Git repository ignored by the parent repository. Do not add a remote, push it, or publish its contents unless the user explicitly requests that action.
- Private placement is not a substitute for secret storage. Never put credentials, tokens, private keys, personal data, downloaded novel content, or raw sensitive logs in `docs/_tmp/`.
- Consult `docs/_tmp/` only when the task needs the relevant local research or plan. Do not copy its contents into public artifacts wholesale.
- Promote a document back to tracked `docs/` only after review. When local findings change an accepted public contract or current behavior, update the relevant tracked documentation, tests, changelog, or agent context in the same implementation change.

## Repository Editing Rules

- Preserve unrelated user changes. Inspect `git status --short` and the relevant diff before editing or staging.
- Keep changes scoped. Broad refactors require a concrete need and explicit agreement.
- Preserve the public CLI, REST API, configuration formats, novel data, and converter output unless the task explicitly changes their contract.
- New Ruby files start with `# frozen_string_literal: true`. Use 2-space indentation, `snake_case` files/methods, `Narou::CamelCase` namespaces, and single-quoted strings when interpolation or escapes are not needed. Follow nearby style when legacy files differ.
- Haml and SCSS changes follow `.haml-lint.yml` and `.scss-lint.yml` in addition to nearby legacy view conventions.
- Keep network and filesystem side effects out of ordinary tests; use existing helpers and fixtures under `spec/support/`, `spec/fixtures/`, and `spec/data/`.
- Changes to supported-site definitions must inspect `webnovel/`, `preset/parsers/`, relevant `preset/parsers/legacy_archive/` entries, and parser/downloader specs. Keep active and legacy definitions synchronized where both serve the same site contract.
- Do not disturb the load-path and RubyGems conflict handling in `narou.rb` or the YJIT/Bootsnap/bootstrap ordering in `bin/narou-mod` without entry-point-specific regression coverage.
- Update `CHANGELOG.md` for user-visible behavior, compatibility changes, release-impacting dependency changes, or fixes users need to know about.

## Security and Secrets

- Never commit secrets or local environment files. Keep examples synthetic and use existing example files for documented configuration.
- Treat downloaded HTML and metadata as untrusted input. Preserve sanitization, encoding handling, Cloudflare/challenge detection, and public error boundaries.
- Avoid live downloads in routine tests. Use fixtures first; perform narrow live verification only when current site behavior is part of the task.
- Do not expose provider bodies, tokens, private URLs, raw logs, or user novel content in agent context, issues, test fixtures, or public error messages.

## Repository Validation Matrix

Choose the smallest validation set that proves the changed behavior, then expand when risk warrants it.

| Changed area | Minimum validation |
| --- | --- |
| Ruby implementation | Focused `bundle exec rspec <spec-path>`; run `bundle exec rspec` for cross-cutting changes |
| Ruby style/quality | `bundle exec rubocop <changed-ruby-files>` and focused Reek where practical; report pre-existing whole-repo debt separately |
| CLI/bootstrap | Relevant CLI specs plus a representative `bundle exec ruby narou.rb <command>` smoke test |
| Sinatra/API | Relevant `spec/web/*` specs and API documentation/contract review |
| Site parser/definition | Parser/downloader specs, fixture variants, and active/legacy definition parity |
| Frontend | Follow `frontend/AGENTS.md`; normally `npm run format:check`, `npm run check`, and `npm run build` |
| UI flow | Relevant Playwright test and visual/browser verification when behavior or layout changes |
| Agent context | Project-scoped `agent_context.py check`, `skills check`, sync/routes idempotency, and `git diff --check` |

CI's PR path installs frontend dependencies, builds/checks Astro, validates built HTML, runs Playwright smoke/integration tests, and runs RSpec. Local validation should match that sequence for changes crossing backend/frontend boundaries.

## Git, Branches, and Releases

- Use Git author and committer `ponpon.USA <init0531.usa@gmail.com>`; do not introduce another identity.
- Use imperative commit subjects and reference related issues as `#123` when applicable.
- Normal feature/fix work targets `develop`. Release promotion is `develop` to `release`; `draft` is used for staging validation.
- Pushes to `release` or `draft` build platform gems and can create/update GitHub Releases. Do not push or merge to those branches without an explicit release request.
- Release tags append the `commitversion` commit suffix to the gem version (for example `3.1.6-<commit>`), while gem asset filenames use the plain gem version and the Linux/macOS gem has no platform suffix (`narou-mod-<version>.gem` vs `narou-mod-<version>-x64-mingw-ucrt.gem`). Verify the computed version and both artifacts during release work.
- Stage explicit paths in a mixed worktree and leave unrelated local artifacts out of commits.

## Repository Handoff Requirements

- Report changed files, exact validation commands, failures, skipped checks, and residual risk.
- For work spanning sessions, leave a durable repository-local plan or status note at the path agreed with the user.
- When current code contradicts documentation or this context, verify the behavior, update the stale context in the same change when in scope, and call out the reconciliation.
