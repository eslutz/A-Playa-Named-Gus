# Apple TV review remediation

This round follows the owner's TV-009–075 review and supplied cinematic hero reference. It changes TV presentation while preserving phone/tablet layouts and local simulator state. Physical-TV, Siri Remote, VoiceOver and output-device acceptance remain a manual gate.

| Finding | Remediation |
| --- | --- |
| TV-009 | Full-viewport sign-in options; a dedicated centered authorization code view replaces the cramped Quick Connect form. |
| TV-025 | Native system Back remains system-owned. Hero and toolbar symbols use compact spoken labels; library Filter retains a native labeled menu. Icon-plus-text is a choice, not a tvOS requirement. |
| TV-028–030 | Full-width cinematic movie hero; synopsis/metadata left, Play and compact Next Up/Favorite/More right. Watched, playlist membership and permitted movie collection membership live in More. |
| TV-033/034 | Restore the original full-width, left-aligned series/season composition. Season overflow stays available even without a playable primary target. |
| TV-039 | One collection heading, larger collection artwork and existing capability-gated actions. |
| TV-043 | Playback details use a dark system-material contrast surface over video. |
| TV-046/050 | AVPlayerViewController owns audio transport, scrubbing and output routing. Store-owned queue/reporting remains; native menu actions expose Queue and Stop. |
| TV-051/055 | Library search already uses native SwiftUI searchable, including system keyboard. Query/retry state remains owned by SearchStore. |
| TV-056 | TV playlist rows include server artwork with an explicit placeholder fallback. |
| TV-060 | Add Media and related editors use the full TV viewport. |
| TV-068 | Replace ambiguous Discover overflow with direct Seerr Settings, Search Seerr and request destinations. |
| Discovery identity | Seerr setup and confirmation use Seerr identity, not Gus onboarding branding. Fixture movie names are data, not production branding. |
| TV-071 | Dedicated Search Seerr destination; catalog does not expose a persistent search field. |
| TV-072 | Display the title once in content; keep the native More menu beside the request actions. |
| TV-073–075 | Split artwork/identity from native request review; clean confirmation with explicit status and history action; larger history thumbnails and compact toolbar labels. |

Release requires fresh protected-branch CI, merged-candidate release qualification, processed internal TestFlight build and group association. A queued Cloud run or a delivered upload alone is not tester availability.
