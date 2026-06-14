#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const infoPlistPath = "apps/macos/Supporting/Info.plist";
const entitlementsPath = "apps/macos/Supporting/TuneAVMac.entitlements";

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
  fail("Tune AV macOS should keep the ATS exception scoped to media streams only.");
}
if (ats.NSExceptionDomains && Object.keys(ats.NSExceptionDomains).length > 0) {
  fail("ATS domain exceptions must be reviewed before being checked in.");
}

const allowedEntitlementKeys = new Set([
  "com.apple.security.app-sandbox",
  "com.apple.security.network.client",
  "keychain-access-groups",
]);
for (const key of Object.keys(entitlements)) {
  if (!allowedEntitlementKeys.has(key)) {
    fail(`unexpected macOS entitlement: ${key}`);
  }
}

if (entitlements["com.apple.security.app-sandbox"] !== true) {
  fail("App Sandbox must stay enabled for Mac App Store distribution.");
}
if (entitlements["com.apple.security.network.client"] !== true) {
  fail("Network client entitlement is required for radio streams and Account AV calls.");
}

const keychainGroups = entitlements["keychain-access-groups"] ?? [];
if (
  !Array.isArray(keychainGroups) ||
  keychainGroups.length !== 1 ||
  keychainGroups[0] !== "$(ACCOUNTAV_KEYCHAIN_ACCESS_GROUP)"
) {
  fail("keychain-access-groups must be driven by ACCOUNTAV_KEYCHAIN_ACCESS_GROUP.");
}

if (
  !infoSource.includes("$(ACCOUNTAV_API_BASE_URL)") ||
  !infoSource.includes("$(ACCOUNTAV_PUBLISHABLE_KEY)") ||
  !infoSource.includes("$(ACCOUNTAV_KEYCHAIN_ACCESS_GROUP)")
) {
  fail("Account AV runtime values must remain build-setting substitutions, not literals.");
}

if (failures.length > 0) {
  console.error("macOS platform security check failed:");
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log("macOS platform security check passed.");
