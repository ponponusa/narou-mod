import { expect, test, type Page } from "@playwright/test";

import {
  assertCleanNetwork,
  installDeterministicNetwork,
} from "./support/network";
import { SMOKE_FRONTEND_ORIGIN } from "./support/ports";

const routes = [
  {
    path: "/",
    title: "Narou.rb MOD - ホーム",
    apiPath: "/api/v2/novels",
    assertContent: async (page: Page) => {
      await expect(page.getByText("小説が登録されていません")).toBeVisible();
    },
  },
  {
    path: "/settings",
    title: "設定 - Narou",
    apiPath: "/api/v2/settings/variables",
    assertContent: async (page: Page) => {
      await expect(
        page.getByRole("heading", { name: "設定", exact: true })
      ).toBeVisible();
    },
  },
  {
    path: "/settings-debug",
    title: "設定デバッグ - Narou",
    apiPath: "/api/v2/settings/variables",
    assertContent: async (page: Page) => {
      await expect(page.locator("#api-output")).toContainText('"variables"');
    },
  },
  {
    path: "/tasks",
    title: "Narou.rb MOD - タスクキュー",
    apiPath: "/api/v2/tasks",
    assertContent: async (page: Page) => {
      await expect(
        page.getByRole("heading", { name: "タスクキュー管理" })
      ).toBeVisible();
    },
  },
  {
    path: "/help",
    title: "Narou.rb MOD - ヘルプ",
    apiPath: "/api/v2/system/version",
    assertContent: async (page: Page) => {
      await expect(page.getByRole("heading", { name: "ヘルプ" })).toBeVisible();
      await expect(
        page.locator('link[href*="cdnjs.cloudflare.com"]').first()
      ).not.toHaveAttribute("integrity", /.+/);
      await expect
        .poll(() =>
          page
            .locator("i.fas")
            .first()
            .evaluate((icon) =>
              getComputedStyle(icon).getPropertyValue(
                "--narou-e2e-font-awesome"
              )
            )
        )
        .toBe("loaded");
    },
  },
];

test.describe("frontend migration smoke", () => {
  for (const route of routes) {
    test(`${route.path} renders with same-origin API requests`, async ({
      page,
    }) => {
      const monitor = await installDeterministicNetwork(page, {
        frontendOrigin: SMOKE_FRONTEND_ORIGIN,
        mockApi: true,
        mockPushServer: true,
      });

      await page.goto(route.path);
      await expect(page).toHaveTitle(route.title);
      await route.assertContent(page);
      await expect
        .poll(() => monitor.apiRequests.some((path) => path === route.apiPath))
        .toBe(true);
      await expect
        .poll(() => monitor.pushServerRequests.length)
        .toBeGreaterThan(0);

      assertCleanNetwork(monitor);
    });
  }

  test("mock PushServer delivers a synthetic console event", async ({
    page,
  }) => {
    const monitor = await installDeterministicNetwork(page, {
      frontendOrigin: SMOKE_FRONTEND_ORIGIN,
      mockApi: true,
      mockPushServer: true,
    });

    await page.goto("/help");
    await page.getByRole("button", { name: /^コンソール/ }).click();
    await expect(page.getByText("E2E synthetic console event")).toBeVisible();

    assertCleanNetwork(monitor);
  });
});
