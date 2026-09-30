import type { ConsoleMessage, Page, Route } from "@playwright/test";

import { BACKEND_PORT, PUSH_SERVER_PORT } from "./ports";

const allowedStoppedServerErrors = [
  /Failed to load backend-port\.json/,
  /\[PushServer\] WebSocket error/,
  /\[PushServer\] Max reconnection attempts reached/,
  /cdnjs\.cloudflare\.com.*integrity|integrity.*cdnjs\.cloudflare\.com/i,
];

export interface NetworkMonitor {
  apiRequests: string[];
  consoleErrors: string[];
  pageErrors: string[];
  unexpectedExternalRequests: string[];
  pushServerRequests: string[];
}

interface NetworkOptions {
  frontendOrigin: string;
  mockApi: boolean;
  mockPushServer: boolean;
}

const deterministicFontAwesomeCss = `
  .fas, .far, .fab, .fa-solid, .fa-regular, .fa-brands {
    --narou-e2e-font-awesome: loaded;
    display: inline-block;
    width: 1.25em;
    text-align: center;
    font-style: normal;
  }
  .fas::before, .far::before, .fab::before,
  .fa-solid::before, .fa-regular::before, .fa-brands::before {
    content: "";
  }
`;

function apiResponse(pathname: string): unknown {
  const timestamp = "2026-08-13T00:00:00.000Z";

  switch (pathname) {
    case "/api/v2/novels":
      return {
        success: true,
        data: { novels: [], total: 0 },
        timestamp,
      };
    case "/api/v2/tags":
      return { success: true, data: { tags: [] }, timestamp };
    case "/api/v2/tags/index":
      return {
        success: true,
        data: { tag_index: {}, total_tags: 0, generated_at: 0 },
        timestamp,
      };
    case "/api/v2/system/version":
      return {
        success: true,
        data: { narou: "3.1.7-e2e", ruby: "3.4.0", latest: null },
        timestamp,
      };
    case "/api/v2/system/status":
      return {
        success: true,
        data: {
          queue: {
            total: 0,
            web_worker: 0,
            worker: 0,
            running: false,
          },
          push_server: { running: true, port: PUSH_SERVER_PORT },
          version: { narou: "3.1.7-e2e", ruby: "3.4.0" },
        },
        timestamp,
      };
    case "/api/v2/settings":
      return {
        success: true,
        data: { local: {}, global: {} },
        timestamp,
      };
    case "/api/v2/settings/variables":
      return {
        success: true,
        data: {
          variables: { local: {}, global: {} },
          tab_names: {},
          tab_info: {},
        },
        timestamp,
      };
    case "/api/v2/tasks":
      return {
        success: true,
        data: { tasks: [], count: 0 },
        timestamp,
      };
    case "/api/v2/tasks/summary":
      return {
        success: true,
        data: {
          queued: [],
          recent_completed: [],
          recent_failed: [],
          completed_count: 0,
          failed_count: 0,
          convert_queued: [],
        },
        timestamp,
      };
    default:
      return { success: true, data: {}, timestamp };
  }
}

function isFixedAssetHost(url: URL): boolean {
  return [
    "cdnjs.cloudflare.com",
    "fonts.googleapis.com",
    "fonts.gstatic.com",
  ].includes(url.hostname);
}

function isLoopback(url: URL): boolean {
  return ["127.0.0.1", "localhost", "::1"].includes(url.hostname);
}

function isAllowedConsoleError(message: string): boolean {
  return allowedStoppedServerErrors.some((pattern) => pattern.test(message));
}

async function handleRoute(
  route: Route,
  options: NetworkOptions,
  monitor: NetworkMonitor
): Promise<void> {
  const url = new URL(route.request().url());
  const { frontendOrigin } = options;

  if (url.origin === frontendOrigin && url.pathname === "/backend-port.json") {
    await route.fulfill({
      contentType: "application/json",
      body: JSON.stringify({
        backend_port: BACKEND_PORT,
        push_server_port: PUSH_SERVER_PORT,
        updated_at: "2026-08-13T00:00:00.000Z",
      }),
    });
    return;
  }

  if (url.origin === frontendOrigin && url.pathname.startsWith("/api/")) {
    monitor.apiRequests.push(`${url.pathname}${url.search}`);
    if (options.mockApi) {
      await route.fulfill({
        contentType: "application/json",
        body: JSON.stringify(apiResponse(url.pathname)),
      });
    } else {
      await route.continue();
    }
    return;
  }

  if (isFixedAssetHost(url)) {
    await route.fulfill({
      contentType: "text/css; charset=utf-8",
      body:
        url.hostname === "cdnjs.cloudflare.com"
          ? deterministicFontAwesomeCss
          : "/* deterministic empty font stylesheet for E2E */",
    });
    return;
  }

  if (isLoopback(url)) {
    await route.continue();
    return;
  }

  monitor.unexpectedExternalRequests.push(url.href);
  await route.abort("blockedbyclient");
}

export async function installDeterministicNetwork(
  page: Page,
  options: NetworkOptions
): Promise<NetworkMonitor> {
  const monitor: NetworkMonitor = {
    apiRequests: [],
    consoleErrors: [],
    pageErrors: [],
    unexpectedExternalRequests: [],
    pushServerRequests: [],
  };

  page.on("console", (message: ConsoleMessage) => {
    if (message.type() !== "error") return;
    const text = message.text();
    if (!isAllowedConsoleError(text)) monitor.consoleErrors.push(text);
  });
  page.on("pageerror", (error) => monitor.pageErrors.push(error.message));

  await page.route("**/*", (route) => handleRoute(route, options, monitor));

  if (options.mockPushServer) {
    await page.routeWebSocket(
      (url) =>
        isLoopback(url) && Number.parseInt(url.port, 10) === PUSH_SERVER_PORT,
      (webSocket) => {
        monitor.pushServerRequests.push(webSocket.url());
        setTimeout(() => {
          webSocket.send(
            JSON.stringify({
              echo: {
                target_console: "stdout",
                body: "E2E synthetic console event",
                timestamp: "2026-08-13T00:00:00.000Z",
              },
            })
          );
        }, 100);
      }
    );
  }

  return monitor;
}

export function assertCleanNetwork(monitor: NetworkMonitor): void {
  if (monitor.unexpectedExternalRequests.length > 0) {
    throw new Error(
      `Unexpected external requests: ${monitor.unexpectedExternalRequests.join(", ")}`
    );
  }
  if (monitor.consoleErrors.length > 0) {
    throw new Error(
      `Unexpected console errors: ${monitor.consoleErrors.join(" | ")}`
    );
  }
  if (monitor.pageErrors.length > 0) {
    throw new Error(
      `Unexpected page errors: ${monitor.pageErrors.join(" | ")}`
    );
  }
}

export { BACKEND_PORT, PUSH_SERVER_PORT } from "./ports";
