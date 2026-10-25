# Seerr implementation scope

The user accepted Discovery for implementation on October 25, 2026 and authorized existing Gus design language for visual gaps. The private Sketch Gus iPhone document is the visual input: Discover catalog/search, series/seasons, requests/history, management, issues/blocklist and preferences. Other app redesign work remains separate.

Reviewed frame examples are Discover Catalog / Browse (`75755289-38C8-42F7-9818-BBFE0E619E99`), movie detail (`3203125F-B4FD-48AD-BB53-5A9292BA1E1A`) and series metadata (`7D849119-4F96-44BB-81A2-19F87B02985F`). The private working designs and unfinished design checkout are preserved; they are not shipped with the app.

Use system navigation, sheets, forms, semantic text and existing artwork components. Browse has one leading hero and independent enabled feed shelves, with dedicated paged grids/list and native debounced search. Detail exposes returned metadata and explicit request review; season 0 is Specials and episode drilldown remains metadata-only. Discover can be hidden/reordered without deleting its connection.

A request refreshes account, media, quota and allowed season choices before an explicit POST. The reviewed payload and prior request identities survive uncertain responses in an on-device journal. No request is automatically repeated, and an inconclusive readback keeps the lock. Own pending cancellation and permitted manager decisions require named confirmation and authoritative readback. Support writes observe the same account, restriction and uncertainty boundaries.

Seerr media IDs never authorize playback. Gus scans only the authenticated Jellyfin account, checks type and matching metadata namespaces, applies current content restrictions and offers explicit matching library destinations. Cookies stay in this device's Keychain; passwords are never saved or synced.

The Watch companion has no Discovery destination. Custom Seerr sliders, provider setup/secrets, full infrastructure administration, all-user issue administration and native push are outside the implemented capability set. Catalog filters are limited to fields supported by each endpoint; notification controls cover supported email events. [API sources](Seerr-api-contract.md) define the backend contract.
