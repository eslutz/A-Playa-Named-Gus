# Contributing to Gus

Thanks for helping improve Gus. The project is Apple-first: prefer SwiftUI,
AVKit, Observation, Security, Foundation, and other system frameworks before
adding custom infrastructure or dependencies.

## Before Opening an Issue

- Use the bug report form for reproducible defects.
- Use the feature request form for actionable product or platform work.
- Use GitHub Discussions for support, questions, broad ideas, and design
  conversations.
- Check the wiki for user-facing documentation before filing docs issues.

## Pull Requests

- Keep changes focused and describe the user-facing impact.
- Update localized strings in `Resources/Localizable.xcstrings` for new
  user-facing text.
- Run `xcodegen generate` after file additions, removals, or renames.
- Run the relevant build, test, lint, and string catalog checks for the touched
  area.
- Call out any deliberate deviation from the native API mandate in the PR body.

## Documentation

The wiki is the documentation home for contributors and users. Keep README
content concise and link to the wiki for longer explanations.
