import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

// Served by Rails at /codk-ops (CodkOpsController) from ./build.
// `npm run dev` proxies the API to a local Rails server (default :3000).
export default defineConfig({
  base: '/codk-ops/',
  plugins: [svelte()],
  build: { outDir: 'build', emptyOutDir: true, chunkSizeWarningLimit: 900 },
  server: {
    proxy: { '/codk-ops/api': process.env.OPS_API_ORIGIN || 'http://localhost:3000' }
  }
});
