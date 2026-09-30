# Core Agent Context

This file is the source of truth for repository-wide policy. Keep provider-specific behavior in `.agents/profiles/` and path-specific instructions in routed files.

<!-- agent-context-maintainer:begin -->
## Repository Snapshot

- Detected languages: Ruby, Markdown, TypeScript, JavaScript, Python
- Approximate tracked context files scanned: 571

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

- Runtime baseline: Ruby 3.4 or newer (`required_ruby_version` in `narou-mod.gemspec`). `Gemfile.lock` pins Bundler 2.7.2, as CI does, and newer Bundlers switch to that version automatically; if `bundle` fails while loading bundler 2.7.2, report it instead of skipping validation silently. There is no `.ruby-version`, so a local Ruby may be newer than 3.4; keep code 3.4-compatible.
- Backend: Sinatra 4, Rack 3, Puma, ActiveSupport 8, Nokogiri, rubyzip, Haml 5 (pinned below 6 for the legacy views), Tilt, and sass-embedded.
- Frontend: Astro/Svelte under `frontend/`; its stack, commands, and rules live only in `frontend/AGENTS.md`.
- Ruby entry points: `narou.rb` for the checkout and `bin/narou-mod` for the packaged executable. `bin/narou-mod` runs `./narou.rb` whenever the current directory contains `narou.rb`, so an installed gem started from the repository root executes checkout code.
- Domain and CLI code: `lib/core/`, `lib/narou/`, `lib/novel/`, `lib/conversion/`, `lib/ebook/`, `lib/output/`, and `lib/cli/` (commands in `lib/cli/command/`). Shared support lives in `lib/extensions/`, `lib/mixin/`, and `lib/utilities/`; bootstrap and load guards in `lib/loading/`.
- Web server: `lib/web/appserver.rb` requires each v1/v2 route module and calls `Narou::ApiV{1,2}::<Name>.register(self)`, so a new route module needs both; `v2/base.rb` is mixed in with `include Narou::ApiV2::Base` instead. `lib/web/api/v1/` serves the legacy unversioned `/api/*` paths; `lib/web/api/v2/` serves `/api/v2/*` (follow `v2/novels.rb`; shared helpers in `v2/base.rb`). Sinatra helpers are in `lib/web/server/helpers.rb`, route groups in `lib/web/routes/` (`static_file.rb` serves the built frontend), and the legacy Haml views and static files in `lib/web/views/` and `lib/web/public/`. Only `/`, `/settings`, and `/style.css` switch to Haml in `narou.rb web --legacy` mode; the default mode serves `frontend/dist` there and returns 500 "Frontend not built" when it is missing. The widget, partial, notepad, and per-novel setting Haml routes and `lib/web/public/` are served in both modes, so edits there affect the default server too.
- Tests: RSpec under `spec/` (about 1,400 examples); Playwright flows under `frontend/e2e/`.

Exact dependency versions belong to `Gemfile.lock` and `frontend/package-lock.json`. Inspect the locks instead of relying on remembered framework defaults.

## Common Backend Commands

Run these from the repository root:

- `bundle install`: install Ruby dependencies.
- `bundle exec rspec spec/<dir>/<name>_spec.rb[:line]`: focused RSpec run; `bundle exec rspec` or `bundle exec rake` runs the whole suite.
- `bundle exec rubocop [files]`: the only bundled linter. A whole-repository run takes seconds, so compare offense counts before and after a change. CI does not run it. `reek`, `haml-lint`, and `scss-lint` are not in the bundle; run them only if they are installed globally, and say so when you skip them.
- `bundle exec ruby narou.rb web`: start the Web UI/API from the checkout. It runs in the foreground until Ctrl+C, so start it as a background command. It also starts the Astro dev server on 4321 unless `--no-frontend` is given, and opens a browser only with `--open-browser`. The REST port is `server-port` from the global settings (random on first run; `-p` overrides it), and each start rewrites `frontend/.env` and `frontend/public/backend-port.json`.
- `bundle exec ruby narou.rb download <novel_id>`: a live network download into the checkout's data directory; use it only when current site behavior is part of the task.
- `./scripts/process_control.sh --list`, or `.\scripts\process_control.ps1 -List` on Windows (without a switch it only prints help): inspect the integrated local processes read-only. `--restart`/`-Restart` and `--kill`/`-Kill` stop every matching local narou/Astro process. They prompt for confirmation unless `--force`/`-Force` is given, and in a non-interactive shell the prompt gets no input and the script exits 1 without doing anything. When no matching process is running there is no prompt: `--kill` exits 0, and `--restart` starts the backend (writing `backend.log`) and the Astro dev server right away. Run them only when the user asked for that side effect, and then pass `--force`.

Bundler evaluates `narou-mod.gemspec` on every `bundle install` and `bundle exec`, including the backend that `npm run test:e2e:integration` starts. Each evaluation rewrites `commitversion`. When `frontend/dist/.build-commit` is missing or differs from `git describe --always`, it also runs `npm ci` (which replaces `frontend/node_modules` and needs network) and `npm run build` in `frontend/`. If npm is missing or the build fails, it only prints a warning, keeps the old `dist/`, and retries on every later Bundler command. Expect the first run after a new commit to be slow; these outputs are not source.

