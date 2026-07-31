# Subscription Access Contract

Tune AV uses RevenueCat to perform App Store purchase and restore operations,
while Apps AV remains the authority for visible Pro access on iOS and macOS.

After a purchase or restore, the client first requires the exact active
RevenueCat entitlement identifier `pro`. A successful callback or transaction
without that entitlement does not start backend reconciliation and never grants
local Pro.

- An inactive purchase tells the user not to purchase again and points to
  Restore Purchases.
- An inactive restore reports that no active Tune AV Pro subscription was found
  for the current App Store account and returns to the subscribe path.
- A provider or network failure remains a separate error.
- An active `pro` result starts a bounded Apps AV refresh. If Apps AV has not
  caught up when retries finish, the pending state ends with a purchase-,
  restore-, or code-specific delayed message. It never spins indefinitely.
- A later Apps AV Pro response clears the delayed state and unlocks Pro. An
  account change cancels reconciliation for the previous account.

Every user-visible branch is localized in English, Spanish, Catalan, French,
and German. Regression coverage includes exact entitlement matching, inactive
operations, bounded retries, eventual Apps AV Pro, and both Apple clients.
