# Shadowspore website

The production site stays on the existing Firebase Hosting project `shadowspore`.
Source: `public/index.html`, `public/site.css`, `public/site.js`, `public/account.mjs`.
Original game screenshots and locally hosted Alegreya fonts supply the visual identity.

## Preview and verification

```powershell
python firebase/preview.py
node --test firebase/tests/account.test.mjs
```

Preview: http://127.0.0.1:4180. The helper sets the `.mjs` MIME type correctly on Windows.

To exercise the player view without real credentials:

```powershell
python firebase/preview.py --port 4181 --account-fixture
```

Only this explicit test server injects `tests/account-fixture.js`. Log in with any syntactically valid email and a password of at least 8 characters. The account is visibly named `Vorschau · Ellie`; no requests reach the game server. `?scenario=empty` exercises a new account; `?scenario=partial` exercises unavailable friends. These test files are outside `public/` and cannot be included by the hosting deployment.

## Account contract

- Fixed `https://s.shadowspore.com` origin and existing public launcher client key. No query-parameter endpoint overrides.
- Login: Nakama email auth, `create=false`.
- Signup: `create=true`, `vars.license_key` passed to the existing hook.
- License redemption: existing-account auth, then `redeem_license_key` RPC.
- Profile and friends: `get_my_profile` and `list_friends` RPCs, using Nakama's JSON-string payload envelope.
- World: read only `saves/world_meta` for the authenticated profile's user ID. No save changes or bulk world downloads.
- Only the access token is kept in sessionStorage for this tab. No password or refresh token is stored. Expiry and HTTP 401 return to sign-in. Logout clears local state immediately and attempts server-side invalidation of this token; launcher sessions are unaffected.
- Friend data is a snapshot refreshed with the button; it is not a realtime connection.
- Server-provided strings are rendered as text; avatars are mapped to the two local launcher assets.

## Deployment

```powershell
cd firebase
firebase deploy --only hosting --project shadowspore
```

Hosting also serves the launcher installer and game updates. Before deployment, preserve all existing files under `public/downloads` and `public/updates`. The pre-existing live manifest currently advertises version 0.1.0 with an empty SHA-256 and size 0; the website redesign does not change this release pipeline issue.

The installer checksum element retains the exact `installer-sha256` markup consumed by `tools/build_release.ps1`.
Firebase serves modules with an explicit JavaScript MIME type and HTML/JS/CSS with revalidation. CSP permits only local scripts/assets and the existing game API. Godot `.import` metadata is excluded.

Verified: desktop, 390px and 320px layouts; day/night; atlas selection and image dialog; signup/redeem UI; fixture login, reload/restore, logout, empty data and partial failure; 10 REST-contract tests. Production CORS preflight accepts the website origin. Successful sign-in with a real account and an actual license activation still require the owner's credentials/license; no production accounts were created during QA.
