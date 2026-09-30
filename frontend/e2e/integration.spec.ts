import { expect, test } from "@playwright/test";

import {
  assertCleanNetwork,
  installDeterministicNetwork,
  PUSH_SERVER_PORT,
} from "./support/network";
import { INTEGRATION_FRONTEND_ORIGIN } from "./support/ports";

test("relative API requests traverse the Vite proxy to the isolated backend", async ({
  page,
}) => {
  const monitor = await installDeterministicNetwork(page, {
    frontendOrigin: INTEGRATION_FRONTEND_ORIGIN,
    mockApi: false,
    mockPushServer: false,
  });
  const webSockets: string[] = [];
  page.on("websocket", (webSocket) => webSockets.push(webSocket.url()));

  await page.goto("/");

  const response = await page.evaluate(async () => {
    const result = await fetch("/api/v2/novels");
    const text = await result.text();
    return {
      ok: result.ok,
      status: result.status,
      url: result.url,
      text,
      headers: Object.fromEntries(result.headers.entries()),
    };
  });

  expect(response.ok, JSON.stringify(response, null, 2)).toBe(true);
  expect(new URL(response.url).origin).toBe("http://localhost:4321");
  const body = JSON.parse(response.text);
  expect(body.success).toBe(true);
  expect(body.data.novels.length).toBeGreaterThan(0);
  await expect
    .poll(() =>
      webSockets.some((url) => new URL(url).port === String(PUSH_SERVER_PORT))
    )
    .toBe(true);

  const echo = await page.evaluate(async (port) => {
    return new Promise<Record<string, unknown>>((resolve, reject) => {
      const socket = new WebSocket(`ws://127.0.0.1:${port}/`);
      const timeout = window.setTimeout(
        () => reject(new Error("PushServer echo timed out")),
        5_000
      );
      socket.addEventListener("open", () => socket.send("invalid-json"));
      socket.addEventListener("message", (event) => {
        window.clearTimeout(timeout);
        socket.close();
        resolve(JSON.parse(String(event.data)));
      });
      socket.addEventListener("error", () => {
        window.clearTimeout(timeout);
        reject(new Error("PushServer connection failed"));
      });
    });
  }, PUSH_SERVER_PORT);

  expect(echo).toHaveProperty("echo");
  expect(monitor.apiRequests).toContain("/api/v2/novels");
  assertCleanNetwork(monitor);
});
