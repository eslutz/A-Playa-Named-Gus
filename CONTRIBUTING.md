# Contributing to A Playa Named Gus

Thanks for helping improve A Playa Named Gus.

Contributor guidance lives in the
[Contributing wiki page](https://github.com/eslutz/A-Playa-Named-Gus/wiki/Contributing).

Changes must go through a pull request targeting `main`, with the four required
GitHub checks passing before merge. Server-side main protection is currently disabled.
Run macOS tests locally on Apple Silicon and use local Apple simulators for the
other platforms. Record behavior that requires unavailable hardware or entitlements
as unverified. Record local test results in the PR. GitHub runs the native macOS build.
Local test evidence, authorized native archives, and TestFlight availability are separate gates.
[Gate details](Documentation/AppStore/pipeline-policy.md).

## Development references

- Keep the root [AGENTS.md](AGENTS.md) for guidance that applies to most tasks
  or prevents costly mistakes. Put task-specific instructions and reference
  details in the relevant docs and link to them instead.
- The [engineering guide](Documentation/engineering-guide.md) maps the source,
  platform boundaries, and design decisions.
- The [local validation runbook](Documentation/local-validation.md) has XcodeGen,
  build/test, demo, and screenshot commands.
- Track actionable work and scope changes in [GitHub issues](https://github.com/eslutz/A-Playa-Named-Gus/issues).
  Update the wiki when behavior or user guidance changes, and the website when
  public feature claims, screenshots, support, privacy, accessibility, age
  suitability, or brand assets change. Keep those updates with the app change.
  The wiki is the primary home for long-form user-facing documentation.
- Use [Swiftfin](https://github.com/eslutz/Swiftfin) only as a reference for patterns
  and Jellyfin SDK call shapes. Never copy code; implement Gus changes using its
  own Apple-first stack.
