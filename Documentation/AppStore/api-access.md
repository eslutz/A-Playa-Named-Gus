# App Store Connect API preparation

**Current policy (October 12):** protected main requires PRs and all GitHub checks. The saved main-only Cloud release tests iPhone/iPad/Duo, Mac, TV and Vision before internal distribution. Native Icon Composer source is restored and Cloud Build 8 passed without issues; CI run 38242041231 retained one iPad native audio completion failure. Tester availability remains unconfirmed until the new gates pass. [Pipeline policy](pipeline-policy.md), [release status](internal-testflight-release.md).


API authentication is configured account-wide for the authorized App Manager
team key; management writes remain deliberate task operations. Cloud onboarding
and four-platform warning-free BUILD validation are complete. Marketing version
is **1.0.0**, with a separate integer build number managed by Cloud.

The user authorized internal TestFlight distribution and access for their existing
account. The manual internal-only workflow and `Gus Internal` group are configured.
Current runtime code passed CI `38230709289` **13/13**; Cloud Build 6 reported zero
issues on all platforms. Build 7 successfully exported signed products, but iOS
preparation failed and all group post-actions were skipped. Independent Apple
upload-tool validation identified default iOS/Watch icon alpha channels as the
rejection. Repair `64b9de6` and its CI preflight guard await hosted acceptance and
a signed retry. No completed tester access or external/public release is claimed.

The previously missing embedded Watch identifier is registered as `X7N8FKWCC6`
(`UNIVERSAL`, Team `QS3GC3CT43`). Build 7's App Store export now contains a correctly
signed Watch companion with a matching distribution profile and version/build.
Mac category/copyright metadata is included and its Build 7 upload is
`VALID`/`READY_FOR_BETA_TESTING`. Signing proof,
[icon diagnosis](icon-upload-repair.md), [release status](internal-testflight-release.md).

- `.env.asc.example` is the safe template; `.env.asc.local` is ignored and mode 600.
- The account-wide team key is installed in `~/.appstoreconnect/private_keys/` (directory 700, key 600). Shared configuration lives in `~/.appstoreconnect/config.env` (600), outside all repositories.
- `apps` successfully listed all five accessible apps, including Gus. The key retains its Apple-assigned App Manager permissions across the account; Gus's bundle-ID filter applies only to the `inspect` command.
- Authenticated Gus inspection succeeded: its app record and Cloud product/workflow now exist. See [Cloud setup evidence](xcode-cloud-dependency-onboarding.md). Authentication and Cloud onboarding are verified separately; neither establishes distribution acceptance.
- `Scripts/app-store-connect.swift` signs short-lived ES256 tokens using Apple CryptoKit
  and performs read-only API discovery. It never prints keys or bearer tokens.
- The complete repairs, shared generated project, schemes, and 16 dependency pins were
  published directly to `origin/main` at `755ff09`. Cloud Build 1 verified that source commit. Bootstrap repair `084a470` subsequently
  passed all four required BUILD actions, with its full source SHA verified by the API.
  Build 3 also verified the later placeholder/accessibility repair source at `64505d9`.
- `api-templates/` contains disabled archive-workflow drafts for iOS, tvOS, visionOS,
  and macOS, plus build-trigger and internal TestFlight group requests. All seven
  templates were checked against Apple's OpenAPI 4.5.1 schema; IDs remain placeholders.
  The archive drafts are disabled and use `APP_STORE_ELIGIBLE`; they must be adapted
  to the current internal-only request and verified IDs/start conditions before use.
  The published workflow schema has no TestFlight post-action field, so configure
  post-actions through Apple's workflow editor or manually assign processed builds
  to the intended group. The API helper does not perform these management writes.

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
The initial scoped start requests returned HTTP 405 without creating a run; the
App Store Connect Start Build UI succeeded. The CLI path was corrected on
October 25, 2026: omit the optional JWT `scope` claim for write operations.
The otherwise identical `POST /v1/ciBuildRuns` then created Build 29, whose
source commit was independently verified as merged main
`ee5bf9eae0282a3ad9be884493ff031d7314c8e8`. Interactive sign-in is not required
when the configured API key already has the necessary access.

Apple's [token documentation](https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests)
describes scope entries using the GET method and permits a token without a
scope for requests allowed by the API key's role. Keep the inspection helper's
GET scopes; do not put `POST /v1/ciBuildRuns` in a write token's scope.
Use short-lived ES256 claims (`iss` for a team key or `sub: user` for an
individual key, `iat`, `exp`, and `aud: appstoreconnect-v1`) and the existing
[start request template](api-templates/start-build.json). Do not log the key or
token. A successful start is non-idempotent: inspect existing runs after any
ambiguous response before retrying. The first pending response may have an
empty source SHA; fetch the run again and require the intended full merge SHA
before accepting it. See the [Seerr release record](../Reviews/README.md)
for the first successful CLI start, Cloud startup failure, and successful alternate local Xcode delivery. See the [sign-in-free CLI procedure](cli-release.md).

Configuration precedence: account-wide config, `.env.local`, `.env.asc.local`, then `ASC_*` environment variables. The helper issues short-lived, per-request GET tokens with the complete query in their scope; API management writes remain deliberate operations, not a restriction on the installed key. No key contents or bearer tokens are logged.
