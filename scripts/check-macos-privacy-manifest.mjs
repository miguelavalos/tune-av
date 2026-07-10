#!/usr/bin/env node
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { validateTuneAVPrivacyManifest } from "./check-apple-privacy-manifest.mjs";

const repoRoot = resolve(import.meta.dirname, "..");
const sourceManifestPath = resolve(repoRoot, "apps/macos/Supporting/PrivacyInfo.xcprivacy");
const projectYAMLPath = resolve(repoRoot, "apps/macos/project.yml");
const projectFilePath = resolve(repoRoot, "apps/macos/TuneAVMac.xcodeproj/project.pbxproj");
const failures = [];
let appPath = null;

for (let index = 2; index < process.argv.length; index += 1) {
  const argument = process.argv[index];
  if (argument === "--app") {
    appPath = process.argv[index + 1] ? resolve(process.argv[index + 1]) : null;
    index += 1;
    if (!appPath) failures.push("--app requires a path to Tune AV.app");
  } else {
    failures.push(`unknown argument: ${argument}`);
  }
}

function fail(message) {
  failures.push(message);
}

failures.push(...validateTuneAVPrivacyManifest(sourceManifestPath, "source manifest"));

for (const [path, label] of [
  [projectYAMLPath, "project.yml"],
  [projectFilePath, "generated Xcode project"],
]) {
  if (!existsSync(path) || !readFileSync(path, "utf8").includes("PrivacyInfo.xcprivacy")) {
    fail(`${label} does not include PrivacyInfo.xcprivacy in the macOS target`);
  }
}

if (appPath) {
  if (!existsSync(appPath)) {
    fail(`app bundle does not exist: ${appPath}`);
  } else {
    const bundledManifestPath = resolve(appPath, "Contents/Resources/PrivacyInfo.xcprivacy");
    failures.push(...validateTuneAVPrivacyManifest(bundledManifestPath, "bundled manifest"));
  }
}

if (failures.length > 0) {
  console.error("macOS privacy manifest check failed:");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(appPath
  ? "macOS source and bundled privacy manifest checks passed."
  : "macOS source privacy manifest check passed.");
