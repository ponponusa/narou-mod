# Claude Agent Profile

<!-- agent-context-maintainer:begin -->
## Claude Profile

- Active detected profile: no

## Behavior

- Use strengths in long-form design review and cross-document reconciliation.
- State assumptions and open questions explicitly.
- Convert analysis into concrete edits when implementation is requested.
- Custom subagents may be defined in `.claude/agents/*.md`; read them before changing delegation behavior.
<!-- agent-context-maintainer:end -->

## Claude Code Working Notes

These notes target the Claude 5.5 family (Opus 5.5 and Sonnet 5.5) in Claude Code and are safe for other Claude models. Root `CLAUDE.md` imports `AGENTS.md`, `.agents/core.md`, `.agents/routing.md`, and this profile, so they are already in context when the session starts at the repository root. If Claude Code was started elsewhere and they are missing (for example, external imports were not approved), read them before changing anything. `frontend/CLAUDE.md` adds `frontend/AGENTS.md` when you open a file under `frontend/` with the Read tool; shell reads such as `cat` may not trigger it, so make sure `frontend/AGENTS.md` is in context before a frontend edit. Open other agent-context files (other providers' profiles, skills, `docs/_tmp/` notes) only when a route points to them; read source, specs, and manifests as the task requires.

### Scope and stopping

Current Claude models follow instructions literally, so the scope stated here is the scope that applies. Keep working until everything the user asked for is done; stop to ask only when you cannot continue without the user, or before a risky or hard-to-undo step the user has not asked for in this conversation, such as pushing, merging to `release` or `draft`, deleting novel data, or running `process_control.sh --restart` or `--kill`. When the user did ask for that step, carry it out without asking again. When the requested work is done and checked, stop and report. Unrelated pre-existing bugs, cleanups, refactors, and tests or docs beyond what the task needs go into the report as suggestions rather than into the change. Updates the repository rules require for the change itself, such as `CHANGELOG.md`, `docs/openapi.yaml`, `spec/web/` coverage, the smoke routes table, and stale agent context, are part of the change. When the user only asks a question, answer it without editing files. When they report a bug, investigate; if the intended behavior is clear, fix it, and if it is not, report the cause and ask which behavior they want.

### Grounding

Answer questions about this repository from files you have opened in this session (code, specs, lockfiles, `docs/openapi.yaml`), not from remembered Sinatra, Astro, or Svelte defaults. The frameworks here are recent majors, and `docs/_tmp/` notes may be stale. Read independent files in parallel.

### Code changes

Match the surrounding code's idiom, naming, and comment density. Prefer targeted edits over rewriting whole files. Do not add helpers, abstractions, `rescue` clauses, fallbacks, or validation for cases that cannot occur. Validate at the real boundaries this repository treats as untrusted: downloaded HTML and metadata, REST input, and CLI arguments.

### Verification and tests

A change is done only after a check from the validation matrix has actually exercised it. A syntax-only check or a command that failed to start does not count. If the project's declared dependencies are missing, install them with the project's tools (`bundle install` at the root, `npm ci` in `frontend/`) unless the user said not to; because both can replace `frontend/node_modules` (see the gemspec note in `.agents/core.md`), ask first if the user's `npm run dev` or `narou web` is running. Do not install or upgrade global tooling such as Ruby, Bundler itself, Node, or Playwright system packages without asking. If a check still cannot run, say which one and why. Tests verify behavior; they do not define it. Do not special-case fixture values, and do not loosen, skip, or rewrite an existing RSpec or Playwright expectation just to get a pass; if an expectation looks wrong, report it with evidence. When the task intentionally changes behavior, update the expectations that encode the old behavior (for example a golden `correct_test_*.txt` file or the routes table in `frontend/e2e/smoke.spec.ts`) and name each one in the report. Size new specs like their neighbors, and keep scratch scripts outside the repository.

### Subagents

Use subagents for independent tracks that need a wide read: backend and frontend investigations in parallel, or a sweep across `webnovel/`, `preset/parsers/`, and their specs. Work directly on single-file edits, sequential steps, and checks you can finish with a few tool calls. Launch review subagents only when the user asked for a review. Shared project subagents belong in `.claude/agents/`, which is tracked; read existing definitions there before changing delegation behavior.

### Reporting and long tasks

Lead the final report with the outcome in one or two sentences, then list changed files, the exact commands run, failures or skipped checks, and residual risk. Write complete sentences rather than shorthand. For multi-session work, keep the progress note described in `.agents/core.md` current, so that a fresh context can resume from it together with `git log`.

### Effort

Opus 5.5 and Sonnet 5.5 default to `medium` effort in Claude Code. Phrases in these files do not change that. For cross-cutting backend-and-frontend changes, parser architecture, or release work, suggest that the user raise effort with `/effort high` or `/effort xhigh`.
