# App Store Connect API preparation

API authentication verified on 2026-10-11; Xcode Cloud onboarding is complete; the repaired complete project passed Cloud Build 2 on all four configured platforms. Marketing version is **1.0.0**, with a separate numeric build number.

- `.env.asc.example` is the safe template; `.env.asc.local` is ignored and mode 600.
- The account-wide team key is installed in `~/.appstoreconnect/private_keys/` (directory 700, key 600). Shared configuration lives in `~/.appstoreconnect/config.env` (600), outside all repositories.
- `apps` successfully listed all five accessible apps, including Gus. The key retains its Apple-assigned App Manager permissions across the account; Gus's bundle-ID filter applies only to the `inspect` command.
- Authenticated Gus inspection succeeded: its app record and Cloud product/workflow now exist. See [Cloud setup evidence](xcode-cloud-dependency-onboarding.md). Authentication and Cloud onboarding are verified separately; neither establishes distribution acceptance.
- `Scripts/app-store-connect.swift` signs short-lived ES256 tokens using Apple CryptoKit
  and performs read-only API discovery. It never prints keys or bearer tokens.
- The complete repairs, shared generated project, schemes, and 16 dependency pins were
  published directly to `origin/main` at `755ff09`. Cloud Build 1 verified that source commit. Bootstrap repair `084a470` subsequently
  passed all four required BUILD actions, with its full source SHA verified by the API.
- `api-templates/` contains disabled archive-workflow drafts for iOS, tvOS, visionOS,
  and macOS, plus build-trigger and internal TestFlight group requests. All seven
  templates were checked against Apple's OpenAPI 4.5.1 schema; IDs remain placeholders.

```sh
swift Scripts/app-store-connect.swift preflight
swift Scripts/app-store-connect.swift self-test
python3 Scripts/test-cloud-bootstrap.py
python3 Scripts/check-cloud-project.py
# After installing the key and filling .env.asc.local:
swift Scripts/app-store-connect.swift apps
swift Scripts/app-store-connect.swift inspect
```

Full setup, remaining portal steps, and request ordering:
[Release and TestFlight](https://github.com/eslutz/A-Playa-Named-Gus/wiki/Release-and-TestFlight).
The helper currently sends GET requests only. Creating workflows, starting builds, and
assigning builds to tester groups require deliberate write requests using the templates.

Apple supports starting builds through
[`POST /v1/ciBuildRuns`](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-cibuildruns).
The API does not replace initial Xcode Cloud onboarding or GitHub repository authorization.

Configuration precedence: account-wide config, `.env.local`, `.env.asc.local`, then `ASC_*` environment variables. The helper issues short-lived, per-request GET tokens with the complete query in their scope; API management writes remain deliberate operations, not a restriction on the installed key. No key contents or bearer tokens are logged.
