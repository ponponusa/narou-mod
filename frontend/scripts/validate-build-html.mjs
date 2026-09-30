import { readdir, readFile } from "node:fs/promises";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";

import { HtmlValidate } from "html-validate";

const buildDirectory = fileURLToPath(new URL("../dist/", import.meta.url));
const validator = new HtmlValidate({
  extends: ["html-validate:recommended"],
  rules: {
    "attribute-boolean-style": "off",
    "no-implicit-button-type": "off",
    "no-inline-style": "off",
    "prefer-native-element": "off",
    "text-content": "off",
    "void-style": "off",
    "wcag/h30": "off",
  },
});

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

function maskFrameworkBodyStyles(html) {
  const headEnd = html.indexOf("</head>");
  if (headEnd === -1) return html;

  const body = html.slice(headEnd + "</head>".length);
  const maskedBody = body.replace(
    /<style(?:\s[^>]*)?>[\s\S]*?<\/style>/gi,
    (style) => {
      const isFrameworkStyle = /astro-(?:island|slot|static-slot)|svelte-/.test(
        style
      );
      return isFrameworkStyle ? style.replace(/[^\n]/g, " ") : style;
    }
  );
  return html.slice(0, headEnd + "</head>".length) + maskedBody;
}

const files = await findHtmlFiles(buildDirectory);
if (files.length === 0) {
  throw new Error("No built HTML found. Run `npm run build` first.");
}

let errorCount = 0;
for (const file of files) {
  const html = await readFile(file, "utf8");
  const report = await validator.validateString(
    maskFrameworkBodyStyles(html),
    file
  );
  for (const result of report.results) {
    for (const message of result.messages) {
      if (message.severity !== 2) continue;
      errorCount += 1;
      const displayPath = relative(buildDirectory, file);
      console.error(
        `${displayPath}:${message.line}:${message.column} ${message.ruleId}: ${message.message}`
      );
    }
  }
}

if (errorCount > 0) {
  console.error(`Built HTML validation failed with ${errorCount} error(s).`);
  process.exitCode = 1;
} else {
  console.log(`Validated ${files.length} built HTML pages.`);
}
