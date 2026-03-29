---
name: codex-sdk-upstream-sync
description: Update this Swift Codex SDK port to match the latest relevant upstream `openai/codex` Python app-server SDK under `sdk/python/src/codex_app_server`, then refresh vendored upstream, typed model generation, and recorded metadata. Use when the user asks to sync upstream, bump `vendor/openai-codex`, catch up Python app-server behavior, compare against the v2 app-server schema, or update files like `UPSTREAM.md`, `README.md`, and `CHANGELOG.md` after parity work.
---

# Codex SDK Upstream Sync

Sync this Swift port against the relevant upstream `openai/codex` Python app-server SDK and the vendored v2 app-server schema, then update code, tests, and metadata together.

## Workflow

1. Resolve the repositories first.
   - Work in the target Swift port repository.
   - Prefer the vendored upstream checkout at `vendor/openai-codex` when the repository includes it.
   - If the repo does not vendor upstream, ensure a local checkout of `openai/codex` exists. Use [$ghq-get](/Users/ainame/.codex/skills/ghq-get/SKILL.md) when the upstream repo is only referenced by GitHub URL or is not present locally.
2. Resolve the upstream basis before editing.
   - Fetch upstream tags and remote state.
   - If the user asks for the latest release, use the latest stable GitHub release, not alpha or pre-release tags.
   - Expect upstream release tags to be named like `rust-v0.117.0`.
   - Compare the current vendored commit against the target release with ancestry checks before moving the submodule pointer. The current pin may already contain newer commits than the latest stable release for some paths.
   - Record the exact `openai/codex` commit SHA used as the basis, not just the tag name or branch.
3. Compare the right upstream sources.
   - Treat `sdk/python/src/codex_app_server` as the primary handwritten SDK surface.
   - Treat `sdk/python/src/codex_app_server/generated/v2_all.py`, `generated/notification_registry.py`, and `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json` as the typed protocol/model basis.
   - Review upstream examples and tests when they clarify intended behavior.
4. Decide the parity target explicitly.
   - Python SDK parity: match the public Python app-server client surface and behavior.
   - Raw app-server schema parity: match protocol features present in the v2 schema even if the Python SDK does not expose them yet.
   - Do not silently switch between these modes. State which one the change is targeting.
5. Port the changes end to end.
   - Update implementation files first.
   - Regenerate typed models when the vendored schema changed and this repo’s generator depends on it.
   - Update or add tests for each behavior change.
   - Preserve intentional Swift-specific deviations unless the user asks to remove them.
6. Refresh metadata and version references in the same pass.
   - If the repository vendors upstream as a submodule, keep the submodule pointer, `UPSTREAM.md`, and `CHANGELOG.md` aligned.
   - Update `UPSTREAM.md` with the exact upstream commit SHA, commit URL, review date, reviewed files or features, parity mode, and intentional deviations.
   - Update `CHANGELOG.md` with the vendored release or basis commit and the user-visible changes from the sync.
   - Update `README.md` when supported features, scope, or upstream wording changed.
   - Update package or release version references only when the repository’s version should move because of the sync.
   - Update `NOTICE` only when attribution requirements actually changed.
7. Verify before concluding.
   - Run `swift test` for behavior changes. Use `swift build` only when tests are unavailable or the change is documentation-only.
   - If there is an examples package, build it when the sync touches user-facing API.
8. Finish with a focused summary.
   - State the upstream commit and release tag used.
   - State whether the work targeted Python SDK parity or raw schema parity.
   - State the main features or files synced.
   - State which metadata/version files were updated.
   - Call out any upstream areas still not ported.

## Comparison Rules

- Prefer direct upstream sources such as repository files, examples, and tests over secondary explanations.
- Treat upstream tests as behavioral specifications when production code is ambiguous.
- Keep CLI wrapper behavior aligned with upstream where practical, but keep the Swift API idiomatic.
- Do not claim full app-server feature parity when only the Python SDK surface was matched.
- When the schema contains features not exposed by the Python SDK, call that gap out explicitly instead of implying parity.

## Metadata Rules

- Treat `UPSTREAM.md` as the canonical record of which upstream snapshot this port currently references.
- When a vendored `vendor/openai-codex` submodule exists, treat it as the default local upstream checkout and record its pinned commit separately from the verified port basis.
- Use `CHANGELOG.md` to expose the same sync at release level so users can see which upstream basis a given version corresponds to.
- If the repo does not already record a trustworthy basis, do not invent one. Record the newly reviewed commit only for the sync you actually performed.
- If the sync warrants a release/version bump, update all visible references consistently, including installation snippets and release notes if present.
- Keep `NOTICE` focused on legal attribution, not ongoing sync notes.

## Practical Command Pattern

Use fast local inspection tools first.

```bash
git -C vendor/openai-codex fetch --tags origin
gh release list --repo openai/codex --limit 10
git -C vendor/openai-codex merge-base --is-ancestor <target-release-or-commit> <current-pin>
git -C vendor/openai-codex log -n 20 -- sdk/python/src/codex_app_server
git -C vendor/openai-codex diff <old-sha>..<new-sha> -- sdk/python/src/codex_app_server sdk/python/examples sdk/python/tests codex-rs/app-server-protocol/schema/json
rg -n "upstream|vendor/openai-codex|codex_app_server|generate_app_server_v2|version" README.md UPSTREAM.md CHANGELOG.md Package.swift Scripts Sources Tests AGENTS.md
swift test
```

For a detailed checklist, read [references/sync-checklist.md](references/sync-checklist.md).
