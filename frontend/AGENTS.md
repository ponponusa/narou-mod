# Frontend Agent Instructions

These instructions apply to `frontend/`. First follow `../AGENTS.md`, `../.agents/core.md`, and `../.agents/routing.md`; this file contains only Astro/Svelte-specific rules.

## Current Stack and Boundaries

- Astro 7 with the Svelte integration provides pages, layouts, static output, and development proxying.
- Svelte 5 components use runes such as `$state`, `$props`, `$derived`, `$effect`, and `$bindable`.
- Tailwind CSS 4 is loaded through `@tailwindcss/vite`; shared CSS starts in `src/styles/global.css`.
- TypeScript 6 runs in Astro strict mode with bundler module resolution.
- Playwright is the current browser test framework. There is no Vitest/unit-test command in `package.json`.
- npm and `package-lock.json` are the dependency source of truth; CI uses Node.js 24.

Exact package versions belong to `package-lock.json`. Check `package.json`, the lockfile, and framework config before relying on a version-sensitive API.

## Source Map

- `src/pages/`: Astro routes (`index`, `settings`, `settings-debug`, `tasks`, and `help`).
- `src/layouts/`: shared Astro layouts.
- `src/components/`: Svelte UI; console-specific components are under `src/components/console/`.
- `src/lib/api.ts`: typed wrappers for backend REST calls.
- `src/lib/backend-config.ts`: runtime backend/push-server port resolution.
- `src/lib/pushserver.ts` and `src/lib/progressStore.ts`: push and progress integration.
- `src/lib/stores/`: client stores such as server status.
- `src/types/api.ts`: shared API/domain types.
- `public/backend-port.json`: runtime-generated and ignored; never treat it as source.
- `e2e/`: Playwright flows.

## Commands

Run these from `frontend/`:

- `npm ci`: reproduce the lockfile environment; use this for validation and CI parity.
- `npm install`: use only when intentionally changing dependencies/lockfile.
- `npm run dev`: start Astro on port 4321.
- `npm run build`: create `dist/` and write `dist/.build-commit` from `git describe`.
- `npm run preview`: preview the built output.
- `npm run check`: run Astro/TypeScript diagnostics.
- `npm run format`: format supported source files.
- `npm run format:check`: check formatting without writing.
- `npm run validate:html`: validate all HTML pages in the current `dist/` output.
- `npm run test:e2e:smoke`: run deterministic, backend-free browser coverage for all routes.
- `npm run test:e2e:integration`: run the isolated Ruby backend and verify the Vite proxy path (Linux/macOS only).

For the integrated local stack, inspect and use `../scripts/process_control.sh` or `../scripts/process_control.ps1`. The backend defaults are 5678 for REST and 5679 for push when `backend-port.json` is unavailable.

## Implementation Rules

- Use 2 spaces, double quotes, 80-column formatting, and ES5 trailing commas as configured by `.prettierrc`.
- Component files use `PascalCase.svelte`; Astro routes use `kebab-case.astro` or `index.astro`; TypeScript modules follow the existing local naming pattern.
- Use Svelte 5 runes for new state and props. Do not introduce legacy `export let` component APIs or regress a runes-based component to Svelte 4 patterns.
- Keep TypeScript strict. Avoid `any`; update `src/types/api.ts` or a nearby explicit interface when the contract changes.
- Prefer Tailwind utilities and existing design patterns. Add component CSS only when the style is not reasonably expressible with the current system.
- Keep browser-only APIs out of server-side execution. Guard `window`, `document`, storage, and event subscriptions and clean up subscriptions/timers in effects.
- Route REST calls through `src/lib/api.ts`; do not scatter raw endpoint construction through components.
- Keep endpoint paths, request/response types, and Ruby API behavior synchronized. API changes normally require both backend specs/docs and frontend types/wrappers.
- Resolve backend/push ports through `backend-config.ts` or the existing dev proxy; do not hard-code a new host/port in UI code.
- Preserve the stopped-server fallback and reconnection behavior when changing initial loading or server-status UI.
- Do not edit `dist/`, `.astro/`, `playwright-report/`, `test-results/`, `node_modules/`, or runtime port files as source.

## Validation

Choose checks based on the change:

1. Run `npm run format:check` and `npm run check` for TypeScript, Astro, or Svelte changes.
2. Run `npm run build` for routing, configuration, bundling, or integration changes.
3. Run the smoke Playwright suite for user-visible flows and the integration suite for proxy/backend changes; add/update coverage when behavior changes.
4. For layout or interaction changes, verify the built UI in a browser at relevant desktop/mobile widths and capture evidence for the PR.
5. For backend integration, run the matching Ruby API specs as well as frontend checks.

If a broad baseline check fails outside the changed slice, establish the focused result first and report the unrelated failure rather than masking it.

## Security and Handoff

- Never expose secrets through `PUBLIC_` variables or bundle private URLs/credentials into browser code.
- Treat backend response strings and downloaded novel metadata as untrusted; use Svelte's normal escaped rendering unless reviewed sanitization is explicitly required.
- UI PRs should describe the tested flow and include screenshots or recordings when visuals changed.
- Report exact commands, browser coverage, skipped checks, and whether the backend was live or a stopped-server fallback was used.
