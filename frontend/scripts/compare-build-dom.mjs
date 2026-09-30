import { readdir, readFile } from "node:fs/promises";
import { basename, join, relative, resolve } from "node:path";

import { parse } from "parse5";

const [beforeArgument, afterArgument = "dist"] = process.argv.slice(2);
if (!beforeArgument) {
  console.error("Usage: npm run compare:dom -- <before-dist> [after-dist]");
  process.exit(2);
}

const beforeDirectory = resolve(beforeArgument);
const afterDirectory = resolve(afterArgument);

async function findHtmlFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = await Promise.all(
    entries.map(async (entry) => {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) return findHtmlFiles(path);
      return entry.isFile() && entry.name.endsWith(".html") ? [path] : [];
    })
  );
  return files.flat().sort();
}

function normalizeAssetReferences(value) {
  return value.replace(
    /\/_astro\/[^\s"'?]+?\.[A-Za-z0-9_-]{6,}(\.[A-Za-z0-9]+)(?=[?"'\s]|$)/g,
    "/_astro/$ASSET$1"
  );
}

function normalizeAuditedPhrasingElement(node, attributes) {
  const classes = new Set((attributes.class ?? "").split(/\s+/));
  const themeToggleElement = [
    "toggle-container",
    "icon-wrapper",
    "slider",
  ].some((className) => classes.has(className));
  const consoleStatusDot =
    node.parentNode?.tagName === "button" &&
    ["w-2", "h-2", "rounded-full"].every((className) => classes.has(className));

  if (themeToggleElement || consoleStatusDot) return "audited-phrasing-element";
  return node.tagName;
}

function canonicalize(node) {
  if (node.nodeName === "#comment") return null;
  if (node.nodeName === "#text") {
    const text = normalizeAssetReferences(
      node.value.replace(/\s+/g, " ").trim()
    );
    return text ? { text } : null;
  }
  if (node.nodeName === "#documentType") return { doctype: node.name };

  const attributes = Object.fromEntries(
    (node.attrs ?? [])
      .filter(
        ({ name }) =>
          !name.startsWith("data-astro-") &&
          !(node.tagName === "astro-island" && name === "uid")
      )
      .sort((left, right) => left.name.localeCompare(right.name))
      .map(({ name, value }) => [name, normalizeAssetReferences(value)])
  );
  if (node.tagName === "script" || node.tagName === "style") return null;
  if (
    node.tagName === "link" &&
    attributes.rel === "stylesheet" &&
    attributes.href?.startsWith("/_astro/")
  ) {
    return null;
  }
  const children = (node.childNodes ?? []).map(canonicalize).filter(Boolean);
  if (node.tagName) {
    return {
      tag: normalizeAuditedPhrasingElement(node, attributes),
      attributes,
      children,
    };
  }
  return { node: node.nodeName, children };
}

function firstDifferentLine(before, after) {
  const beforeLines = before.split("\n");
  const afterLines = after.split("\n");
  const length = Math.max(beforeLines.length, afterLines.length);
  for (let index = 0; index < length; index += 1) {
    if (beforeLines[index] !== afterLines[index]) return index;
  }
  return -1;
}

const beforeFiles = await findHtmlFiles(beforeDirectory);
const afterFiles = await findHtmlFiles(afterDirectory);
const beforeRelative = beforeFiles.map((file) =>
  relative(beforeDirectory, file)
);
const afterRelative = afterFiles.map((file) => relative(afterDirectory, file));

if (JSON.stringify(beforeRelative) !== JSON.stringify(afterRelative)) {
  console.error("Built page sets differ:");
  console.error(`before: ${beforeRelative.join(", ")}`);
  console.error(`after:  ${afterRelative.join(", ")}`);
  process.exit(1);
}

let differences = 0;
for (let index = 0; index < beforeFiles.length; index += 1) {
  const before = canonicalize(
    parse(await readFile(beforeFiles[index], "utf8"))
  );
  const after = canonicalize(parse(await readFile(afterFiles[index], "utf8")));
  const beforeJson = JSON.stringify(before, null, 2);
  const afterJson = JSON.stringify(after, null, 2);
  if (beforeJson === afterJson) continue;

  differences += 1;
  const line = firstDifferentLine(beforeJson, afterJson);
  const start = Math.max(0, line - 2);
  const end = line + 3;
  console.error(`DOM mismatch: ${beforeRelative[index]}`);
  console.error(`before (${basename(beforeDirectory)}):`);
  console.error(beforeJson.split("\n").slice(start, end).join("\n"));
  console.error(`after (${basename(afterDirectory)}):`);
  console.error(afterJson.split("\n").slice(start, end).join("\n"));
}

if (differences > 0) {
  console.error(
    `${differences} of ${beforeFiles.length} pages have structural DOM differences.`
  );
  process.exitCode = 1;
} else {
  console.log(
    `Compared ${beforeFiles.length} pages with normalized structural DOM equality.`
  );
}
