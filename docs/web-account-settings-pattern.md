# Tune AV Web Account And Settings Pattern

Tune AV follows the shared Apps AV web product app pattern documented in
`public/apps-av/docs/web-product-app-patterns.md`.

## Account

`/account` uses the shared `@avalsys/apps-av-web` account/settings primitives in
the standard order:

1. Account session identity, email, and plan/access summary.
2. Tune AV Pro benefits and manage/upgrade action.
3. Cloud sync state when the account capability is available.
4. Account safety and deletion entry point.

Tune-specific state stays in `useTune()`. The shared package owns the visual
section, row, button, Pro, sync, and account-safety grammar.

## Settings

`/settings` uses the standard order:

1. App preferences: language and appearance.
2. Tune preferences: country, discovery mode, and external search engine.
3. On this device: local station/listening data and browser storage cleanup.
4. Help and legal links.

## Assistant

Avi is exposed through the shared app shell assistant slot and the `/avi` route.
Tune AV should not add a fixed bottom assistant button on web.

## Import Rule

Product routes import reusable primitives from the public package entry point:

```ts
import { SettingsProfileScaffold } from "@avalsys/apps-av-web";
```

Do not import product UI from `@avalsys/apps-av-web/src/...`; anything reused by
Tune AV and another product should be exported by `@avalsys/apps-av-web`.
