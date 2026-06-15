#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const infoPlistPath = "apps/ios/TuneAV/App/Info.plist";
const entitlementsPath = "apps/ios/TuneAV/App/TuneAV.entitlements";

function readPlist(path) {
  const json = execFileSync("plutil", ["-convert", "json", "-o", "-", path], {
    encoding: "utf8",
  });
  return JSON.parse(json);
}

const failures = [];
const info = readPlist(infoPlistPath);
const entitlements = readPlist(entitlementsPath);
const infoSource = readFileSync(infoPlistPath, "utf8");

function fail(message) {
  failures.push(message);
}

const ats = info.NSAppTransportSecurity ?? {};
if (ats.NSAllowsArbitraryLoads === true) {
  fail("NSAllowsArbitraryLoads must stay disabled; use scoped ATS exceptions only.");
}
if (ats.NSAllowsArbitraryLoadsInWebContent === true) {
  fail("NSAllowsArbitraryLoadsInWebContent must stay disabled for embedded web content.");
}
if (ats.NSAllowsLocalNetworking === true) {
  fail("NSAllowsLocalNetworking must not be enabled in the checked-in release Info.plist.");
}
if (ats.NSAllowsArbitraryLoadsForMedia !== true) {
  fail("Tune AV should keep the ATS exception scoped to media streams only.");
}
if (ats.NSExceptionDomains && Object.keys(ats.NSExceptionDomains).length > 0) {
  fail("ATS domain exceptions must be reviewed before being checked in.");
}

const forbiddenUsageDescriptions = [
  "NSCameraUsageDescription",
  "NSMicrophoneUsageDescription",
  "NSLocationWhenInUseUsageDescription",
  "NSLocationAlwaysAndWhenInUseUsageDescription",
  "NSPhotoLibraryUsageDescription",
  "NSPhotoLibraryAddUsageDescription",
  "NSContactsUsageDescription",
  "NSCalendarsUsageDescription",
  "NSBluetoothAlwaysUsageDescription",
  "NSMotionUsageDescription",
];

for (const key of forbiddenUsageDescriptions) {
  if (Object.hasOwn(info, key)) {
    fail(`${key} is present but Tune AV does not need that permission.`);
  }
}

const backgroundModes = info.UIBackgroundModes ?? [];
const allowedBackgroundModes = new Set(["audio"]);
for (const mode of backgroundModes) {
  if (!allowedBackgroundModes.has(mode)) {
    fail(`unexpected UIBackgroundModes entry: ${mode}`);
  }
}
if (!backgroundModes.includes("audio")) {
  fail("UIBackgroundModes must include audio for background radio playback.");
}

const allowedEntitlementKeys = new Set([
  "com.apple.developer.applesignin",
  "keychain-access-groups",
]);
for (const key of Object.keys(entitlements)) {
  if (!allowedEntitlementKeys.has(key)) {
    fail(`unexpected iOS entitlement: ${key}`);
  }
}

const appleSignIn = entitlements["com.apple.developer.applesignin"] ?? [];
if (!Array.isArray(appleSignIn) || appleSignIn.length !== 1 || appleSignIn[0] !== "Default") {
  fail("Sign in with Apple entitlement must remain limited to Default.");
}

const keychainGroups = entitlements["keychain-access-groups"] ?? [];
if (
  !Array.isArray(keychainGroups) ||
  keychainGroups.length !== 1 ||
  keychainGroups[0] !== "$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)"
) {
  fail("keychain-access-groups must stay scoped to the app bundle identifier.");
}

if (
  !infoSource.includes("$(ACCOUNTAV_API_BASE_URL)") ||
  !infoSource.includes("$(TUNEAV_API_BASE_URL)") ||
  !infoSource.includes("$(ACCOUNTAV_PUBLISHABLE_KEY)")
) {
  fail("Account AV runtime values must remain build-setting substitutions, not literals.");
}

if (failures.length > 0) {
  console.error("iOS platform security check failed:");
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log("iOS platform security check passed.");
