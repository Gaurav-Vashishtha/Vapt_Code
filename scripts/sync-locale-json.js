/* eslint-disable no-console */
/**
 * Sync `config/localeJson/en.json` keys into other locale JSON files.
 *
 * - Adds missing keys using English as fallback value.
 * - Never overwrites existing translations.
 * - Recurses through nested objects.
 *
 * Usage:
 *   node scripts/sync-locale-json.js --check   # prints what would change, exits non-zero if changes needed
 *   node scripts/sync-locale-json.js          # updates files in place
 */
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const LOCALES_DIR = path.join(ROOT, "config", "localeJson");
const EN_PATH = path.join(LOCALES_DIR, "en.json");

function isPlainObject(v) {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}

function mergeMissing(base, target) {
  // Returns { merged, changed, missingCount }
  let changed = false;
  let missingCount = 0;

  // If target is not an object but base is, replace target only if it's undefined.
  if (target === undefined) {
    return { merged: base, changed: true, missingCount: 1 };
  }

  // Arrays: if missing, copy base; otherwise keep target (don't attempt element merge).
  if (Array.isArray(base)) {
    return { merged: target, changed: false, missingCount: 0 };
  }

  // Non-objects: keep target if present; only fill when target is undefined (handled above).
  if (!isPlainObject(base)) {
    return { merged: target, changed: false, missingCount: 0 };
  }

  // base is a plain object.
  const out = isPlainObject(target) ? { ...target } : {};

  for (const key of Object.keys(base)) {
    if (!(key in out)) {
      out[key] = base[key];
      changed = true;
      missingCount += 1;
      continue;
    }

    const b = base[key];
    const t = out[key];
    if (isPlainObject(b)) {
      const r = mergeMissing(b, t);
      if (r.changed) changed = true;
      missingCount += r.missingCount;
      out[key] = r.merged;
    }
  }

  return { merged: out, changed, missingCount };
}

function stableStringify(obj) {
  // Preserve insertion order as created by mergeMissing (existing keys first, then missing keys).
  return JSON.stringify(obj, null, 2) + "\n";
}

function readJson(filePath) {
  const raw = fs.readFileSync(filePath, "utf8");
  return JSON.parse(raw);
}

function listLocaleFiles() {
  return fs
    .readdirSync(LOCALES_DIR)
    .filter((f) => f.endsWith(".json"))
    .map((f) => path.join(LOCALES_DIR, f));
}

function main() {
  const args = new Set(process.argv.slice(2));
  const check = args.has("--check") || args.has("-c");

  const en = readJson(EN_PATH);
  const files = listLocaleFiles().filter((p) => path.basename(p) !== "en.json");

  let totalMissing = 0;
  const changedFiles = [];

  for (const filePath of files) {
    const current = readJson(filePath);
    const { merged, changed, missingCount } = mergeMissing(en, current);

    totalMissing += missingCount;
    if (!changed) continue;

    changedFiles.push({ filePath, missingCount });
    if (!check) {
      fs.writeFileSync(filePath, stableStringify(merged), "utf8");
    }
  }

  if (changedFiles.length === 0) {
    console.log("✅ Locale JSON already in sync (no missing keys).");
    process.exit(0);
  }

  for (const { filePath, missingCount } of changedFiles) {
    console.log(`${path.relative(ROOT, filePath)}: +${missingCount} key(s)`);
  }

  if (check) {
    console.error(
      `\n❌ Missing keys found (${totalMissing} total). Run without --check to apply updates.`,
    );
    process.exit(2);
  } else {
    console.log(`\n✅ Synced locales. Added ${totalMissing} key(s) total.`);
  }
}

main();

