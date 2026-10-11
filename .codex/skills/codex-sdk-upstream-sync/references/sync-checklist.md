# Sync Checklist

Use this checklist when updating this Swift Codex SDK port from upstream `openai/codex`.

## 1. Establish the upstream basis

- Prefer the vendored upstream checkout at `vendor/openai-codex` when available.
- If `vendor/openai-codex` is empty, uninitialized, or otherwise not a valid upstream checkout, do not use it to resolve releases. Repair it with `git submodule update --init --recursive vendor/openai-codex`, then fetch tags inside the submodule before diffing.
- If the worktree is detached, stale, or otherwise blocks a clean sync branch, create a fresh worktree from `origin/main` or reset this automation worktree after confirming it has no uncommitted user changes.
- If the request says latest release, resolve the latest stable GitHub release first from a current upstream source.
- Verify the chosen release tag from the GitHub releases page or `gh release view` before relying on local tags.
- Fetch upstream remote state and tags when the environment allows it.
- If the sync uses a `ghq-get` checkout instead of `vendor/openai-codex`, run `git fetch --tags origin` in that local repo before picking the release tag.
- If refresh is blocked, treat local tags as stale fallback evidence only and say so explicitly.
- Record:
  - release tag, if applicable
  - commit SHA
  - commit URL
  - review date
  - parity target: Python SDK surface or raw schema surface
  - submodule commit, if the repo vendors upstream

## 2. Compare the correct upstream inputs

- Handwritten SDK surface:
  - `sdk/python/src/openai_codex/api.py` or legacy `sdk/python/src/codex_app_server/api.py`
  - `sdk/python/src/openai_codex/async_client.py` or legacy `sdk/python/src/codex_app_server/async_client.py`
  - `sdk/python/src/openai_codex/client.py` or legacy `sdk/python/src/codex_app_server/client.py`
  - `sdk/python/src/openai_codex/errors.py` or legacy `sdk/python/src/codex_app_server/errors.py`
- Typed/generated surface:
  - the current Python package's `generated/v2_all.py`
  - the current Python package's `generated/notification_registry.py`
  - `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`
- Behavior clarifiers:
  - `sdk/python/examples/`
  - `sdk/python/tests/`

## 3. Audit coverage and existing gaps

- Generate the complete method and experimental-field inventory with `python3 Scripts/audit_app_server_surface.py > /tmp/swift-codex-surface.md`.
- Compare it to the previous basis and carry forward the deferred gaps in `UPSTREAM.md`, including unchanged features.
- Read Rust client/server wire declarations and standalone server-request exports. Stable combined schemas can filter experimental fields and methods.
- Classify reviewed gaps as implemented, intentionally unsupported (with a reason), or deferred. Source matches are not evidence of semantic parity.
- For selected features, trace public options → serialization → dispatch → response → turn/item lifecycle and test the full path.
- Use upstream request IDs of both integer and string types. Check capability negotiation, missing handlers, generic-handler precedence, arbitrary JSON, and start/resume/fork applicability as relevant.
- Do not report full app-server parity based on deterministic generation or existing tests alone.

## 4. Check release ancestry before moving vendor

- Confirm whether the current vendored commit is behind or ahead of the latest stable release in the relevant paths.
- Do not assume “latest release” means “newer than current pin”.
- If moving the submodule pointer would drop already-vendored behavior, call that out explicitly.

## 5. Port the implementation

- Update Swift sources for reviewed behavior changes.
- Regenerate typed models when the vendored schema changed.
- Add or revise tests for each ported change.
- Keep intentional Swift-only differences explicit.

## 6. Update metadata

- Update `UPSTREAM.md`:
  - vendored checkout path and pinned commit
  - reference release tag, when applicable
  - reference commit SHA
  - reference commit URL
  - last reviewed date
  - reviewed files or features
  - parity target
  - intentional deviations
- Update `CHANGELOG.md`:
  - unreleased or released version heading
  - vendored release or basis commit
  - concise list of user-visible changes
- Update `README.md` if supported features, scope, or install guidance changed.
- Update package version references only if the repo is taking a new release because of the sync.
- Update `NOTICE` only if legal attribution changed.
- If the repo versions releases to match upstream, update the visible release version references to that same upstream version.

## 7. Verify

- Run `swift test` for behavior changes.
- Run `swift build` if tests are not the right verification target.
- Build examples if public API changed.

## 8. Ship Flow

- If the sync should ship immediately, open a PR for the sync branch first.
- Merge the PR before creating the release tag.
- Switch to the latest `main` and prepare the matching repository release there.

## 9. Report

Include:

- release tag and commit used
- parity target used
- main ported changes
- docs/version files updated
- remaining gaps, especially schema features intentionally not exposed because Python does not expose them yet
