import { defineConfig, devices } from "@playwright/test";

const baseURL = process.env.NAROU_VISUAL_BASE_URL;
const snapshotDirectory = process.env.NAROU_VISUAL_SNAPSHOT_DIR;

if (!baseURL || !snapshotDirectory) {
  throw new Error(
    "NAROU_VISUAL_BASE_URL and NAROU_VISUAL_SNAPSHOT_DIR are required"
  );
}

export default defineConfig({
  testDir: "./e2e",
  testMatch: "visual.spec.ts",
  fullyParallel: false,
  forbidOnly: true,
  retries: 0,
  workers: 1,
  reporter: "line",
  snapshotPathTemplate: `${snapshotDirectory}/{projectName}/{arg}{ext}`,
  use: {
    baseURL,
    colorScheme: "light",
    contextOptions: { reducedMotion: "reduce" },
    trace: "off",
  },
  projects: [
    {
      name: "desktop",
      use: {
        ...devices["Desktop Chrome"],
        viewport: { width: 1440, height: 900 },
      },
    },
    {
      name: "mobile",
      use: {
        ...devices["Desktop Chrome"],
        viewport: { width: 390, height: 844 },
      },
    },
  ],
});
