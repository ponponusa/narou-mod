import { dev } from "astro";

const port = Number.parseInt(process.env.NAROU_E2E_FRONTEND_PORT ?? "", 10);
if (!Number.isInteger(port) || port < 1 || port > 65_535) {
  throw new Error("NAROU_E2E_FRONTEND_PORT must be a valid TCP port");
}

const server = await dev({
  root: new URL("../", import.meta.url),
  server: {
    host: "127.0.0.1",
    port,
  },
});

let stopping = false;
async function stop(signal) {
  if (stopping) return;
  stopping = true;
  console.log(`[Astro E2E] received ${signal}, stopping`);
  await server.stop();
  process.exit(0);
}

process.once("SIGINT", () => void stop("SIGINT"));
process.once("SIGTERM", () => void stop("SIGTERM"));
