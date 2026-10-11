Evidence acceptance notes
- Xcode app build succeeded; direct simulator install and launch PID 49837 verified.
- Xcode DeviceInteraction applicationState=NotRun conflicts with live app hierarchy/PID because launch used simctl; hierarchy and image establish app identity.
- CUA Device Hub rotation timed out once but later took effect; do not infer application hang from this tool timeout.
- XCTest app.screenshot landscape images are incorrectly cropped/transformed; rejected as visual evidence. AX trees indicate 874x402; use XCUIScreen screenshot or direct simulator captures for accepted landscape images.
- Tests return true from accessibility issue handlers to collect all issues; test success means harness completion, NOT accessibility pass.
- Contrast/clipping reports with null elements require review; disabled Connect appearance and horizontally scrolling URL text are not automatically defects.
- Existing debug preview session uses .invalid server URL and fake in-memory identity; no authenticated browsing/playback success can be inferred.
