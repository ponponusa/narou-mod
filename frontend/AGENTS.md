# Frontend Agent Instructions

These instructions apply to `frontend/` and add Astro/Svelte-specific rules to the shared repository context (`../AGENTS.md`, `../.agents/core.md`, `../.agents/routing.md`).

## Current Stack and Boundaries

- Astro 7 with the Svelte integration provides pages, layouts, static output, and development proxying.
- Svelte 5 components use runes such as `$state`, `$props`, `$derived`, `$effect`, and `$bindable`.
- Tailwind CSS 4 is loaded CSS-first through `@tailwindcss/vite`; `src/styles/global.css` holds the only Tailwind setup. There is no `tailwind.config.js`; add configuration in CSS (`@theme`, `@variant`) rather than reintroducing a JavaScript config.
- TypeScript 6 runs in Astro strict mode with bundler module resolution.
- Playwright is the only test framework; there is no unit-test command in `package.json`. No ESLint is configured; Prettier formats sources, and `html-validate` (`npm run validate:html`) lints the built HTML.
- npm and `package-lock.json` are the dependency source of truth; Node.js 24 (`.nvmrc`, `engines`, CI).

Exact package versions belong to `package-lock.json`. Check `package.json`, the lockfile, and framework config before relying on a version-sensitive API.

## Source Map

- `src/pages/`: Astro routes (`index`, `settings`, `settings-debug`, `tasks`, and `help`).
- `src/layouts/`: shared Astro layouts (`BaseLayout.astro` sets `lang="ja"` and loads Font Awesome from cdnjs).
- `src/components/`: Svelte UI; console-specific components are under `src/components/console/`.
- `src/lib/api.ts`: typed wrappers for backend REST calls; `API_BASE_URL` is `PUBLIC_API_BASE_URL` or an empty string (same origin).
- `src/lib/backend-config.ts`: runtime backend/push-server port resolution from `/backend-port.json`, falling back to 5678 (REST) and 5679 (push).
- `src/lib/pushserver.ts` and `src/lib/progressStore.ts`: PushServer WebSocket and progress integration.
- `src/lib/stores/`: `svelte/store` writables shared across islands, such as server status.
- `src/types/api.ts`: shared API/domain types.
- `public/backend-port.json`: written at runtime by `narou web`; ignored and never source.
- `e2e/`: `smoke.spec.ts`, `integration.spec.ts`, `visual.spec.ts`, and helpers in `e2e/support/`.

## Commands

Run these from `frontend/`:

- `npm ci`: reproduce the lockfile environment; use this for validation and CI parity.
- `npm install`: use only when intentionally changing dependencies/lockfile.
- `npm run dev`: start Astro on port 4321 with the `/api` proxy.
- `npm run build`: create `dist/` and write `dist/.build-commit` from `git describe --always`.
- `npm run preview`: preview the built output.
- `npm run check`: run Astro/TypeScript diagnostics.
- `npm run format` / `npm run format:check`: format or check `src/**` with Prettier. A husky pre-commit hook runs `lint-staged`, which formats staged files.
- `npm run validate:html`: validate all HTML pages in the current `dist/` output.
- `npm run compare:dom -- <before-dist> [after-dist]`: compare built DOM between two builds.
- `npm run test:e2e:smoke`: deterministic, backend-free browser coverage for all routes.
- `npm run test:e2e:integration`: start an isolated Ruby backend from the repository root and verify the Vite proxy path. It needs `bundle install` at the root and aborts on Windows (`scripts/run_e2e_backend.rb`).
- `npm run test:e2e:visual`: compare full-page screenshots at 1440px and 390px widths against an external baseline. It starts no server: set `NAROU_VISUAL_BASE_URL` to an already-running frontend and `NAROU_VISUAL_SNAPSHOT_DIR` to the baseline directory.
- `npx playwright test --config=playwright.config.ts -g "<title>"`: run one smoke test (each config pins one spec file).
- `npm run dev:e2e` is started by the smoke and integration configs; do not run it by hand.

For the integrated local stack, inspect and use `../scripts/process_control.sh` or `../scripts/process_control.ps1` (see `../.agents/core.md` for their side effects).

## E2E Harness

- Smoke tests install `page.route` handlers from `e2e/support/network.ts`. Same-origin `/backend-port.json` and `/api/*` requests are fulfilled, with `apiResponse()` returning canned JSON (unknown paths get `{ success: true, data: {} }`). cdnjs and Google Fonts get stub stylesheets, and the PushServer WebSocket is mocked. Any other external host is aborted and fails the test, as do unexpected console or page errors. Other loopback requests, including direct `getBackendBaseUrl()` calls, are not mocked.
- Ports: smoke frontend 4322, integration frontend 4321, isolated backend 45678 with push on 45679 (`e2e/support/ports.ts`). Integration uses `reuseExistingServer: false` and fails when 4321 is busy; if the user's `npm run dev` or `narou web` holds it, ask before stopping it.
- The smoke and integration configs set `NAROU_E2E_DISABLE_SRI=true` (removes the Font Awesome SRI attribute) and `NAROU_TEST_BACKEND_PORT` (proxy target).
- The routes table in `e2e/smoke.spec.ts` asserts each page's exact Japanese title, page-specific content (a heading, the home empty-state text, `#api-output` on settings-debug, and the SRI and Font Awesome checks on `/help`), the API path the page requests on load, and at least one PushServer connection. Changing that copy, id, or load-time endpoint, or adding a page, means updating the table in the same change.

