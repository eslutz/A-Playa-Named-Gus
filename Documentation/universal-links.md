# Universal Links

Gus claims applinks:gus.ericslutz.dev through its app entitlements. Universal
Links route into the app; viewing details or playing content still requires an
active authorized account and provider/item resolution.

## Own and synchronize the payload

The app-side [association payload](AppStore/apple-app-site-association.json)
is the reference checked by Gus tests. The sibling Gus.website checkout serves
extensionless copies at src/.well-known/apple-app-site-association and
src/apple-app-site-association. Keep the copies synchronized when the team ID,
bundle ID, or supported routes change. The website test aasa.test.mjs checks
the two published output paths and payload; that test does not prove deployment.

- /item/* opens the item detail.
- /play/* requests playback through the authenticated router.
- Internal gus://item and gus://play routes also support Top Shelf, Handoff,
  Spotlight, Siri/App Intents and fixture automation. Shared with You uses
  Universal Links.

## Verify a deployment

When verifying an actual release, check the HTTPS GET response at each deployed
route without following redirects. Require HTTP 200, application/json, the
extensionless path and exact payload, then verify signed entitlements and native
detail/play routing on an authorized device. A local source comparison or build
does not verify an Apple association cache, signed installation, or live host.

```sh
curl -sS -D - https://gus.ericslutz.dev/.well-known/apple-app-site-association
curl -sS -D - https://gus.ericslutz.dev/apple-app-site-association
```
