# Gus Review Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remediate the static Gus codebase review findings with tested local fixes, clear release gates, and explicit manual-verification follow-ups for external Apple/Jellyfin/device dependencies.

**Architecture:** Prioritize session-boundary, child-safety, playback, and release-readiness work before polish. Use small injectable seams only where they let tests cover system-side effects without replacing Apple frameworks. Keep `project.yml` as the source of truth and regenerate after source/target/resource changes.

**Tech Stack:** Swift 5, SwiftUI Observation, AVKit/MediaPlayer, Security Keychain, CoreSpotlight, WatchConnectivity, XcodeGen, Swift Testing/XCTest.

---

### Task 1: Session Boundary and System-Surface Cleanup

**Files:**
- Modify: `Sources/Stores/AppModel.swift`
- Modify: `Sources/App/RootView.swift`
- Modify: `Sources/Services/WatchSessionRelay.swift`
- Modify: `Sources/Watch/WatchCredentialReceiver.swift`
- Test: `Tests/APlayaNamedGusTests/AppModelSessionTests.swift`

- [x] **Step 1: Write failing tests for account switch cleanup**

Add tests that install a lifecycle spy into `AppModel`, switch from user A to user B, and assert the outgoing account's Spotlight/TopShelf/watch cleanup hooks run before the new session is installed.

- [x] **Step 2: Verify the tests fail**

Run:

```sh
xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus iOS Unit Tests' -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:GusTests/AppModelSessionTests
```

Expected: failure because there is no cleanup seam and `switchToStoredUser` only restores the new session.

- [x] **Step 3: Implement cleanup seam and root keying**

Add an app-model account-lifecycle dependency with default closures for `SpotlightIndexer.deleteIndex`, `TopShelfSnapshot.clear`, and `WatchSessionRelay.clear`. Call it on switch/sign-out. Key `RootContainer` by `SessionCredential(user: session.user).account`.

- [x] **Step 4: Verify tests pass**

Run the same focused AppModel session test command.

### Task 2: Watch Credential Clear Payload

**Files:**
- Modify: `Sources/Services/WatchSessionRelay.swift`
- Modify: `Sources/Watch/WatchCredentialReceiver.swift`
- Test: `Tests/APlayaNamedGusTests/AppModelSessionTests.swift`

- [x] **Step 1: Write failing tests for clear payload decoding**

Add tests proving a signed-out handoff for a specific server/user removes the matching watch-side session and token but does not clear an unrelated account.

- [x] **Step 2: Verify failure**

Run the focused AppModel tests.

- [x] **Step 3: Implement clear payload support**

Publish a `clearCredential` context containing `serverID` and `userID`; on the watch, call an `AppModel.clearHandedOffSession(serverID:userID:)` helper that deletes the matching token/session only.

- [x] **Step 4: Verify tests pass**

Run the focused AppModel tests.

### Task 3: Now Playing and Audio Playback Correctness

**Files:**
- Modify: `Sources/Features/Player/NowPlayingController.swift`
- Modify: `Sources/Stores/AudioPlayerStore.swift`
- Test: `Tests/APlayaNamedGusTests/AudioPlaybackTests.swift`

- [x] **Step 1: Write failing tests for audio resume and media typing**

Add tests for pure helpers that classify `.audioBook` as audio and compute the initial report position from resume ticks.

- [x] **Step 2: Verify failure**

Run the focused audio playback tests.

- [x] **Step 3: Implement minimal fixes**

Remove any existing periodic observer before `NowPlayingController.start` installs a new one; use `item.isAudioPlayable` for media type; set `AudioPlayerStore.currentTime` immediately after resume seek; add optional next/previous callbacks for system commands.

- [x] **Step 4: Verify tests pass**

Run the focused audio playback tests.

### Task 4: Book Cache and Progress Scoping

**Files:**
- Modify: `Sources/Services/BookFileProvider.swift`
- Test: create `Tests/APlayaNamedGusTests/BookCacheTests.swift`

- [x] **Step 1: Write failing tests for cache path and progress key scoping**

Add tests proving two server/user accounts with the same item ID use different cache directories and progress keys.

- [x] **Step 2: Verify failure**

Run the focused book cache tests after regenerating the project.

- [x] **Step 3: Implement scoped paths**

Add `AccountScope`-based cache directories and progress keys; preserve backward-compatible read fallback for existing unscoped progress when safe.

- [x] **Step 4: Verify tests pass**

Run the focused book cache tests.

### Task 4A: Offline Download Account Cleanup

**Files:**
- Modify: `Sources/Services/OfflineDownloadStore.swift`
- Modify: `Sources/Stores/AppModel.swift`
- Test: `Tests/APlayaNamedGusTests/OfflineDownloadTests.swift`
- Test: `Tests/APlayaNamedGusTests/AppModelSessionTests.swift`

- [x] **Step 1: Write failing tests for account-scoped download cleanup**

Add tests proving file-store deletion removes only the requested server/user records and that loaded stores cancel/remove only the loaded account.

