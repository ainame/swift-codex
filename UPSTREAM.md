# Upstream Reference

This repository ports the TypeScript SDK from the [`openai/codex`](https://github.com/openai/codex) monorepo, primarily from [`sdk/typescript`](https://github.com/openai/codex/tree/main/sdk/typescript).

## Recorded Upstream Basis

- Upstream repository: `openai/codex`
- Upstream SDK path: `sdk/typescript`
- Vendored upstream checkout: `vendor/openai-codex`
- Vendored upstream commit: `06e06ab173a7912de1661f6678eaf8d1c04da170`
- Reference commit SHA: `3293538e128e02ca24d5e9913af986ac68405b00`
- Reference commit URL: `https://github.com/openai/codex/commit/3293538e128e02ca24d5e9913af986ac68405b00`
- Last reviewed date: `2026-03-21`

The vendored submodule commit above identifies which upstream checkout is bundled in this repository. The exact upstream commit that the current Swift implementation was originally based on was not recorded before this file was added. Do not replace the reference commit placeholders unless you have verified the port basis being referenced.

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

- Vendored checkout: `vendor/openai-codex` at `06e06ab173a7912de1661f6678eaf8d1c04da170`
- Reference commit: `3293538e128e02ca24d5e9913af986ac68405b00`
- Reviewed upstream files:
  - `sdk/typescript/src/exec.ts`
  - `sdk/typescript/tests/exec.test.ts`
  - `sdk/typescript/tests/run.test.ts`
  - `sdk/typescript/tests/setupCodexHome.ts`
  - `sdk/typescript/tests/testCodex.ts`
  - `sdk/typescript/README.md`
- Reviewed upstream features:
  - `baseUrl` now maps to `--config openai_base_url=...` rather than `OPENAI_BASE_URL`
  - explicit environment overrides must remain isolated from the host environment except for required SDK variables
  - resume arguments must continue to precede image arguments
- Intentional deviations:
  - Swift uses task cancellation rather than exposing an `AbortSignal`-style turn option
  - Swift keeps CLI discovery `PATH`-based or explicitly overridden instead of npm package resolution
