---
tags: [skill-creator]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill, Write]
---

Dry-run this release-only automation result. Do not access live services or mutate the repository. Produce response.md explaining what should happen and what, if anything, belongs in a PR body.

The user requested a PR only if upstream has a new stable release. A live upstream release check succeeded, and the latest stable tag resolves to a commit already included in the current vendored pin. The recorded port basis was verified, the existing audit is current, no relevant implementation or metadata change is needed, and the worktree is clean. Claude Code is not installed. No PR exists for this run. Apply the workflow without creating an empty PR, moving the pin backwards or inventing work merely to force a consultation.
