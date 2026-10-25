# Seerr API contract

Verified against the official [Seerr v3.0.0](https://github.com/seerr-team/seerr/tree/v3.0.0)
and [v3.5.1](https://github.com/seerr-team/seerr/tree/v3.5.1) released source on
2026-10-25. Gus accepts stable Seerr 3 releases, minimum 3.0.0; development builds,
legacy Jellyseerr/Overseerr versions, and future major versions require separate
compatibility review. No server API key is needed.

All paths below are relative to the configured server base path plus `/api/v1/`.
The released [OpenAPI file](https://github.com/seerr-team/seerr/blob/v3.5.1/seerr-api.yml)
is an index; the owning route, model and constant definitions resolve its stale
or incomplete fields.

| Capability | Endpoints and owning contract |
| --- | --- |
| Validation and account | `status`, `settings/public`, `auth/local`, `auth/jellyfin`, `auth/me`, `auth/logout`; [authentication routes](https://github.com/seerr-team/seerr/blob/v3.5.1/server/routes/auth.ts) |
| Catalog | `settings/discover`, `discover/trending`, `discover/movies`, `discover/tv`, both upcoming feeds, `search`, movie/TV details, recommendations/similar, person/combined credits, TV season and collection details; [discovery constants](https://github.com/seerr-team/seerr/blob/v3.5.1/server/constants/discover.ts), [search models](https://github.com/seerr-team/seerr/blob/v3.5.1/server/models/Search.ts) |
| Requests | `request` list/create, `request/{id}` detail/delete, approve/decline/retry, user requests/quota; [request routes](https://github.com/seerr-team/seerr/blob/v3.5.1/server/routes/request.ts), [creation logic](https://github.com/seerr-team/seerr/blob/v3.5.1/server/entity/MediaRequest.ts) |
| Advanced request choices | Non-sensitive `service/radarr` and `service/sonarr` lists/details; [service routes](https://github.com/seerr-team/seerr/blob/v3.5.1/server/routes/service.ts) |
| Issues | `issue` list/create, issue detail/comment and `open`/`resolved`; own issue history, permission and ownership checked before changes; [issue routes](https://github.com/seerr-team/seerr/blob/v3.5.1/server/routes/issue.ts) |
| Blocklist | List/add and typed TMDB-ID removal; removal also deletes Seerr's associated media/history records and receives a named confirmation; [blocklist routes](https://github.com/seerr-team/seerr/blob/v3.5.1/server/routes/blocklist.ts) |
| Preferences | Supported regions/languages, own general settings, supported email event choices; fresh complete settings snapshots preserve unrelated fields, including notification-provider credentials; [user settings routes](https://github.com/seerr-team/seerr/blob/v3.5.1/server/routes/user/usersettings.ts) |

Permission bits follow [permissions.ts](https://github.com/seerr-team/seerr/blob/v3.5.1/server/lib/permissions.ts).
Availability and request statuses follow [media.ts](https://github.com/seerr-team/seerr/blob/v3.5.1/server/constants/media.ts):
availability `6` means blocklisted and `7` means deleted. Undocumented statuses
cannot enable changes. Movie quotas count titles; TV quotas count selected
seasons. Explicit season arrays preserve the confirmed selection.

The client uses an ephemeral session, an exact-origin/base-path cookie jar and
redirect policy, and Keychain-ready cookie representations. Passwords and server
API keys are never persisted. CSRF cookies and headers are supported. Full
notification snapshots stay inside the client actor and are not shown by forms
or logged. An interrupted or malformed mutation response requires reconciliation
through a fresh read before retry; mutations are never automatically replayed.
Report/comment operations additionally journal their pending state in the owning
account's saved connection. Disappearance or cancellation cannot unlock duplicate
submission. An authoritative reply clears that journal; otherwise the user must
check Seerr and explicitly confirm whether another submission is needed.

Browse honors the enabled supported built-in server sliders. Custom sliders and
unsupported categories are omitted. Issue management currently exposes the
signed-in user's history and authorized actions, rather than an all-user issue
administration screen. Notification controls expose supported email events;
provider setup and credential forms remain in Seerr.

Contract tests use synthetic URLProtocol fixtures for URL/cookie/redirect
isolation, status and permission handling, quotas/seasons, request payloads,
uncertain outcomes, and preservation of general/notification settings and
unchanged/unknown notification bits. Playback resolver tests use authenticated
provider fixtures and isolated restrictions to verify typed external-ID matching,
paging, and season-zero resolution. These
checks do not establish live-server acceptance, real account permissions,
Jellyfin identity matching, or physical-device behavior. See the current release
validation evidence before claiming platform acceptance.

## TMDB attribution asset

`Resources/Assets.xcassets/TMDBLogo.imageset/TMDBLogo.svg` is the unmodified approved
short blue logo downloaded from TMDB's official
[logos and attribution page](https://www.themoviedb.org/about/logos-attribution):
[original SVG](https://www.themoviedb.org/assets/v4/logos/v2/blue_short-8e7b30f73a4020692ccca9c88bafe5dcb6f8a62a4c6bc55cd9ba82bb2cd95f6c.svg).
SHA-256: `8e7b30f73a4020692ccca9c88bafe5dcb6f8a62a4c6bc55cd9ba82bb2cd95f6c`.
Its original colors and aspect ratio are retained. Display it with the required
notice in Discover Settings, less prominently than Gus's own branding. The
[official FAQ](https://developer.themoviedb.org/docs/faq) specifies the approved
logo and notice: “This product uses the TMDB API but is not endorsed or certified
by TMDB.”