## Repository-Specific Boundaries

- Follow `frontend/AGENTS.md` for every change under `frontend/`.
- Treat `README.md`, `CHANGELOG.md`, `docs/openapi.yaml`, and `docs/development.md` as publishable product documentation, not substitutes for current code verification.
- Do not read or summarize `.env*`, credentials, private keys, local databases, raw logs, dependency caches, coverage output, or build output unless the user explicitly places them in scope.
- Do not edit generated or runtime output as source: `frontend/dist/` (including `.build-commit`), coverage reports, built `.gem` files, `commitversion`, `backend.log`, runtime `frontend/public/backend-port.json`, the fixture copies `.test_dot_narou/` and `.test_novel_data/` at the repository root, and the checkout's `.narou/` data directory. Edit fixtures under `spec/fixtures/` instead.

## Documentation Lifecycle

- Keep only reviewed, publishable documentation in the parent repository's tracked `docs/` tree. At present, `docs/openapi.yaml` and `docs/development.md` are the reviewed documents there.
- Use `docs/_tmp/` for local-only investigations, implementation plans, design drafts, decision notes, performance reports, and handoff material that should not be published with the project.
- Treat every Markdown document under `docs/_tmp/` as unverified until its claims have been checked against current code, manifests, tests, and runtime behavior.
- Treat `docs/_tmp/` as an independent local Git repository ignored by the parent repository. Do not add a remote, push it, or publish its contents unless the user explicitly requests that action.
- Private placement is not a substitute for secret storage. Never put credentials, tokens, private keys, personal data, downloaded novel content, or raw sensitive logs in `docs/_tmp/`.
- Consult `docs/_tmp/` only when the task needs the relevant local research or plan. Do not copy its contents into public artifacts wholesale.
- Promote a document back to tracked `docs/` only after review. When local findings change an accepted public contract or current behavior, update the relevant tracked documentation, tests, changelog, or agent context in the same implementation change.

## Repository Editing Rules

- Inspect `git status --short` and the relevant diff before editing or staging.
- Keep changes scoped. Broad refactors require a concrete need and explicit agreement.
- Preserve the public CLI, REST API, configuration formats, novel data, and converter output unless the task explicitly changes their contract; users run existing novel archives and scripts against them.
- Ruby style: start new files with `# frozen_string_literal: true` (a repository convention; the cop is disabled). Use 2-space indentation, `snake_case` files/methods, `Narou::CamelCase` namespaces, and double-quoted strings, which the existing code uses almost everywhere (`Style/StringLiterals` is disabled). Follow nearby style when legacy files differ.
- Haml and SCSS follow nearby legacy view conventions; `.haml-lint.yml` and `.scss-lint.yml` document them, but their linters are not bundled.
- Keep network and filesystem side effects out of ordinary tests; use existing helpers and fixtures under `spec/support/`, `spec/fixtures/`, and `spec/data/`.
- `spec/support/init_fixtures.rb` copies `spec/fixtures/.test_dot_narou/` and `.test_novel_data/` to the repository root and recopies them only when `spec/fixtures/.test_dot_narou/fixture_version.txt` changes. Update that timestamp whenever you edit these fixtures, or local runs silently keep the old copy. The Playwright integration backend (`scripts/run_e2e_backend.rb`) uses the same fixtures.
- Converter tests are golden files: `spec/data/convert_test/<case>/test_<case>.txt` (its title must equal the file name) with the expected `correct_test_<case>.txt`, plus an optional per-case `setting.ini` or `replace.txt`. `spec/novel/convert_spec.rb` is generated; regenerate it with `ruby spec/generator/convert_spec_gen.rb` from the repository root instead of editing it. The spec writes converted `[<author>]*.txt` outputs next to each case and deletes them afterwards; an interrupted run or a `spec/debug` file leaves them behind as untracked files, which should be deleted, not committed.
- Site definitions have two layers. `webnovel/<domain>.yaml` is always loaded (`lib/novel/sitesetting.rb`) and drives URL matching, the table of contents, and novel metadata for every site; under the `legacy` engine it also parses section bodies. The default `nokogiri` engine replaces only section-body parsing (`lib/novel/downloader/section_downloader.rb`), using `preset/parsers/<domain>.yaml` and `lib/narou/parsers/`. Only kakuyomu.jp, ncode.syosetu.com, and novel18.syosetu.com have presets; other sites fall back to `webnovel/` patterns because `lib/novel/downloader.rb` rescues parser selection to nil. Put TOC and metadata fixes in `webnovel/`.
- `preset/parsers/legacy_archive/<domain>/v<version>.yaml` keeps past `webnovel/` versions for the parser settings API. When you edit a `webnovel/` definition, apply the same edit to the archive file for its current `version`, as commit 8c0591dc did; bump `version` only when the user wants a new history entry. `dev/archive_legacy_parsers.rb` rebuilds snapshots from committed history only.
- Do not disturb the load-path and RubyGems conflict handling in `narou.rb` or the YJIT/Bootsnap/bootstrap ordering in `bin/narou-mod` without entry-point regression coverage such as `spec/loading/gem_conflict_guard_spec.rb`; the ordering decides whether checkout or installed gem code runs.
- Update `CHANGELOG.md` for user-visible behavior, compatibility changes, release-impacting dependency changes, or fixes users need to know about. Entries are Japanese, go under an `Unreleased` section until release, and use the existing `### ⚠️ 互換性変更` / `### ✨ 新機能` / `### 🐛 バグ修正` / `### 🔧 メンテナンス` headings with a bold summary bullet and indented details. Internal-only changes need no entry.

