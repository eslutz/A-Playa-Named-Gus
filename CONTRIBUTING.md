# Contributing to A Playa Named Gus

Thanks for helping improve A Playa Named Gus.

Contributor guidance lives in the
[Contributing wiki page](https://github.com/eslutz/A-Playa-Named-Gus/wiki/Contributing).

Changes must go through a pull request targeting `main`, with the five required
GitHub checks passing before merge. Server-side main protection is currently disabled;
this requirement remains project policy. Use local Apple simulators for automated
app tests and runtime verification. Record hardware-only behavior as unverified.
Native macOS build/unit checks run on GitHub. Local simulator qualification,
authorized native archives, and actual TestFlight availability are separate gates.
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
