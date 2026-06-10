# App Store Readiness Packet

Status: readiness documentation, bundled privacy manifest, local signing support, and
the GitHub Actions/Xcode Cloud ownership split. App Store Connect setup, screenshots,
Xcode Cloud archive validation, upload, TestFlight, and submission are still
implementation work.

## Index

- `privacy-policy.md` - draft privacy policy text, including tvOS text.
- `privacy-labels.md` - draft App Privacy answers.
- `review-compliance-audit.md` - App Review self-audit, including downloaded media.
- `signing-capabilities.md` - signing and capability gaps.
- `ci-strategy.md` - GitHub Actions and Xcode Cloud ownership split.
- `app-store-metadata.md` - draft product metadata.
- `accessibility.md` - accessibility readiness, public accessibility page, and release
  validation matrix.
- `diagnostics-reliability.md` - Apple-native crash, MetricKit, performance baseline,
  and diagnostics review plan.
- `review-support-pages.md` - required hosted support, privacy, marketing, and age
  suitability pages for `gus.ericslutz.dev`.
- `demo-server.md` - local demo Jellyfin container over the rights-cleared sample media.
- `performance-baselines.md` - recorded performance baselines and re-measurement steps.
- `screenshots-and-testflight.md` - screenshot matrix and beta checklist.

Feature briefs (acceptance artifacts) live one level up in `Documentation/`:
`family-safety-brief.md`, `watchos-brief.md`, and `visionos-3d-playback-plan.md`.

## Apple References

- Privacy manifest files: https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
- Manage app privacy: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy
- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Screenshot specifications: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
- TestFlight overview: https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/
