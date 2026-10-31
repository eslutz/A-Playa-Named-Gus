# tvOS design validation

Compare `Design/Gus-tvOS.sketch` with the current app; saved design coverage does
not establish current runtime or release readiness. Keep captures, comparison
manifests, dated audits and result bundles outside the repository.

## Limitations to verify

- Sketch represents native glass, blur, focus transitions, spinners and system
  keyboards statically; assess these in the running app.
- Recheck Settings → Streaming Quality and Content Restrictions: these picker
  destinations have shown empty screens, so intended options need runtime acceptance.
- The sign-out confirmation board is an unimplemented proposal; current Sign Out
  acts directly. Top Shelf artwork is a system reference, not dynamic-card acceptance.
- Sketch capture caching can omit unchanged layers. Refresh the render and inspect
  nested visibility and geometry before judging a missing control.
- Simulator comparisons do not establish physical-TV, Siri Remote, accessibility,
  minimum-OS or distribution acceptance. See [service boundaries](tvos-capabilities.md).

## Reproduce

Follow [isolated validation](tvos-capabilities.md#isolated-validation) to create a
separate TV simulator and start the local Jellyfin/Seerr fixtures. List installed
destinations, then run the focused UI checks against that simulator's UDID:

```sh
xcodebuild -showdestinations -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus tvOS Tests'
TEST_RUNNER_GUS_DEMO_URL=http://127.0.0.1:<port> xcodebuild test \
  -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus tvOS Tests' \
  -destination 'platform=tvOS Simulator,id=<UDID>' \
  -resultBundlePath <external-directory>/tvOS.xcresult \
  -only-testing:GusTVOSUITests/GusAuthenticatedUITests/testTVRemediationSupplementaryScreens \
  -only-testing:GusTVOSUITests/GusAuthenticatedUITests/testTVToolbarViewModes
```

Compare fresh Screens/States renders with settled app states, including focus,
loading, errors, empty data and modal dismissal. Inspect the saved Sketch archive
for missing image/symbol references and prototype destinations. Record action
coverage separately from visual comparison and retain original captures externally.
