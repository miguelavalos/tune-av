#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const sourceRoots = ["apps/ios/TuneAV", "shared/apple"];
const excludedPathFragments = [
  "/Tools/",
  "/Preview Content/",
];

const forbiddenPatterns = [
  {
    pattern: /\bsk_(?:live|test)_[A-Za-z0-9_]+/g,
    reason: "secret key literal found in iOS source",
  },
  {
    pattern: /\bpk_(?:live|test)_[A-Za-z0-9_]{8,}/g,
    reason: "Account AV publishable key must come from generated xcconfig, not source",
  },
  {
    pattern: /\bappl_[A-Za-z0-9_]{8,}/g,
    reason: "RevenueCat public app key must come from generated xcconfig, not source",
  },
  {
    pattern: /\b(?:eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,})\b/g,
    reason: "JWT-like token literal found in iOS source",
  },
  {
    pattern: /\b(?:Bearer|Basic)\s+[A-Za-z0-9._~+/-]+=*/g,
    reason: "authorization credential literal found in iOS source",
  },
  {
    pattern: /https?:\/\/api-account-av(?:-preview)?\.avalsys\.com\b/g,
    reason: "Account AV API endpoint must come from generated xcconfig, not source",
  },
  {
    pattern: /https?:\/\/account-av-preview\.avalsys\.com\b/g,
    reason: "preview Account AV management URL must not be compiled into production iOS source",
  },
  {
    pattern: /https?:\/\/(?:127\.0\.0\.1|localhost|\[?::1\]?)(?::8788)?\b/g,
    reason: "local backend endpoint must not be compiled into iOS source",
  },
  {
    pattern: /\bACCOUNTAV_SUBSCRIPTION_SYNC_TOKEN\b/g,
    reason: "backend subscription sync token name must not appear in iOS source",
  },
  {
    pattern: /\b(?:CLERK_SECRET_KEY|REVENUECAT_SECRET|STRIPE_SECRET_KEY)\b/g,
    reason: "server-side secret name must not appear in iOS source",
  },
];

function trackedSwiftFiles() {
  const output = execFileSync("git", ["ls-files", "-z", "--", ...sourceRoots], {
    encoding: "buffer",
  });

  return output
    .toString("utf8")
    .split("\0")
    .filter((filePath) => filePath.endsWith(".swift"))
    .filter((filePath) => !excludedPathFragments.some((fragment) => filePath.includes(fragment)));
}

function lineNumberForOffset(source, offset) {
  return source.slice(0, offset).split("\n").length;
}

const violations = [];

for (const filePath of trackedSwiftFiles()) {
  const source = readFileSync(filePath, "utf8");

  for (const rule of forbiddenPatterns) {
    rule.pattern.lastIndex = 0;
    let match;

    while ((match = rule.pattern.exec(source)) !== null) {
      violations.push({
        filePath,
        line: lineNumberForOffset(source, match.index),
        reason: rule.reason,
      });
    }
  }
}

if (violations.length > 0) {
  console.error("iOS hardcoded sensitive config check failed:");
  for (const violation of violations) {
    console.error(`${violation.filePath}:${violation.line} ${violation.reason}`);
  }
  process.exit(1);
}

console.log("iOS hardcoded sensitive config check passed.");
