# TestFlight API preparation — 2026-10-10

Local preparation completed without an Apple private key. No authenticated API calls,
portal changes, Cloud builds, uploads, tester invitations, commits, or pushes occurred.
The App Store Connect browser session was signed out. The existing app candidate,
including offline/download changes and UI remediation, remains local.

## Prepared

- Private key directory outside git: `~/.appstoreconnect/private_keys/` (700).
  Ignored `.env.asc.local` (600) contains placeholders. Existing Jellyfin configuration
  is preserved. `.env.asc.example` is safe to commit; `.p8` files are ignored.
- Apple-native read-only API helper with ES256 JWT signing, team/individual key support,
  offline preflight, and app/Cloud/workflow/repository/branch/toolchain/build discovery.
  Keys/JWTs are never printed; dotenv text is not evaluated as shell code.
- Cloud bootstrap corrected for Apple's `ci_scripts` working directory, with team and
  project/lockfile checks. Cloud uses the existing shared project and never regenerates it.
- Shared generated project, 11 schemes, and 16 dependency pins prepared for publication.
  GitHub CI checks project drift and resolves only pinned package versions.
- Seven request templates prepared for four disabled archive workflows, an explicit
  branch/tag build trigger, an internal beta group, and build-to-group assignment.
  Placeholder IDs require authenticated discovery. Request shapes validated against
  Apple's published App Store Connect OpenAPI 4.5.1. Server acceptance is unverified.
- Repo guidance/checklists/roadmap and the sibling wiki's Release and TestFlight page
  updated. Website claims are unaffected by this release-tooling preparation.

## Verification

- Six isolated bootstrap tests pass: scripts working directory, explicit repository
  path, wrong team, missing project, missing pins, and local generation.
- API self-test passes: P-256 PEM round-trip, ES256 JOSE signature, team/individual
  claims, expiry, GET scope, dotenv parsing, and HTTPS/host boundaries.
- Preflight reports authentication pending and zero network requests. Inspection
  refuses to proceed without credentials.
- Project drift check passes; all 16 pins contain fixed versions and revisions.
  SwiftFormat passes for the new Swift helper; `git diff --check` passes.
- Unsigned Release iOS archive succeeds using only pinned dependencies. Main app and
  embedded Watch app both contain marketing version **1.0.0**, numeric build **1**.
  Main app declares `ITSAppUsesNonExemptEncryption = false`. See `archive-metadata.json`.
  This archive proves local packaging, not signing or App Store validation.
- Earlier six-platform build/unit/UI evidence remains in the separate UI remediation
  report. Physical-device and accessibility acceptance gates remain open.

## Handoff

1. Download the Apple `.p8` when possible; fill Key ID, Issuer ID and private-key path in
   `.env.asc.local`. Run `swift Scripts/app-store-connect.swift preflight`, then `inspect`
   for an actual read-only connectivity check.
2. Publish a coherent reviewed candidate with added sources, shared project and pins.
   The generated snapshot must not be pushed without the source files it references.
3. Sign in, verify/create the app record, complete initial Cloud onboarding and GitHub
   repository authorization, and confirm platform capabilities/provisioning.
4. Substitute actual IDs/toolchain pairs in workflow templates. Enable and configure
   the intended workflow before starting a run with `POST /v1/ciBuildRuns`.
5. Verify signed archive/upload/processing, then assign the processed build to an
   eligible internal group. Confirm installation and core flows on supported devices.

The API can trigger new Cloud builds once onboarding and credentials are configured.
It does not replace initial Cloud onboarding. The helper currently performs GETs;
write templates are reviewable drafts and were not executed.

[Setup and commands](../../AppStore/api-access.md) ·
[Full wiki guide](https://github.com/eslutz/A-Playa-Named-Gus/wiki/Release-and-TestFlight) ·
[Apple build-trigger API](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-cibuildruns)

`preparation.patch` isolates edits to pre-existing configuration/docs against the
start-of-task snapshot. `prepared-files.sha256.json` inventories prepared files without
including credential files or unrelated app-source changes. Archive output remains
ignored under `build/release-preparation/`; its full local log is `/tmp/gus-release-prep-ios.log`.
