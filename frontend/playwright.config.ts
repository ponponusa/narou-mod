import { defineConfig, devices } from "@playwright/test";

import {
  BACKEND_PORT,
  SMOKE_FRONTEND_ORIGIN,
  SMOKE_FRONTEND_PORT,
} from "./e2e/support/ports";

export default defineConfig({
  testDir: "./e2e",
  testMatch: "smoke.spec.ts",
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  reporter: process.env.CI ? "line" : "html",
  use: {
    baseURL: SMOKE_FRONTEND_ORIGIN,
    trace: "on-first-retry",
    screenshot: "only-on-failure",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
  webServer: {
    command: "npm run dev:e2e",
    url: SMOKE_FRONTEND_ORIGIN,
    reuseExistingServer: false,
    timeout: 120_000,
    gracefulShutdown: {
      signal: "SIGTERM",
      timeout: 10_000,
    },
    env: {
      NAROU_E2E_DISABLE_SRI: "true",
      NAROU_E2E_FRONTEND_PORT: String(SMOKE_FRONTEND_PORT),
      NAROU_TEST_BACKEND_PORT: String(BACKEND_PORT),
    },
  },
});
