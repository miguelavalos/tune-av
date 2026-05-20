#!/usr/bin/env node

import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const workflowDir = ".github/workflows";
const workflowFiles = readdirSync(workflowDir)
  .filter((file) => file.endsWith(".yml") || file.endsWith(".yaml"))
  .sort();

const failures = [];

for (const file of workflowFiles) {
  const path = join(workflowDir, file);
  const lines = readFileSync(path, "utf8").split(/\r?\n/);
  const hasTopLevelPermissions = lines.some((line) => /^permissions:\s*$/.test(line));

  if (!hasTopLevelPermissions) {
    failures.push(`${path}: missing top-level permissions block`);
  }
}

if (failures.length > 0) {
  console.error(failures.join("\n"));
  console.error("Every GitHub Actions workflow must declare explicit top-level permissions.");
  process.exit(1);
}

console.log("GitHub Actions permissions check passed.");
