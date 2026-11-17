# CI strategy

The [pipeline policy](pipeline-policy.md) defines the current validation and release
boundaries. Simulator builds and tests run locally, one simulator at a time.
Reuse valid revision-scoped evidence when the relevant inputs are unchanged;
do not repeat disruptive runs merely to obtain a newer timestamp.

GitHub Actions runs on pull requests targeting `main`, with five checks:
Validation Scope, Lint, Docs and Config, Build macOS, and Test macOS.
The native macOS unit job is the authorized hosted runtime exception.
The shared project and dependency pins are verified before native build/test work;
warning-free and Apple Silicon enforcement remain mandatory.

Xcode Cloud is reserved for separately authorized native archive/signing/distribution
work after exact-candidate local simulator qualification. Old Cloud workflows with
simulator test actions must not be started. Their live settings have not been changed
by this correction; review and reconcile them before any future archive run.
The source preflight rejects simulator actions when that revision is selected.

The PR and five-check requirement is project policy. Live main-branch protection is
currently disabled; workflow YAML does not establish server-side enforcement.
No merge, archive, distribution or permission change follows from this policy update.
