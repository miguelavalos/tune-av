#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";

const requiredProductInteractionPurposes = [
  "NSPrivacyCollectedDataTypePurposeAppFunctionality",
  "NSPrivacyCollectedDataTypePurposeAnalytics",
];

export function validateTuneAVPrivacyManifest(path, label = path) {
  const failures = [];

  if (!existsSync(path)) {
    return [`${label} is missing: ${path}`];
  }

  let manifest;
  try {
    const json = execFileSync("plutil", ["-convert", "json", "-o", "-", path], {
      encoding: "utf8",
    });
    manifest = JSON.parse(json);
  } catch {
    return [`${label} is not a valid plist: ${path}`];
  }

  if (manifest.NSPrivacyTracking !== false) {
    failures.push(`${label} must declare NSPrivacyTracking=false`);
  }
  if (!Array.isArray(manifest.NSPrivacyTrackingDomains) || manifest.NSPrivacyTrackingDomains.length !== 0) {
    failures.push(`${label} must declare an empty NSPrivacyTrackingDomains array`);
  }

  const accessedAPIs = Array.isArray(manifest.NSPrivacyAccessedAPITypes)
    ? manifest.NSPrivacyAccessedAPITypes
    : [];
  const userDefaults = accessedAPIs.find(
    (entry) => entry.NSPrivacyAccessedAPIType === "NSPrivacyAccessedAPICategoryUserDefaults",
  );
  if (!userDefaults) {
    failures.push(`${label} must declare UserDefaults accessed API usage`);
  } else if (
    !Array.isArray(userDefaults.NSPrivacyAccessedAPITypeReasons) ||
    !userDefaults.NSPrivacyAccessedAPITypeReasons.includes("CA92.1")
  ) {
    failures.push(`${label} must declare UserDefaults reason CA92.1`);
  }

  const collectedData = Array.isArray(manifest.NSPrivacyCollectedDataTypes)
    ? manifest.NSPrivacyCollectedDataTypes
    : [];
  const productInteraction = collectedData.find(
    (entry) => entry.NSPrivacyCollectedDataType === "NSPrivacyCollectedDataTypeProductInteraction",
  );
  if (!productInteraction) {
    failures.push(`${label} must declare collected Product Interaction data`);
    return failures;
  }

  if (productInteraction.NSPrivacyCollectedDataTypeLinked !== true) {
    failures.push(`${label} Product Interaction data must be declared as linked to the user`);
  }
  if (productInteraction.NSPrivacyCollectedDataTypeTracking !== false) {
    failures.push(`${label} Product Interaction data must be declared as not used for tracking`);
  }

  const purposes = Array.isArray(productInteraction.NSPrivacyCollectedDataTypePurposes)
    ? productInteraction.NSPrivacyCollectedDataTypePurposes
    : [];
  for (const purpose of requiredProductInteractionPurposes) {
    if (!purposes.includes(purpose)) {
      failures.push(`${label} Product Interaction data must declare ${purpose}`);
    }
  }

  return failures;
}

const invokedPath = process.argv[1] ? resolve(process.argv[1]) : null;
const isMain = invokedPath === fileURLToPath(import.meta.url);

if (isMain) {
  const manifestPaths = process.argv.slice(2).map((path) => resolve(path));
  if (manifestPaths.length === 0) {
    console.error("Usage: node scripts/check-apple-privacy-manifest.mjs <PrivacyInfo.xcprivacy> [...]");
    process.exit(2);
  }

  const failures = manifestPaths.flatMap((path) => validateTuneAVPrivacyManifest(path));
  if (failures.length > 0) {
    console.error("Apple privacy manifest check failed:");
    for (const failure of failures) console.error(`- ${failure}`);
    process.exit(1);
  }

  console.log(`Apple privacy manifest check passed for ${manifestPaths.length} manifest(s).`);
}
