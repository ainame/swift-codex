# Upstream Reference

This repository ports the TypeScript SDK from the [`openai/codex`](https://github.com/openai/codex) monorepo, primarily from [`sdk/typescript`](https://github.com/openai/codex/tree/main/sdk/typescript).

## Recorded Upstream Basis

- Upstream repository: `openai/codex`
- Upstream SDK path: `sdk/typescript`
- Vendored upstream checkout: `vendor/openai-codex`
- Vendored upstream commit: `c1defcc98cf9c6b9001e86d8d13e5b5ec9488510`
- Reference commit SHA: not yet recorded
- Reference commit URL: not yet recorded
- Last reviewed date: not yet recorded

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

- Vendored checkout: `vendor/openai-codex` at `c1defcc98cf9c6b9001e86d8d13e5b5ec9488510`
- Reference commit: not yet recorded
- Reviewed upstream files: none recorded
- Intentional deviations: none recorded