- [x] **Step 2: Verify failure**

Run focused offline download and app-model session tests.

- [x] **Step 3: Implement scoped deletion hooks**

Add account-scoped file-store deletion, store-level scoped cancellation/removal, and app-model cleanup wiring for sign-out/account switch.

- [x] **Step 4: Verify tests pass**

Run focused offline download and app-model session tests.

### Task 5: Release Configuration and CI Metadata

**Files:**
- Modify: `project.yml`
- Modify: `.github/workflows/ci.yml`
- Modify: `Documentation/AppStore/app-store-metadata.md`
- Modify: `Documentation/AppStore/signing-capabilities.md`
- Test: generated Xcode project inspection and plist lint

- [x] **Step 1: Encode the release policy**

Decide whether Gus is OS 26-minimum or Xcode 26-built with lower deployment targets. If no external decision exists, document the current policy as Xcode 26-built with older deployment targets and availability gates.

- [x] **Step 2: Gate entitlement-backed features**

Remove release metadata claims for CarPlay and Declared Age Range until entitlements are granted, or mark them as pending in release docs.

- [x] **Step 3: Fix watch scheme test action**

Remove the `Gus watchOS` test action until a watch test bundle exists.

- [x] **Step 4: Broaden CI config validation**

Add watch Info.plist, TopShelf entitlement, and CarPlay entitlement linting to CI.

- [x] **Step 5: Verify**

Run `xcodegen generate`, `jq empty Resources/Localizable.xcstrings`, and plist/entitlement lint.

### Task 6: Localization and Accessibility Polish

**Files:**
- Create: `Resources/InfoPlist.xcstrings` or localized InfoPlist resource files
- Modify: display/formatting helpers under `Sources/Providers/MediaItem+Display.swift`
- Modify: progress labels in watch and downloads views
- Test: `jq empty Resources/Localizable.xcstrings`

- [x] **Step 1: Add localizable Info.plist strings**
- [x] **Step 2: Replace English-only duration/fallback formatting with native formatters**
- [x] **Step 3: Add accessibility values for progress indicators**
- [x] **Step 4: Verify string catalogs, focused provider tests, and watch build**

### Task 7: Test Coverage and Maintainability Follow-Up

**Files:**
- Modify: `Tests/APlayaNamedGusTests/LibraryStoreTests.swift`
- Modify: `Tests/APlayaNamedGusTests/PerformanceBaselineTests.swift`
- Modify or remove: `Scripts/generate-app-icon.swift`
- Test: focused unit tests and lint

- [x] **Step 1: Isolate URLProtocol mock state in `LibraryStoreTests`**
- [x] **Step 2: Convert performance baseline helpers to enforced thresholds or rename them as manual measurement helpers**
- [x] **Step 3: Retire obsolete app-icon generator docs/script**
- [x] **Step 4: Verify focused test suites**

### Completed Validation

- `xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus iOS Unit Tests' -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:GusTests/AppModelSessionTests`
- `xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus iOS Unit Tests' -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:GusTests/AudioPlaybackTests`
- `xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus iOS Unit Tests' -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:GusTests/BookCacheTests`
- `xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus iOS Unit Tests' -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:GusTests/OfflineDownloadTests`
- `xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus iOS Unit Tests' -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:GusTests/ProviderArchitectureTests`
- `xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus iOS Unit Tests' -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:GusTests/LibraryStoreTests -only-testing:GusTests/PerformanceMeasurementTests`
- `xcodebuild build -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus watchOS' -destination 'generic/platform=watchOS Simulator'`
- `xcodegen generate`
- `jq empty Resources/Localizable.xcstrings Resources/InfoPlist.xcstrings Resources/Watch/InfoPlist.xcstrings`
- `plutil -lint Resources/Info.plist Resources/Watch/Info.plist Resources/PrivacyInfo.xcprivacy Sources/TopShelf/Info.plist Config/Gus.entitlements Config/Gus-tvOS.entitlements Config/GusTopShelf.entitlements Config/Gus-CarPlay.entitlements`
- CI pending-entitlement policy check for CarPlay entitlement wiring.

### External / Manual Gates

- Apple Developer Portal: CarPlay audio entitlement, Declared Age Range entitlement, tvOS user-management provisioning, App Group validation.
- App Store Connect: metadata, privacy labels, screenshots, age rating, TestFlight review.
- Legal/license: third-party notices and MPL obligations for `jellyfin-sdk-swift`.
- Runtime validation: physical/simulator playback, AirPlay, PiP, CarPlay, watchOS, tvOS Top Shelf, Spotlight, VoiceOver, Switch Control, keyboard, Dynamic Type, RTL, large-library performance, and live Jellyfin server behavior.
- Full Jellyfin feature completeness: central unauthorized handling, episode paging, favorites support, authenticated-image strategy, and book/audiobook resume rails remain larger follow-up items.
- Runtime cancellation of in-flight app downloads during account switch should be verified in the running app. Persistent records/files are purged; the live `AppModel` cleanup path does not own every `OfflineDownloadStore` instance.
