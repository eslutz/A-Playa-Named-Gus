## Summary

-

## Validation

- Record the local test command, destination, and result for each affected platform. Use a native Apple Silicon Mac for macOS and simulators for the other platforms.

## Checklist

- [ ] User-facing text is localized in `Resources/Localizable.xcstrings`.
- [ ] `xcodegen generate` was run after source/resource file changes.
- [ ] Relevant builds, tests, and lint checks were run.
- [ ] Native Apple/system APIs are preferred; any exception is explained above.
- [ ] Wiki or roadmap documentation is updated when the change affects project scope or user guidance.
