# visionOS 3D / Spatial Video Playback — Implementation Plan

## Feasibility Research

### What Jellyfin exposes

The only 3D signal is `BaseItemDto.video3DFormat: Video3DFormat?`, an enum with five
cases:

| Jellyfin value | Format | Apple playability |
|---|---|---|
| `halfSideBySide` / `fullSideBySide` | Frame-packed: both eyes in one 2D frame, L\|R | No native support — needs custom per-eye rendering |
| `halfTopAndBottom` / `fullTopAndBottom` | Frame-packed: both eyes stacked, top/bottom | No native support — same |
| `mvc` | Blu-ray 3D (Multiview Video Coding) | Not decodable on Apple platforms — out of scope |

Critically, this field is **nil for Apple MV-HEVC "spatial video"** — Jellyfin
classifies those as ordinary HEVC. So the two cases are inverted: the format Apple
plays best carries no Jellyfin flag, and the formats Jellyfin flags are the ones Apple
can't play natively.

### What Apple provides (confirmed in XROS 26.5 SDK)

- **MV-HEVC spatial video → fully native.** `AVPlayer`/`VideoPlayer`/
  `AVPlayerViewController` render it automatically via the `CMTaggedBufferGroup` /
  `stereoViewComponents` pipeline. RealityKit's `VideoPlaybackController` exposes
  `ViewingMode.stereo`, `SpatialVideoMode`, and `ImmersiveViewingMode` for the
  immersive path.
- **Frame-packed SBS/TAB → no native stereo decode.** The file plays as a normal 2D
  video. To show it in 3D, render to a texture and feed the correct half to each eye
  via a RealityKit `ShaderGraphMaterial` keyed on view/eye index inside an
  `ImmersiveSpace`. Moderate but well-trodden.
- **MVC → unsupported.** No Apple decoder exists.

### Hard constraint — the direct-play requirement

Gus's playback is deliberately **HLS-transcode-biased** so AVPlayer always gets a
playable container. **Transcoding collapses stereo into 2D.** Any 3D playback requires
a guaranteed **direct-play** path that bypasses the transcode bias. If the server
cannot direct-play the source, 3D is impossible and the app must fall back to 2D.

### Verdict

Feasible on visionOS only, in two tiers:

- **MV-HEVC (spatial video):** low effort, near-native via existing AVKit surfaces.
- **Frame-packed SBS/TAB:** moderate effort, custom RealityKit renderer extending the
  existing Gus Cinema `ImmersiveSpace`.
- **MVC and all non-visionOS platforms:** degrade to 2D with a user-visible notice.

---

## Implementation Plan

Scope: visionOS only. Two playable tiers (MV-HEVC spatial; frame-packed SBS/TAB),
graceful 2D fallback for MVC and all other platforms. Native-first: AVKit for MV-HEVC,
RealityKit for frame-packed; no third-party decoders. One feature per commit; all five
destinations build green before each commit.

### Feature 1 — 3D detection model + eligibility

Pure logic, fully unit-testable, no UI. Lands the vocabulary the rest builds on.

- Add `Stereo3DLayout` enum in `Sources/Services/`:
  `.sideBySide(half: Bool)`, `.topAndBottom(half: Bool)`, `.mvHEVC` (Apple spatial),
  `.multiviewCoding` (MVC, unsupported), `.none`.
- Add `Media3DDetector`:
  - Maps `BaseItemDto.video3DFormat` → `Stereo3DLayout` for the frame-packed/MVC cases.
  - MV-HEVC heuristic: `video3DFormat == nil` but the media may be spatial. Inspect
    `MediaStream` codec/codecTag for HEVC + any available multiview hint; otherwise
    rely on a user "Play as Spatial" override (Feature 5). The auto-detection gap is
    the key pre-implementation unknown — see Risks.
  - `presentation(for:on:)` returns one of: `.native2D`, `.nativeSpatial` (MV-HEVC),
    `.immersiveFramePacked` (SBS/TAB), `.unsupported3D` (MVC), considering platform
    (non-visionOS always `.native2D`).
- Unit tests: every `Video3DFormat` case maps correctly; non-visionOS forces 2D;
  MVC → `.unsupported3D`.

Commit: `feat(3d): add stereo-3D detection model and eligibility`

### Feature 2 — Direct-play guarantee for 3D sources

Without this, every 3D source gets transcoded to flat 2D. Touches `StreamURLBuilder`.

- Add a `requiresDirectPlay` path to `StreamURLBuilder.resolvePlayback`: when the
  detected layout is stereo, request a profile with `enableTranscoding: false` and a
  direct-play-only `DeviceProfile`.
- If the server returns no direct-play source, surface a typed outcome:
  `"3D unavailable — playing in 2D"` rather than silently transcoding.
- Extend `StreamURLBuilder.Resolution` with `stereoLayout: Stereo3DLayout` so
  `PlaybackStore` knows which surface to build.
