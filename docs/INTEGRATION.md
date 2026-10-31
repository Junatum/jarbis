# SmartSafeHub integration contract

Confirmed against user-provided `luci-app-smartsafehub-develop(20261031-012234).zip`:

- UI: Preact / TypeScript, hash-based routes (`frontend/src/app/routes.ts`)
- RPC: existing LuCI JSON-RPC client (`frontend/src/api/rpc.ts`)
- Backend uses isolated rpcd ucode objects (e.g. `smartsafehub_guest`).
- ACL groups are declared at `root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json`.

**This scaffold intentionally does not modify SmartSafeHub sources or generate frontend bundles.**

Recommended subsequent integration patch (separate release, version bump, changelog, tests):

1. Add `#smart-home` route (`스마트홈` navigation).
2. Add `frontend/src/api/jarbis.ts` typed API adapter, using shared scheduler with low request priority for outside-system calls.
3. Add `SmartHomePage.tsx` with empty/not-installed/disabled states and `light_set` controls.
4. Extend *SmartSafeHub* ACL to grant `jarbis` read/status/list and write/light_set for authenticated sessions, subject to the existing root password checks and login model.
5. Add test/demo fixtures; do not generate or commit new frontend dist files.

Deploying the Jarbis package alone **does not** add a SmartSafeHub UI menu. Avoid installing separate LuCI root-entry hooks or replacing core SmartSafeHub RPC. Preserve `jarbis` RPC independently so package faults do not affect the router admin login.
