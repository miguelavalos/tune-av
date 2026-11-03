#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const infoPlistPath = "apps/ios/TuneAV/App/Info.plist";
const entitlementsPath = "apps/ios/TuneAV/App/TuneAV.entitlements";
const widgetsInfoPlistPath = "apps/ios/TuneAVWidgets/Info.plist";
const widgetsEntitlementsPath = "apps/ios/TuneAVWidgets/TuneAVWidgets.entitlements";
const widgetsPrivacyManifestPath = "apps/ios/TuneAVWidgets/PrivacyInfo.xcprivacy";
const liveActivitySwitchPath = "apps/ios/WidgetShared/TuneAVLiveActivityIntents.swift";
const appGroupValue = "group.$(TUNEAV_BUNDLE_IDENTIFIER)";

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
  "com.apple.security.application-groups",
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

function checkAppGroup(label, value) {
  if (!Array.isArray(value) || value.length !== 1 || value[0] !== appGroupValue) {
    fail(`${label} application group must stay limited to ${appGroupValue}.`);
  }
}

checkAppGroup("iOS app", entitlements["com.apple.security.application-groups"]);

// The Info.plist key follows the one Live Activity switch: required while the activity is on,
// absent while it is off so iOS Settings shows no Live Activities toggle for Tune AV.
const liveActivitySwitch = readFileSync(liveActivitySwitchPath, "utf8").match(
  /enum TuneAVLiveActivityFeature \{\s*static let isEnabled = (true|false)\b/,
);
if (!liveActivitySwitch) {
  fail(`TuneAVLiveActivityFeature.isEnabled must be a literal true or false in ${liveActivitySwitchPath}.`);
} else if (liveActivitySwitch[1] === "true" && info.NSSupportsLiveActivities !== true) {
  fail("NSSupportsLiveActivities must be enabled while the now playing Live Activity is on.");
} else if (liveActivitySwitch[1] === "false" && Object.hasOwn(info, "NSSupportsLiveActivities")) {
  fail("NSSupportsLiveActivities must be absent while the Live Activity is off (TuneAVLiveActivityFeature.isEnabled).");
}
if (Object.hasOwn(info, "NSSupportsLiveActivitiesFrequentUpdates")) {
  fail("NSSupportsLiveActivitiesFrequentUpdates is not needed: Live Activity updates are local and throttled.");
}
if (info.TuneAVAppGroupIdentifier !== appGroupValue) {
  fail(`TuneAVAppGroupIdentifier must be ${appGroupValue} in the app Info.plist.`);
}

const widgetsInfo = readPlist(widgetsInfoPlistPath);
const widgetsEntitlements = readPlist(widgetsEntitlementsPath);
readPlist(widgetsPrivacyManifestPath);

for (const key of Object.keys(widgetsEntitlements)) {
  if (key !== "com.apple.security.application-groups") {
    fail(`unexpected TuneAVWidgets entitlement: ${key}`);
  }
}
checkAppGroup("TuneAVWidgets", widgetsEntitlements["com.apple.security.application-groups"]);

if (widgetsInfo.NSExtension?.NSExtensionPointIdentifier !== "com.apple.widgetkit-extension") {
  fail("TuneAVWidgets must stay a WidgetKit extension.");
}
if (widgetsInfo.TuneAVAppGroupIdentifier !== appGroupValue) {
  fail(`TuneAVAppGroupIdentifier must be ${appGroupValue} in the TuneAVWidgets Info.plist.`);
}
for (const key of ["CFBundleShortVersionString", "CFBundleVersion"]) {
  if (widgetsInfo[key] !== info[key]) {
    fail(`TuneAVWidgets ${key} (${widgetsInfo[key]}) must match the app (${info[key]}).`);
  }
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
