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
  let inJobs = false;
  let currentJob = null;

  const finishJob = () => {
    if (currentJob && !currentJob.hasTimeout) {
      failures.push(`${path}:${currentJob.line}: job '${currentJob.name}' is missing timeout-minutes`);
    }
  };

  lines.forEach((line, index) => {
    if (/^jobs:\s*$/.test(line)) {
      inJobs = true;
      finishJob();
      currentJob = null;
      return;
    }

    if (inJobs && /^[A-Za-z_][A-Za-z0-9_-]*:\s*$/.test(line)) {
      inJobs = false;
      finishJob();
      currentJob = null;
      return;
    }

    if (!inJobs) {
      return;
    }

    const jobMatch = line.match(/^  ([A-Za-z0-9_-]+):\s*$/);
    if (jobMatch) {
      finishJob();
      currentJob = {
        name: jobMatch[1],
        line: index + 1,
        hasTimeout: false,
      };
      return;
    }

    if (currentJob && /^    timeout-minutes:\s*[1-9][0-9]*\s*$/.test(line)) {
      currentJob.hasTimeout = true;
    }
  });

  finishJob();
}

if (failures.length > 0) {
  console.error(failures.join("\n"));
  console.error("Every GitHub Actions job must define timeout-minutes.");
  process.exit(1);
}

console.log("GitHub Actions timeout check passed.");
