# Seerr release — October 25, 2026

**Version 1.0.0 (31) is available to Gus Internal on iOS/iPadOS, macOS, tvOS and visionOS.** Watch is embedded in iOS; Top Shelf is embedded in tvOS. All four native build records were independently verified as `VALID`, `INTERNAL_ONLY`, `IN_BETA_TESTING`, not expired, and associated with the internal group. [TestFlight evidence](evidence/testflight-build31.json). Seerr-specific English tester notes were updated on every platform. Physical installation, live Seerr and assistive-input acceptance remain unverified.

## Source and qualification

- [PR #34](https://github.com/eslutz/A-Playa-Named-Gus/pull/34) merged as `ee5bf9eae0282a3ad9be884493ff031d7314c8e8`.
- All 13 required GitHub checks passed on `9c154295bde72a27a56c1990ce524098ae39a056`. Both review comments were fixed, replied to directly and resolved. [CI/review evidence](evidence/github-final-checks.json).
- The merged-main tree exactly matches the checked PR tree. [Source identity](evidence/merged-source.json).
- The current iOS unit suite passed 530 tests with zero failures, skips, expected failures or build diagnostics. Earlier platform/UI qualification is bounded as described in [validation](VALIDATION.md).
- Local release delivery rebuilt all four native Release archives from that checked tree, with matching version/build numbers, arm64 executables and valid complete signatures. All accepted archive/export/upload logs and their native distribution sublogs passed the existing diagnostic scan with zero diagnostics. [Qualification](evidence/local-cli-qualification.json), [raw-log hashes/review](evidence/cli-accepted-logs.json).

## Working sign-in-free delivery

The owner requested a CLI or other method without another sign-in, including trying Xcode. Native Xcode CLI archive/export/upload with the existing App Store Connect API key succeeded. The Mac was locked and Xcode MCP opening required local approval, so neither UI path was used for delivery.

The original distribution private key appeared to require local SecurityAgent authorization. Its permissions were preserved. Dedicated distribution and Mac-installer identities were created through the API, along with exact app/Watch/Top Shelf platform profiles, and installed into a separate signing Keychain. They are retained privately outside Git; temporary raw key copies were removed after a signature probe verified the persisted Keychain.

Two additional packaging/signing problems were corrected without app-source changes or diagnostic suppression:

- Apple rsync launched Homebrew rsync as its peer, which rejected Apple's extended-attributes option. Putting system tools first in the Xcode process PATH fixed packaging.
- The first Mac upload was rejected with code 90284 because Xcode retained a development signature on the SwiftNIO resource bundle. The nested bundle was signed with the distribution identity and the archive seal restored with its original entitlements. The actual exported Mac package then passed installer/app/resource-bundle signature, certificate/profile and arm64 checks. The corrected upload processed successfully. One interrupted empty upload reservation was removed after verifying it had no processed build; no valid build was removed.

[CLI release procedure](../../AppStore/cli-release.md). All four successful upload resources reported `COMPLETE` with empty error/warning lists before internal group assignment. Native platform identity, beta readiness and group association were read back after assignment. No public or external distribution was performed.

## Xcode Cloud remains a separate failure

The scoped write token was the cause of the earlier HTTP 405 behavior: the otherwise identical `POST /v1/ciBuildRuns` succeeded after removing the optional JWT `scope` claim. The read-only inspection helper retains its GET scopes. Apple documents GET scope entries and permits unscoped tokens for operations allowed by the key's role.

Full release runs 29 and 30, plus one cheap routine validation diagnostic (31), all resolved the intended merge SHA but failed before native actions, with no started date or issue counts. The public API exposed no startup cause. **No Cloud qualification success is claimed.** [Run evidence](evidence/cli-cloud-runs.json). No workflow actions, warning gates or platform requirements were removed. Following the owner's alternate-method request, this release used the full passing PR matrix and local native archive/export verification instead. Default Cloud delivery policy remains unchanged for future releases.

The product's last observed Cloud run number is 31, so its next run should advance beyond the uploaded build 31; verify the returned number and avoid a duplicate version before uploading another release.

## Identifiers

- App: `6778382140` (`dev.ericslutz.gus`)
- Product: `f2e5bb18-7cd2-44ab-b88c-9d54ac63b512`
- Full workflow: `559f9de9-14d5-4b85-a091-8c3598fa346f`
- Main reference: `ada4521c-52e4-42b9-84a5-7df794a50c1e`
- Internal group: `cc95594c-6adf-4f5b-82b1-85cb92a8165f`

Private API responses, signing material and access-bearing artifact URLs remain outside the repository. Saved evidence contains sanitized metadata and hashes only. The original design checkout and its unrelated changes remain untouched.