## Security and Secrets

- Never commit secrets or local environment files. Keep examples synthetic and use existing example files for documented configuration.
- Treat downloaded HTML and metadata as untrusted input. Preserve sanitization, encoding handling, Cloudflare/challenge detection (under `lib/novel/downloader/`), and public error boundaries.
- Avoid live downloads in routine tests. Use fixtures first; perform narrow live verification only when current site behavior is part of the task.
- Do not expose provider bodies, tokens, private URLs, raw logs, or user novel content in agent context, issues, test fixtures, or public error messages.

## Repository Validation Matrix

Choose the smallest validation set that proves the changed behavior, then expand when risk warrants it.

| Changed area | Minimum validation |
| --- | --- |
| Ruby implementation | Focused `bundle exec rspec <spec-path>`; run `bundle exec rspec` for cross-cutting changes |
| Ruby style/quality | `bundle exec rubocop <changed-ruby-files>`; report pre-existing offenses separately from new ones |
| CLI/bootstrap | Relevant CLI specs plus a representative `bundle exec ruby narou.rb <command>` smoke test |
| Sinatra/API | Relevant `spec/web/*` specs and API documentation/contract review |
| Site parser/definition | Parser/downloader specs, fixture variants, and the matching `legacy_archive/` edit |
| Frontend | Follow `frontend/AGENTS.md`; normally `npm run format:check`, `npm run check`, and `npm run build` |
| UI flow | Relevant Playwright test and visual/browser verification when behavior or layout changes |
| Agent context | Project-scoped `agent_context.py check`, `skills check`, sync/routes idempotency, and `git diff --check` |
| Documentation only | Verify each changed claim against code, manifests, or command output, and run `git diff --check` |

CI runs on pull requests to `develop`, `release`, and `draft` and on pushes to `release` and `draft`. Its build-test job runs, in order: `npm ci`, Playwright browser install, `npm run build`, `npm run validate:html`, `npm run check`, `npm run test:e2e:smoke`, `npm run test:e2e:integration`, and RSpec. It does not run `format:check` or RuboCop, so run those locally. A separate job regenerates agent context with `scaffold . --agent codex` and fails on drift. Local validation should follow the same order for changes crossing backend/frontend boundaries.

## Git, Branches, and Releases

- Use Git author and committer `ponpon.USA <init0531.usa@gmail.com>`; do not introduce another identity. Older merges made through the GitHub web UI carry other identities; do not rewrite history to change them.
- Use imperative English commit subjects and reference related issues as `#123` when applicable. Topic branches use `feature/<topic>`, `fix/<topic>`, or `chore/<topic>` and merge into `develop` through pull requests.
- Normal feature/fix work targets `develop`. Release promotion is `develop` to `release`; `draft` is used for staging validation. GitHub's default branch is `release`, so tools that assume the default branch (Claude Code's git context, `gh pr create` without `--base`) pick the wrong target; open topic-branch pull requests with `--base develop`.
- Pushes to `release` or `draft` build platform gems and can create/update GitHub Releases. Do not push or merge to those branches without an explicit release request.
- A version bump changes exactly `lib/core/version.rb`, the `CHANGELOG.md` heading (`Unreleased` becomes `X.Y.Z (YYYY-MM-DD)`), the `Gemfile.lock` PATH version, and the `README.md` install example.
- Release tags append the `commitversion` commit suffix to the gem version (for example `3.1.6-<commit>`), while gem asset filenames use the plain gem version and the Linux/macOS gem has no platform suffix (`narou-mod-<version>.gem` vs `narou-mod-<version>-x64-mingw-ucrt.gem`). Verify the computed version and both artifacts during release work.
- Stage explicit paths in a mixed worktree and leave unrelated local artifacts out of commits.

## Repository Handoff Requirements

- Report changed files, exact validation commands, failures, skipped checks, and residual risk.
- For work spanning sessions, keep a checklist and progress note in `docs/_tmp/` unless the user names another path: done items with the command that verified them, open items, and the next step. On resume, read that note plus `git status` and `git log` before acting.
- When current code contradicts documentation or this context, verify the behavior, update the stale context in the same change when in scope, and call out the reconciliation.
