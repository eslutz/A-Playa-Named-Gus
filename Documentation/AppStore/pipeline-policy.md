# Pull request and release gates

Requested October 12, 2026. Main is protected, including administrators: changes require a pull request, all 13 GitHub Actions checks must pass on an up-to-date branch, conversations must be resolved, and linear history is required. Force pushes and deletion are disabled. No additional reviewer approval is required; the PR and CI gate still apply to the owner.

GitHub CI runs only on pull requests targeting main, with read-only repository permissions and cancellation of superseded runs for the same PR. It keeps six builds, five unit-test lanes, lint, and configuration checks.

The saved Gus Internal TestFlight Cloud workflow accepts only exact main for automatic branch changes and manual starts. It requires unit tests using dedicated iOS, macOS, tvOS, and visionOS schemes before its internal TestFlight post-actions can distribute. iOS runs on iPhone 17, iPad Pro 11-inch (M5), and Duo; Mac, recommended Apple TVs, and Apple Vision Pro complete the device matrix. Four required internal-only archives produce the app products; Watch is embedded in iOS.

Cloud's available iOS runtime menu showed 27.1, 17.5, and 16.4. It offered no iOS 18 runtime, so minimum-OS execution remains unverified. The known iPad native audio end-notification failure is retained in run 38242041231 evidence and is not counted as a passing gate.

Saved configuration does not establish successful execution or tester eligibility. The PR matrix, subsequent merged-main Cloud run, and group association must pass before availability is claimed.

The old compile-only Gus Multiplatform Validation workflow is deactivated; its recorded builds remain available. Superseded main release builds are automatically cancelled when a newer main update starts.
