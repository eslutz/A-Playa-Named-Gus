# App Store Connect API preparation

Prepared locally on 2026-10-10; authenticated portal access and Cloud onboarding remain
pending. Marketing version is **1.0.0**, with a separate numeric build number.

- `.env.asc.example` is the safe template; `.env.asc.local` is ignored and mode 600.
- `~/.appstoreconnect/private_keys/` is prepared with mode 700. No Apple key is installed.
- `Scripts/app-store-connect.swift` signs short-lived ES256 tokens using Apple CryptoKit
  and performs read-only API discovery. It never prints keys or bearer tokens.
- The shared generated project, schemes, and 16 dependency pins are prepared for git.
  The complete app candidate must be published before Cloud can use these changes.
- `api-templates/` contains disabled archive-workflow drafts for iOS, tvOS, visionOS,
  and macOS, plus build-trigger and internal TestFlight group requests. All seven
  templates were checked against Apple's OpenAPI 4.5.1 schema; IDs remain placeholders.

```sh
swift Scripts/app-store-connect.swift preflight
swift Scripts/app-store-connect.swift self-test
python3 Scripts/test-cloud-bootstrap.py
python3 Scripts/check-cloud-project.py
# After installing the key and filling .env.asc.local:
swift Scripts/app-store-connect.swift inspect
```

Full setup, remaining portal steps, and request ordering:
[Release and TestFlight](https://github.com/eslutz/A-Playa-Named-Gus/wiki/Release-and-TestFlight).
The helper currently sends GET requests only. Creating workflows, starting builds, and
assigning builds to tester groups require deliberate write requests using the templates.

Apple supports starting builds through
[`POST /v1/ciBuildRuns`](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-cibuildruns).
The API does not replace initial Xcode Cloud onboarding or GitHub repository authorization.
