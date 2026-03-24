# Upstream Reference

This repository ports the TypeScript SDK from the [`openai/codex`](https://github.com/openai/codex) monorepo, primarily from [`sdk/typescript`](https://github.com/openai/codex/tree/main/sdk/typescript).

## Recorded Upstream Basis

- Upstream repository: `openai/codex`
- Upstream SDK path: `sdk/typescript`
- Vendored upstream checkout: `vendor/openai-codex`
- Vendored upstream commit: `527244910fb851cea6147334dbc08f8fbce4cb9d`
- Stable exec reference commit SHA: `3293538e128e02ca24d5e9913af986ac68405b00`
- Stable exec reference commit URL: `https://github.com/openai/codex/commit/3293538e128e02ca24d5e9913af986ac68405b00`
- Experimental app-server reference commit SHA: `527244910fb851cea6147334dbc08f8fbce4cb9d`
- Experimental app-server reference commit URL: `https://github.com/openai/codex/commit/527244910fb851cea6147334dbc08f8fbce4cb9d`
- Last reviewed date: `2026-03-24`

The vendored submodule commit above identifies which upstream checkout is bundled in this repository. The stable `exec` transport still tracks an earlier reviewed TypeScript basis, while the experimental app-server client now tracks the current Python `codex_app_server` and v2 protocol basis shown above.

## How To Keep This In Sync

When porting new behavior from the TypeScript SDK or validating parity against upstream:

1. Identify the upstream `openai/codex` commit you are using as the basis for the change.
2. Start from the vendored checkout in `vendor/openai-codex`, fetch the latest upstream remote state there, and review the relevant files under `sdk/typescript` at the chosen commit.
3. Update this file with:
   - the exact commit SHA
   - a GitHub commit URL
   - the review date
   - the specific upstream files or features reviewed
   - any intentional Swift-specific deviations
4. Update [`README.md`](README.md) if the high-level status or scope has changed.
5. Update [`NOTICE`](NOTICE) only if attribution requirements change or additional derived material is imported.

## Sync Notes Template

Use this section for ongoing maintenance notes. Add dated entries newest first.

### Unreleased

- Vendored checkout: `vendor/openai-codex` at `527244910fb851cea6147334dbc08f8fbce4cb9d`
- Stable exec reference commit: `3293538e128e02ca24d5e9913af986ac68405b00`
- Experimental app-server reference commit: `527244910fb851cea6147334dbc08f8fbce4cb9d`
- Reviewed upstream files:
  - `sdk/typescript/src/exec.ts`
  - `sdk/typescript/tests/exec.test.ts`
  - `sdk/typescript/tests/run.test.ts`
  - `sdk/typescript/tests/setupCodexHome.ts`
  - `sdk/typescript/tests/testCodex.ts`
  - `sdk/typescript/README.md`
  - `sdk/python/src/codex_app_server/api.py`
  - `sdk/python/src/codex_app_server/client.py`
  - `sdk/python/src/codex_app_server/_run.py`
  - `sdk/python/src/codex_app_server/errors.py`
  - `sdk/python/src/codex_app_server/generated/v2_all.py`
  - `sdk/python/src/codex_app_server/generated/notification_registry.py`
  - `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`
- Reviewed upstream features:
  - `baseUrl` now maps to `--config openai_base_url=...` rather than `OPENAI_BASE_URL`
  - explicit environment overrides must remain isolated from the host environment except for required SDK variables
  - resume arguments must continue to precede image arguments
  - the experimental app-server client now mirrors the Python `codex_app_server` request surface for thread, turn, model, and initialize operations
  - generated `AppServerV2` wrappers and notification payload mapping are derived from the vendored v2 protocol schema and Python notification registry
  - default app-server server-request behavior matches Python: approval requests accept by default and unknown methods return an empty object result
  - upstream app-server `origin/main` reviewed at `527244910fb851cea6147334dbc08f8fbce4cb9d` on `2026-03-24`
- Intentional deviations:
  - Swift uses task cancellation rather than exposing an `AbortSignal`-style turn option
  - Swift keeps CLI discovery `PATH`-based or explicitly overridden instead of npm package resolution
  - Swift remains async-only and does not add Python-style synchronous wrappers
  - generated Swift models are thin `JSONValue` wrappers with typed convenience accessors rather than field-by-field value structs
