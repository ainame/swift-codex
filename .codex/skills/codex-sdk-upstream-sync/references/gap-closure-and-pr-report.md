# Gap Closure and PR Reporting

Use this policy before finalizing every PR created or updated through the upstream-sync skill, including vendor-pointer, metadata-only and workflow-only PRs. A verified release-only no-op with no repository changes does not require a PR or Claude Code run.

## Choose a reviewable gap

1. Compare the fresh surface inventory with the unresolved coverage audit in `UPSTREAM.md`. Consider old gaps as well as this release's additions. Generated types and source matches are candidates, not proof of runtime support.
2. Rank relevant candidates by user impact and effort (a short 1–10 estimate is sufficient). Prefer correctness, lifecycle, cancellation, serialization and usable typed APIs over cosmetic coverage counts.
3. Select a cohesive slice that can be implemented and verified in this PR. Describe the user-visible before/after and acceptance evidence. Larger gaps can be split; record the residual scope explicitly.
4. Attempt the selected slice through public API, encoding/dispatch, lifecycle handling and regression fixtures. Do not stop at regenerated models. Preserve compatibility where practical and document changes in behavior or exhaustive switches.
5. If all reviewed gaps are unsafe, require an upstream change, need unavailable evidence or are outside the user's scope, record that concrete reason and the next useful step. If the audit finds no verified gap, say so. Do not manufacture a code change to meet a quota.

## Seek actual Claude Code support

- Attempt Claude Code support for the selected slice before finalizing each PR. Use it for exploration, bounded implementation or independent review; substantial implementation benefits from a follow-up review of corrections.
- Discover and read the available `claude-delegate` skill and follow its relay, permission and artifact guidance. If that skill is unavailable, use a supported Claude Code CLI interface with a bounded brief and record the fallback. Never bypass permissions to obtain a consultation.
- Check CLI availability and authentication, then make an actual request. `claude auth status` alone does not prove a usable OAuth session. A failed refresh, missing CLI or quota error is an attempted but blocked consultation, not a review.
- Give the delegate the repository instructions, exact pinned upstream basis, selected gap, owned files, compatibility boundaries and gate commands. It is not alone in the codebase: it must preserve other edits. Tell it not to commit, push, merge, release or contact others. Keep implementation tasks separate from read-only reviews and use only the access needed.
- Bound each request by scope and a supported turn or time cap. Reuse a session for a focused correction; do not retry unchanged authentication, quota or permission failures in a loop. Retry after the blocking condition changes.
- The orchestrator owns the complete diff review, including generated files and tests, and independently runs the applicable checks after edits settle. Fix verified findings and rerun affected gates. Do not treat a delegate's proposed commands or unexecuted tests as passes.
- If assistance fails, briefly explain the actual blocker and continue the already-authorized work independently. An interactive user may restore authentication while work continues, but an unattended run must not wait indefinitely or abandon an otherwise reviewable PR solely because Claude is unavailable.

## Keep evidence and reporting aligned

Update `UPSTREAM.md` with selected gap outcomes and carry forward unresolved entries. Update README/changelog when supported behavior or compatibility changes. Preserve the exact basis and recorded parity target; gap work does not itself establish a newer upstream snapshot or change the target. If a dry-run snapshot omits the exact basis or target, use a clearly unresolved placeholder and a provenance lookup step instead of inventing one.

Separate local SDK tests, independent Examples builds, deterministic generation, hosted CI and live integrations. For documentation-only changes, use relevant content/link checks; do not rerun Swift builds merely to populate a report. Report pending or unavailable checks accurately.

## PR body summary

Include a concise, concrete summary in every PR body. Integrate it with the repository's PR template if present; omit conversational history, local transcript paths, credentials and memory citations. Use the final diff, not an abandoned plan:

```markdown
Upstream basis: <release and exact commit>. Parity target: <Python SDK or focused raw schema>.

### Gap closure
- Selected: <gap, impact, bounded scope and why it was prioritized>.
- Outcome: <implemented or partially implemented, with behavioral evidence; otherwise concrete deferral/no-gap reason>.

### Claude Code support
- <Actual role and useful findings; how they were addressed and independently reviewed.>
- <If blocked: attempted action, actual failure and independent fallback. Never imply a review happened.>

### Validation
- <Checks actually run and their results. Distinguish pending CI and unverified live integration.>

### Remaining gaps
- <Residual scope, compatibility limits and next useful steps; link the coverage audit.>
```

Keep this short for simple PRs. A metadata-only PR still explains the gap attempt or justified deferral and the Claude attempt/outcome. No successful gap closure is guaranteed, but the attempt and its evidence must be visible.
