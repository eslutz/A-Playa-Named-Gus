# ADR 0003: XcodeGen project source of truth

## Status

Accepted

## Context

Gus is one multiplatform app target with generated project settings that need to remain
reviewable in source control. A checked-in `.xcodeproj` would create noisy diffs, while a
pure Swift Package or local-package hybrid would not model app targets, assets,
entitlements, and supported destinations as clearly.

## Decision

`project.yml` is the source of truth and `Gus.xcodeproj` is generated with XcodeGen. After
adding, removing, or renaming source/resource files, contributors run `xcodegen generate`
before building or testing.

## Consequences

Project changes are text-reviewable and deterministic. XcodeGen remains a build-time
developer tool, not a shipped runtime dependency.
