# Sync Checklist

Use this checklist when updating this Swift Codex SDK port from upstream `openai/codex`.

## 1. Establish the upstream basis

- Prefer the vendored upstream checkout at `vendor/openai-codex` when available.
- Fetch upstream remote state and tags.
- If the request says latest release, resolve the latest stable GitHub release first.
- Record:
  - release tag, if applicable
  - commit SHA
  - commit URL
  - review date
  - parity target: Python SDK surface or raw schema surface
  - submodule commit, if the repo vendors upstream

## 2. Compare the correct upstream inputs

- Handwritten SDK surface:
  - `sdk/python/src/codex_app_server/api.py`
  - `sdk/python/src/codex_app_server/async_client.py`
  - `sdk/python/src/codex_app_server/client.py`
  - `sdk/python/src/codex_app_server/errors.py`
- Typed/generated surface:
  - `sdk/python/src/codex_app_server/generated/v2_all.py`
  - `sdk/python/src/codex_app_server/generated/notification_registry.py`
  - `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`
- Behavior clarifiers:
  - `sdk/python/examples/`
  - `sdk/python/tests/`

## 3. Check release ancestry before moving vendor

- Confirm whether the current vendored commit is behind or ahead of the latest stable release in the relevant paths.
- Do not assume “latest release” means “newer than current pin”.
- If moving the submodule pointer would drop already-vendored behavior, call that out explicitly.

## 4. Port the implementation

- Update Swift sources for reviewed behavior changes.
- Regenerate typed models when the vendored schema changed.
- Add or revise tests for each ported change.
- Keep intentional Swift-only differences explicit.

## 5. Update metadata

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

## 6. Verify

- Run `swift test` for behavior changes.
- Run `swift build` if tests are not the right verification target.
- Build examples if public API changed.

## 7. Report

Include:

- release tag and commit used
- parity target used
- main ported changes
- docs/version files updated
- remaining gaps, especially schema features intentionally not exposed because Python does not expose them yet
