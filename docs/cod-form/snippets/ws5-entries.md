# WS5 → WS4: build entries, i18n output and size limits

Owner of the target files: WS4 (`storefront/cod-form/build.mjs`, `size-limits.json`).

## 1. Entries — nothing to add

`build.mjs` already discovers every WS5 entry by convention (`src/core/index.js`, `src/chunks/*.{js,jsx}`, `src/i18n/*.json`). No manifest line is needed.

One chunk is not in the list of ARCHITECTURE.md G.1: `src/chunks/preview.js` → `codk-form-preview.js`. It holds the fixture session used by `core.preview(payload)` (H.6) so that this code is not in the core bundle. Add its budget:

```json
"codk-form-preview.js": 2048,
```

## 2. Locale chunks are over budget with the current build options (build exits 1)

With `build.mjs` as it is, every `codk-form-i18n-*.js` is 2.9–3.6 KB gz against the 2 560 B limit, for two reasons that have nothing to do with the texts:

- esbuild's `json` loader gives an entry point one named export per key, so each key name is emitted twice;
- esbuild escapes non-ASCII characters by default (`ا…`), which triples Arabic, Hindi and Urdu.

Add to `esmOptions()` in `build.mjs`:

```js
  charset: "utf8",                       // ES modules are always decoded as UTF-8
  plugins: [i18nDefaultOnlyPlugin(), moveMapsPlugin()],
```

and the plugin (the same one `scripts/build-ws5.mjs` uses):

```js
// A locale chunk only needs its default export; the json loader would add one named export per key.
function i18nDefaultOnlyPlugin() {
  return {
    name: "codkf-i18n-default-only",
    setup(b) {
      b.onLoad({ filter: /[\\/]src[\\/]i18n[\\/][^\\/]+\.json$/ }, (args) => ({
        contents: "export default " + JSON.stringify(JSON.parse(fs.readFileSync(args.path, "utf8"))) + ";",
        loader: "js",
      }));
    },
  };
}
```

Result (measured with `node scripts/build-ws5.mjs`): en 1 784, es 1 976, fr 2 013, sr 2 013, hu 2 170, ar 2 255, ur 2 291, hi 2 376 B gz — all under 2 560.

If the build must stay untouched, the alternative is `"codk-form-i18n-*.js": 3840` in `size-limits.json`. The files work either way; only the size check differs.