## How the Build Ships

`narou-mod.gemspec` rebuilds `dist/` with `npm ci && npm run build` whenever `dist/.build-commit` differs from `git describe --always`, then packs `frontend/dist/**` into the gem. At runtime `../lib/web/routes/static_file.rb` serves the pages, `_astro` assets, and a dynamic `/backend-port.json`. A new page therefore needs the cross-side updates listed in the frontend route of `../.agents/routing.md`.

## Implementation Rules

- Use 2 spaces, double quotes, 80-column formatting, and ES5 trailing commas as configured by `.prettierrc`.
- Component files use `PascalCase.svelte`; Astro routes use `kebab-case.astro` or `index.astro`; TypeScript modules follow the existing local naming pattern.
- Use Svelte 5 runes for component state and props. Do not introduce legacy `export let`, `$:`, `createEventDispatcher`, or `on:` directives. State shared across islands stays in the existing `svelte/store` writables under `src/lib/stores/` unless the task is a deliberate migration.
- Hydrate components that touch `window`, `document`, or `localStorage` during initialization with `client:only="svelte"`; use `client:load` otherwise, as the existing pages do.
- Keep TypeScript strict. Avoid `any`; update `src/types/api.ts` or a nearby explicit interface when the contract changes.
- Keep browser-only APIs out of server-side execution. Guard `window`, `document`, storage, and event subscriptions and clean up subscriptions/timers in effects.
- Send new JSON REST calls through `src/lib/api.ts`. Same-origin `/api` requests go through the dev proxy in development and the Sinatra server in production, and the smoke mocks cover them. Existing exceptions: EPUB downloads (`NovelList.svelte`, `NovelDetailModal.svelte`) and the novel-settings calls in `ConversionSettingsModal.svelte` use `getBackendBaseUrl()`, which in development goes cross-origin to the backend port (bypassing the dev proxy) and is never mocked in smoke tests; settings export/import (`Settings.svelte`), console clear (`ConsolePanel.svelte`), and `settings-debug.astro` fetch same-origin `/api` paths directly. Do not copy any of these for new JSON endpoints.
- Leave `PUBLIC_API_BASE_URL` empty in `frontend/.env` for development and e2e runs; a value bypasses the `/api` proxy. It is the only `PUBLIC_` variable the frontend code reads; `.env.example` mirrors the template `narou web` writes, whose `PUBLIC_PUSH_SERVER_PORT` and `PUBLIC_DEV_MODE` are currently unused by `src/`.
- Resolve backend/push ports through `backend-config.ts` or the existing dev proxy; do not hard-code a host or port in UI code, because the backend port is chosen at runtime. The proxy covers only `/api`, so a non-`/api` endpoint needs a proxy change in `astro.config.mjs`.
- Keep endpoint paths, request/response types, and Ruby API behavior synchronized; see the frontend route in `../.agents/routing.md` for the full list of files an API change touches.
- Preserve the stopped-server fallback and reconnection behavior when changing initial loading or server-status UI.
- Do not edit `dist/`, `.astro/`, `playwright-report/`, `test-results/`, `node_modules/`, or runtime port files as source.

## UI Conventions

- UI copy is Japanese and hard-coded; there is no i18n library. Code comments in this tree are also Japanese.
- `DEVELOPMENT.md`, `IMPLEMENTATION_SUMMARY.md` (Astro 5), and `WSL_NOTES.md` in this directory predate the current stack; trust this file, `README.md`, and the code over them.
- Build new UI from the existing look: Tailwind utilities, the colors and spacing already used by neighboring components, Font Awesome icons, and dark mode through the `.dark` class on `<html>` (toggled by `ThemeToggle.svelte`, stored in `localStorage` as `theme`). Give neutral surface, text, and border colors a `dark:` variant as neighboring components do; saturated accent controls such as `bg-blue-600 text-white` buttons keep one style in both modes.
- Do not add new fonts, color palettes, or gradients. Match the rounding of neighboring elements: rectangular buttons, panels, and list tag chips use `rounded`, `rounded-md`, or `rounded-lg`; `rounded-full` is for circular elements such as badges, spinners, progress bars, status dots, and the floating scroll-to-top buttons.
- Use semantic headings, buttons, and labels. Smoke tests mostly query by role and accessible name but also rely on visible text, `#api-output`, the cdnjs `<link>`, and `i.fas` icons, so keep those stable or update the tests.
- Add component CSS only when the style is not reasonably expressible with Tailwind utilities.

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
