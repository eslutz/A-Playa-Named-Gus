# App Store Connect operations

Follow the [pipeline policy](pipeline-policy.md) for release authorization and qualification.

## API access and Cloud workflow discovery

- `.env.asc.example` is the safe template; `.env.asc.local` is ignored and mode 600.
- The account-wide team key is installed in `~/.appstoreconnect/private_keys/` (directory 700, key 600). Shared configuration lives in `~/.appstoreconnect/config.env` (600), outside all repositories.
- `apps` lists apps accessible to the installed key; Gus bundle-ID filtering applies only to `inspect`.
- Use authenticated inspection to verify the app, Cloud product, and workflow separately from distribution.
- `Scripts/app-store-connect.swift` signs short-lived ES256 tokens using Apple CryptoKit
  and performs read-only API discovery. It never prints keys or bearer tokens.
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
If a start request is rejected or ambiguous, inspect the request’s authorization
and list existing runs before retrying. Interactive sign-in is not required when
the configured API key already has the necessary access.

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
before accepting it. See the [sign-in-free CLI procedure](#authorized-alternate-native-delivery).

Configuration precedence: account-wide config, `.env.local`, `.env.asc.local`, then `ASC_*` environment variables. The helper issues short-lived, per-request GET tokens with the complete query in their scope; API management writes remain deliberate operations, not a restriction on the installed key. No key contents or bearer tokens are logged.

## Authorized alternate native delivery

1. Choose a build number unused by every native platform; check both uploaded builds and product-wide Cloud runs. Use identical versions on the app, Watch and Top Shelf. Verify available numbers rather than assuming the next one.
2. Archive from the checked source with the normal architecture/warning settings. This project's shared configuration defaults to manual ad-hoc signing. Local device archives instead used `CODE_SIGN_STYLE=Automatic`, `CODE_SIGN_IDENTITY=Apple Development`, `DEVELOPMENT_TEAM=QS3GC3CT43`, and the existing API key with `-allowProvisioningUpdates`, `-authenticationKeyPath`, `-authenticationKeyID`, and `-authenticationKeyIssuerID`. The explicit team also applies to package resource bundles. Keep the Watch automation layout override and Intel exclusions from the shared build wrapper.
3. Export/upload with `method=app-store-connect`, `signingStyle=manual`, explicit distribution certificate/profile mappings, `testFlightInternalTestingOnly=true`, `manageAppVersionAndBuildNumber=false`, and `uploadSymbols=true`. Use `destination=export` for a reviewable package and `destination=upload` for delivery. Native macOS additionally requires the explicit installer certificate.
4. Put `/usr/bin:/bin:/usr/sbin:/sbin` first in Xcode's process `PATH`. On this Mac, Apple's rsync launched Homebrew rsync 3.5.1 as its peer, which rejected Apple's `--extended-attributes` option and caused `exportArchive Copy failed`. Using system tools first fixed packaging; no app source or diagnostics were changed.
5. Verify the exported Mac package's nested resource bundles. Xcode retained a development signature on `Contents/Resources/swift-nio_NIOPosix.bundle`, and Apple rejected it with code 90284. The release artifact's resource bundle was re-signed with the distribution identity, its outer archive seal restored while preserving entitlements, then re-exported. Verification of the actual package required a valid installer signature, arm64 executable, valid complete app signature and the same certificate on app/resource bundle and App Store profile. No entitlements or source files were removed to make signing pass.
6. Inspect `GET /v1/apps/{id}/buildUploads` for server processing errors/warnings, then require native `preReleaseVersion.platform`, `processingState=VALID`, `buildAudienceType=INTERNAL_ONLY`, and beta readiness. Successful delivery alone does not establish a processed build. Update tester notes using the beta localization **`whatsNew`** field. Add the four validated native builds to Gus Internal and read back each group's association and internal beta state.

Keep keychains, private keys, unlock material, export mappings and raw logs out
of Git, PRs, reports and handoffs. Do not change Keychain access controls or
create/revoke signing credentials as part of routine validation.
