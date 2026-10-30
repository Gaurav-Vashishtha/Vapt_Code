import fs from "node:fs";
import path from "node:path";

function isPlainObject(value) {
  return (
    value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    Object.prototype.toString.call(value) === "[object Object]"
  );
}

function mergeMissingKeys(source, target) {
  let added = 0;

  for (const [k, sourceVal] of Object.entries(source)) {
    if (!(k in target)) {
      target[k] = sourceVal;
      added += 1;
      continue;
    }

    const targetVal = target[k];
    if (isPlainObject(sourceVal) && isPlainObject(targetVal)) {
      const child = mergeMissingKeys(sourceVal, targetVal);
      added += child;
    }
  }

  return added;
}

function readJson(filePath) {
  const raw = fs.readFileSync(filePath, "utf8");
  return JSON.parse(raw);
}

function writeJson(filePath, data) {
  const json = JSON.stringify(data, null, 2) + "\n";
  fs.writeFileSync(filePath, json, "utf8");
}

const localeDir = path.resolve(process.cwd(), "config/localeJson");
const sourcePath = path.join(localeDir, "en.json");
const source = readJson(sourcePath);

const files = fs
  .readdirSync(localeDir)
  .filter((f) => f.endsWith(".json") && f !== "en.json")
  .sort();

let totalAdded = 0;
for (const file of files) {
  const fullPath = path.join(localeDir, file);
  const target = readJson(fullPath);
  const added = mergeMissingKeys(source, target);
  if (added > 0) writeJson(fullPath, target);
  totalAdded += added;
  process.stdout.write(`${file}: +${added} keys\n`);
}

process.stdout.write(`Total added: ${totalAdded} keys\n`);

