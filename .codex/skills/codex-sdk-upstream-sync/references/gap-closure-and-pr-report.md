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

Write for a reviewer assessing the final diff. Use a linked upstream release and short commit label (link to the exact commit) plus the recorded parity target on one line. Then use this compact format, adapting an existing repository template when present:

```markdown
Upstream: <release link> (<exact commit link, short label>) · <recorded parity target>.

## Changes
- <User-visible outcome, including the gap closed or the concrete reason it remains deferred.>
- <Other meaningful outcomes; usually 3–5 bullets total.>

## Compatibility
- <Actual migration or behavior change; omit this section when none applies.>

## Validation
- <Checks actually run and their results, grouped into 1–2 bullets.>
- Claude Code: <actual role and outcome, or the real blocker and independent fallback; one short bullet.>
- <Material pending or unverified gate, such as live integration.>

## Remaining
- <Top 1–2 residual gaps and next step; link UPSTREAM.md for the full audit.>
```

Keep simple PRs around 60–120 words and larger syncs around 150–250 words, excluding link URLs. These are editing targets, not reasons to hide material compatibility changes or blockers. Omit empty sections. If the audit finds no remaining gap, a short explicit statement is enough; do not invent one.

- Put gap outcomes under Changes; avoid a second section repeating the same gap selection, impact and implementation story. Keep detailed prioritization and evidence in `UPSTREAM.md`.
- Keep Claude support to one validation bullet. State whether help actually ran; a failure is not a successful review. Omit delegate-session history, internal role choreography and transcript paths.
- Summarize tests by meaningful gates and result. Include a toolchain or command only when it helps reproduce the result or explains a limitation. Omit long fixture inventories, generated-file counts and routine command transcripts.
- Link the full audit and changelog instead of enumerating every RPC, model or unresolved gap. Do not repeat the complete SHA when its commit link and `UPSTREAM.md` identify the exact basis.
- Describe workflow or skill changes only if they are part of this PR's diff, in one Changes bullet. Do not append the workflow policy itself to the PR body.
- Rewrite the body as scope changes; do not keep appending progress updates, abandoned plans or validation history. Omit credentials, memory citations and local filesystem paths.

A metadata-only PR still uses a short Changes bullet for the gap attempt or justified deferral and a Validation bullet for the actual Claude attempt/outcome. Preserve separate local, hosted-CI and live-integration claims, but do not list irrelevant gates merely to fill the template. No successful gap closure is guaranteed; a concise, evidence-backed outcome is required.