- Unit tests: stereo source produces a direct-play (no-transcode) `PlaybackInfoDto`
  body; non-stereo source is unchanged (keeps current HLS bias).

Commit: `feat(3d): force direct play for stereo sources, fall back to 2D`

### Feature 3 — MV-HEVC spatial playback (native, low effort)

The near-native tier. visionOS `VideoPlayer`/`AVPlayer` already renders MV-HEVC.

- When `presentation == .nativeSpatial`, build the `AVPlayer` as today via the
  direct-play URL from Feature 2. The existing `VideoPlayer` surface renders stereo
  automatically; no new rendering code is needed.
- Add a small "Spatial" badge in the visionOS player chrome (compile-guarded) so the
  user can confirm the stereo path engaged.
- Verify on the visionOS simulator (renders monoscopically in sim; true stereo
  confirmed on device — record as a manual device-verification note).

Commit: `feat(3d): play MV-HEVC spatial video via direct-play AVPlayer`

### Feature 4 — Frame-packed SBS/TAB renderer (RealityKit, moderate)

The custom tier. Extends the existing Gus Cinema `ImmersiveSpace`.

- Add `Stereo3DScreen` (RealityKit entity) hosting a `VideoMaterial` fed by the
  `AVPlayer`, applied to a curved/flat screen entity inside the Cinema `ImmersiveSpace`.
- Add a `ShaderGraphMaterial` (or surface shader) that, per eye (view index), samples
  the correct half of the frame:
  - `sideBySide`: left eye → `u ∈ [0, 0.5]`, right eye → `u ∈ [0.5, 1]`
  - `topAndBottom`: left eye → `v ∈ [0, 0.5]`, right eye → `v ∈ [0.5, 1]`
  - Half variants: same sampling; the aspect squeeze is corrected by screen dimensions.
- When `presentation == .immersiveFramePacked`, `PlaybackStore` opens the Cinema
  `ImmersiveSpace` with the stereo screen instead of the flat `VideoPlayer` window.
  The same `AVPlayer` drives audio, transport controls, and Now Playing unchanged.
- Graceful open failure: if the `ImmersiveSpace` can't open, fall back to flat 2D
  (the existing Cinema fallback path handles this already).
- Gate the `ShaderGraphMaterial` view-index API on visionOS availability; fall back
  to 2D below the supported version.

Commit: `feat(3d): render frame-packed SBS/TAB stereo in an immersive screen`

### Feature 5 — Graceful fallback + viewing-mode control

Honors the acceptance bar: "unsupported formats fall back gracefully."

- MVC and any `.unsupported3D` → play 2D with a one-line notice
  (`"3D not supported for this format — playing in 2D"`). Catalogued string.
- Non-visionOS platforms → always 2D; no 3D UI shown (compile-guarded to visionOS).
- Add a viewing-mode menu in the visionOS player: **Auto / 2D / Spatial**, letting
  the user force-enable spatial for MV-HEVC files Jellyfin didn't flag (the detection
  gap from Feature 1) or force 2D for comfort.
- All new strings in `Localizable.xcstrings`.

Commit: `feat(3d): graceful fallback and viewing-mode control`

### Feature 6 — ADR, docs, roadmap

- New ADR: `Documentation/adr/0006-stereoscopic-video-playback.md` recording the
  direct-play constraint, the MV-HEVC detection gap, MVC as out-of-scope, and the
  RealityKit-vs-AVKit surface split.
- Update `CLAUDE.md`/`AGENTS.md` to document the supported formats and presentation
  paths.
- Promote the roadmap "visionOS 3D video playback" item from Future Features into a
  real milestone entry and check it off per its acceptance bar (formats documented,
  correct path chosen, graceful fallback confirmed), noting device-only stereo
  separation as a manual-verification item.

Commit: `docs(3d): ADR, architecture notes, and roadmap promotion`

---

## Risks / Unknowns

| Risk | Severity | Mitigation |
|---|---|---|
| **MV-HEVC auto-detection** — Jellyfin doesn't flag spatial video; `MediaStream` may expose no usable multiview hint | High | Validate on a real spatial file before committing to auto-detection; Feature 5's manual "Play as Spatial" override is the safety net regardless |
| **Direct-play dependency** — if a server can only transcode a given 3D source, 3D is impossible by construction | Medium | Surface clearly as a 2D fallback with a message; not a bug |
| **Device-only stereo verification** — simulators don't render true stereo separation | Medium | All three playable paths need a Vision Pro to confirm; record as manual notes per the M4 verification pattern |
| **ShaderGraphMaterial view-index API version sensitivity** | Low | Gate on availability; fall back to 2D below the supported visionOS version |

---

## Out of Scope

- MVC (Blu-ray 3D) decoding — no Apple decoder.
- 3D playback on iOS/iPadOS/macOS/tvOS — no stereo presentation hardware; always 2D.
- Offline downloads of spatial/stereo media — a later increment if warranted.
