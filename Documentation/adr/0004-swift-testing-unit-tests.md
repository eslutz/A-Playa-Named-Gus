# ADR 0004: Swift Testing for unit tests

## Status

Accepted

## Context

M2 adds a unit-test target for pure app logic. The project favors Apple-native APIs and is
already targeting modern Apple OS versions and Xcode toolchains.

## Decision

Unit tests use Swift Testing (`import Testing`, `@Test`, `#expect`) for pure logic such as
URL normalization, session credential formatting, stream device profiles, display helpers,
and injected-directory persistence. UI smoke coverage uses XCUITest because it is the
native framework for launching and inspecting the app.

## Consequences

Unit tests remain concise and Apple-native. Unit and XCUITest flows run locally
on native Apple Silicon for macOS and in simulators for the other platforms.
See the [current pipeline policy](../AppStore/pipeline-policy.md).
