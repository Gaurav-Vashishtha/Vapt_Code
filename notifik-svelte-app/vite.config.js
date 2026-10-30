import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import { visualizer } from "rollup-plugin-visualizer";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig(({ mode }) => ({
  base: "/notifik-svelte-app/",
  plugins: [
    tailwindcss(),
    svelte({
      // svelte.config.js rewrites every `onX=` attribute to the legacy `on:x=`
      // directive on purpose, so this deprecation fires for the whole codebase.
      onwarn(warning, handler) {
        if (warning.code === "event_directive_deprecated") return;
        handler?.(warning);
      },
    }),
    visualizer({
      filename: path.resolve(__dirname, "stats.html"),
      open: false,
      gzipSize: true,
      brotliSize: true,
      template: "treemap"
    })
  ],

  build: {
    outDir: path.resolve(__dirname, "../public/notifik-svelte-app"),
    emptyOutDir: true,
    manifest: "manifest.json",
    minify: mode === "production" ? "terser" : false,
    terserOptions:
      mode === "production"
        ? {
            compress: {
              drop_console: true,
              drop_debugger: false,
              passes: 2,
              keep_fnames: false,
              keep_classnames: false,
            },
            format: { comments: false, semicolons: false },
            mangle: { toplevel: true },
          }
        : undefined,
    sourcemap: true,
    cssMinify: mode === "production",

    treeshake: {
      moduleSideEffects: "no-external",
      preset: "recommended",
      propertyReadSideEffects: true
    },

    rollupOptions: {
      input: path.resolve(__dirname, "src/main.js"),

      output: {
        inlineDynamicImports: true,
        entryFileNames: "notifik-svelte.[hash].js",
        assetFileNames: "assets/[name].[hash].[ext]",
      }
    },

    chunkSizeWarningLimit: 500
  },

  server: { port: 5173, strictPort: true }
}));
