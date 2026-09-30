import { expect, test } from "@playwright/test";

import {
  assertCleanNetwork,
  installDeterministicNetwork,
} from "./support/network";

const baseURL = process.env.NAROU_VISUAL_BASE_URL;
if (!baseURL) throw new Error("NAROU_VISUAL_BASE_URL is required");

const routes = [
  ["home", "/"],
  ["settings", "/settings"],
  ["settings-debug", "/settings-debug"],
  ["tasks", "/tasks"],
  ["help", "/help"],
] as const;

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem("theme", "light"));
});

for (const [name, path] of routes) {
  test(`${name} matches the Astro 5 visual baseline`, async ({ page }) => {
    const monitor = await installDeterministicNetwork(page, {
      frontendOrigin: new URL(baseURL).origin,
      mockApi: true,
      mockPushServer: true,
    });
    if (name === "settings-debug") {
      // The Astro 5 reference build hard-codes this LAN API URL. Keep this
      // compatibility route until that visual baseline is regenerated.
      await page.route(
        "http://172.26.39.220:33000/api/v2/settings/variables",
        async (route) => {
          await route.fulfill({
            contentType: "application/json",
            body: JSON.stringify({
              success: true,
              data: {
                variables: { local: {}, global: {} },
                tab_names: {},
                tab_info: {},
              },
            }),
          });
        }
      );
    }

    await page.goto(path, { waitUntil: "networkidle" });
    await page.addStyleTag({
      content: `
        *, *::before, *::after {
          animation: none !important;
          caret-color: transparent !important;
          transition: none !important;
        }
      `,
    });
    await page.evaluate(() => document.fonts.ready);

    await expect(page).toHaveScreenshot(`${name}.png`, {
      animations: "disabled",
      caret: "hide",
      fullPage: true,
      maxDiffPixelRatio: 0,
      scale: "css",
    });
    assertCleanNetwork(monitor);
  });
}
