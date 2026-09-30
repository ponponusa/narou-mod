// @ts-check
import { defineConfig } from 'astro/config';
import { readFileSync, existsSync } from 'fs';
import { join } from 'path';

import svelte from '@astrojs/svelte';

import tailwindcss from '@tailwindcss/vite';

// バックエンドのポート情報を読み込む
function getBackendPort() {
  if (process.env.NAROU_TEST_BACKEND_PORT) {
    const testPort = Number.parseInt(process.env.NAROU_TEST_BACKEND_PORT, 10);
    if (Number.isInteger(testPort) && testPort > 0 && testPort <= 65535) {
      return testPort;
    }
    throw new Error('NAROU_TEST_BACKEND_PORT must be a valid TCP port');
  }

  const portFile = join(process.cwd(), 'public', 'backend-port.json');
  if (existsSync(portFile)) {
    try {
      const data = JSON.parse(readFileSync(portFile, 'utf-8'));
      return data.backend_port || 5678;
    } catch (error) {
      console.warn('[Astro Config] Failed to read backend-port.json:', error);
    }
  }
  return 5678; // デフォルトポート
}

const backendPort = getBackendPort();
console.log(`[Astro Config] Using backend port: ${backendPort}`);

// https://astro.build/config
export default defineConfig({
  integrations: [svelte()],

  vite: {
    plugins: [tailwindcss()],
    server: {
      proxy: {
        // バックエンドAPIへのプロキシ設定
        '/api': {
          target: `http://localhost:${backendPort}`,
          changeOrigin: true,
          rewrite: (path) => path, // パスをそのまま転送
        },
      },
    },
  },

  // 開発サーバーの設定
  server: {
    port: 4321,
    host: true, // 0.0.0.0でリッスン（全インターフェース）
  },
});
