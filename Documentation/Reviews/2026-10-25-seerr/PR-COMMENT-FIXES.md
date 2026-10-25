# PR #34 comment fixes

## Request review for independent formats

The [4K entry comment](https://github.com/eslutz/A-Playa-Named-Gus/pull/34#discussion_r4371095277) identified that the detail action considered only standard request permission and status. The entry policy now evaluates standard and 4K independently. A requestable 4K format remains reachable when standard quality is available, pending or processing, including accounts with only 4K permission. Global blocklists and undocumented states fail closed. Opening review does not authorize a write: fresh server settings, quota and season eligibility still gate submission.

The parameterized regression failed against the previous gate, then passed after the correction. The containing Seerr contract suite has 31 passing tests. Additional boundaries cover permission absence, formats already available, standard-only access and global blocklisting. [Failing regression](evidence/pr-comments-4k-red-summary.json), [focused passing result](evidence/pr-comments-focused-green-summary.json).

## Submitted preference snapshots

The [preference-save comment](https://github.com/eslutz/A-Playa-Named-Gus/pull/34#discussion_r4371095280) identified that live bindings could be mistaken for the submitted values after an await. Catalog controls now disable while a save or required refresh is pending. The save captures regional values/changed fields and email values/changed masks before its first await. Successful acknowledgement advances the saved baseline only to those submitted snapshots, preserving the distinction from any later unsent values.

The full iOS unit suite passes **530 tests**, with zero failures, skips, expected failures or build diagnostics, including the new entry-policy regressions and existing settings-merge contracts. These are unit/build checks; no slow-network preference UI automation is claimed. [Results](evidence/pr-comments-ios-results.json), [source fingerprints](evidence/pr-comments-source-hashes.json). Fresh required GitHub checks and merged-main Cloud qualification remain release gates.
