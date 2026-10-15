# Build 19 strict policy failure

Merged commit: `983b0f4a051955293cf70d4e34b4e5d20affb520`. Run: `2a78b958-09ab-4750-8fc4-d3770354c50c`.

Completed test raw logs contain Intel Swift package compile/link actions, including watch simulator dependencies in the iOS build-for-testing action. The Mac and Vision test-without-building commands emitted multiple-matching-destination warnings. Empty API issue lists did not establish acceptance.

`Config/Architecture.xcconfig` is a global build override. The installed xcodebuild manual documents that `XCODE_XCCONFIG_FILE` applies its settings to all targets and overrides other settings, including command-line settings. Set the Xcode Cloud workflow environment variable to `/Volumes/workspace/repository/Config/Architecture.xcconfig` before the next merged run. An export inside a child CI script cannot configure Apple's parent invocation. Cloud preflight now rejects missing/wrong configuration before compilation. Physical Watch SDK ARM variants are preserved.

This is source enforcement, not verified hosted acceptance. Workflow environment setup remains required; the next merged raw logs must prove no Intel actions. The two Apple-generated destination warnings remain unresolved: their invocation lacks an architecture/variant selector, and changing app-target settings cannot rewrite the test-without-building command. No filtering or suppression was added. Native macOS restart/window and stale watched-menu live UI checks also remain unverified.
