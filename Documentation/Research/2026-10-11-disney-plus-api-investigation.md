# Disney+ direct integration investigation

Date: 2026-10-11. Scope: catalog search, personal watch progress, and episode links.

Archived on 2026-10-13 as dated research. Endpoint and source observations below
describe the October 11 investigation; they have not been revalidated here.
No Disney+ subscriber integration is claimed by the subsequent Jellyfin/TV release.
See the [reconciled plan](../Plans/2026-10-11-disney-plus-playlists-next-up.md)
for implemented scope and remaining Disney+ work.

## Finding

A Gus-owned Disney+ adapter is technically plausible without Younify. Evidence exists
for all three requested capabilities, but subscriber operations remain untested.
The available evidence describes internal client interfaces and a separate partner
catalog feed, not a public, self-service subscriber developer API.

Younify support does not establish equivalent developer access: its privacy policy
describes accessing linked services through session tokens or cookies. That explains
a possible integration mechanism without proving the details of its Disney+ connector.

## Official access

- Disney's public Partner Program promotes subscriptions through referral links and
  marketing assets. It does not document subscriber API access.
- Disney Streaming publishes a partner metadata-feed specification. It covers movies,
  series, seasons, episodes, artwork, availability restrictions/windows, access tiers,
  identifiers, deletion markers, and playback/detail links.
- With feed access, Gus could index metadata for its own catalog search. The feed does
  not document subscriber progress or account authorization.
- No public Gus-app registration, delegated Disney+ subscriber scopes, or documented
  third-party watch-progress API was found. Private commercial access may exist;
  eligibility, cost, and onboarding remain unknown.

## Direct technical evidence

Inspected the maintainer's SlyGuy Disney+ package **0.20.33**, added to its GitHub mirror
on **2026-07-09**, at commit `af3b379254804aa9602b81ce793f6f109607cec1`.
Its code was inspected as a reference and was not executed or copied into Gus.

| Capability | Source evidence | Implication for Gus |
|---|---|---|
| Search | `api.py:451`, `search(query)` | Search a profile's available Disney+ catalog |
| Series/seasons/episodes | `page`, `set`, `season` | Browse a show and select individual episodes |
| Progress | `api.py:402`, `userstates(pids)`; `plugin.py:597`, `_add_progress` | Read percentage completed and, when returned, remaining seconds |
| Continue Watching | `plugin.py:96`, `continue_watching` | Read the provider's paginated Continue Watching set |
| Watchlist | `plugin.py:103`, `watchlist` | Import saved titles |
| Content resolution | `api.py:413`, `deeplink` | Resolve provider content references; validate external episode URLs separately |
| Profile context | `account`, `switch_profile`, `_endpoint` | Scope data by profile, country, language, maturity settings, and entitlements |

Authentication code includes password, OTP, device pairing, token refresh, and profile
selection. It uses an existing client identity and Android TV conventions. This is
evidence of a custom client path, not evidence that Disney has registered Gus as a
third-party application. A native Swift implementation would need its own validated
authentication/session strategy.

## Live checks

An unauthenticated GET of the client configuration referenced by the inspected package
returned **HTTP 200**. It listed these current endpoint templates at
`disney.api.edge.bamgrid.com`:

| Method | Template | Operation |
|---|---|---|
| GET | `/explore/{version}/search` | Search |
| GET | `/explore/{version}/page/{pageId}` | Item/show detail |
| GET | `/explore/{version}/set/{setId}` | Catalog/personalized set |
| GET | `/explore/{version}/season/{seasonId}` | Episodes |
| POST | `/explore/{version}/userState` | State for specified content IDs |
| GET | `/explore/{version}/deeplink` | Content-reference resolution |
| GET | `/explore/{version}/upNext` | Next-content lookup |
| POST | `/v1/public/graphql` | Account/authentication orchestration |

One unauthenticated search for `Halloween` returned **HTTP 401**. Configuration
availability therefore does not establish anonymous catalog access. The word
`public` in a route name does not establish third-party developer authorization.

No account login, device registration, token exchange, subscriber request, or
watch-state mutation was performed. Authenticated search, freshness of progress,
cross-profile isolation, and device link behavior remain unverified.

## Support boundaries

- Progress for known titles and Continue Watching have source evidence. A complete
  lifetime watch-history export with accurate watched dates has not been established.
- Provider catalog search is not necessarily a complete catalog export or a search
  over episode titles. A Halloween-episode flow should also browse seasons/episodes.
- Preserve Disney identifiers and returned links; do not assume TMDB or Jellyfin IDs
  can be substituted into Disney URLs. Check region, profile restrictions, and access.
- Own Gus watchlists/collections can remain local. Reading progress is sufficient for
  the requested integration; progress writes are a separate capability.
- The key proof still needed is an authenticated, read-only session that returns
  search results, episode metadata, and progress for one selected profile, followed
  by testing an episode link on each intended playback platform.

## Sources

- [Disney+ Partner Program](https://www.disneyplus.com/welcome/partner-program)
- [Disney Streaming metadata-feed specification](https://specs.disneystreaming.com/media-metadata-feed/spec.html)
- [SlyGuy Disney+ package at inspected commit](https://github.com/matthuisman/slyguy.addons/tree/af3b379254804aa9602b81ce793f6f109607cec1/slyguy.disney.plus)
- [Younify privacy policy](https://www.younify.tv/privacy/)

Package SHA-256: `c354c91d3b3d62f172b64eeb2e75bfd6c7d8a3e4a7409e2916fed44cdea8e387`.
Temporary source/probe evidence: `gus-disney-research-_u59j28m` in the host's temporary
directory; contains sanitized endpoint/probe JSON and inspected public source files.
