# Universal Links

Gus claims `applinks:gus.ericslutz.dev` through the app entitlements. The domain must
serve the associated-domains file over HTTPS with no redirects at one of Apple's accepted
paths:

- `https://gus.ericslutz.dev/.well-known/apple-app-site-association`
- `https://gus.ericslutz.dev/apple-app-site-association`

The response should use `application/json` and no `.json` filename extension.

The source payload lives in `Documentation/AppStore/apple-app-site-association.json` and
must include these app routes:

- `/item/*` opens the item detail surface.
- `/play/*` starts playback through Gus's existing content-link router.

Shared with You v1 relies on these Universal Links. `gus://item/<id>` and
`gus://play/<id>` remain supported for internal routing, Top Shelf, Handoff, Spotlight,
Siri/App Intents, screenshot automation, and development links.
