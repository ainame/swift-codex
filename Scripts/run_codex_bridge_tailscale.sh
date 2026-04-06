#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run_codex_bridge_tailscale.sh [--port PORT] [--codex PATH] [--swift-run-args ...]

Looks up the machine's primary Tailscale IPv4 address and starts CodexBridge
bound to that address so clients on the same tailnet can connect directly.

Examples:
  Scripts/run_codex_bridge_tailscale.sh
  Scripts/run_codex_bridge_tailscale.sh --port 4000
  Scripts/run_codex_bridge_tailscale.sh --codex /opt/homebrew/bin/codex
EOF
}

PORT=31337
CODEX_PATH=""
SWIFT_RUN_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      PORT="$2"
      shift 2
      ;;
    --codex)
      CODEX_PATH="$2"
      shift 2
      ;;
    --swift-run-args)
      shift
      SWIFT_RUN_ARGS=("$@")
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v tailscale >/dev/null 2>&1; then
  echo "tailscale command not found" >&2
  exit 1
fi

TAILSCALE_IP="$(tailscale ip -4 | head -n 1)"
if [[ -z "${TAILSCALE_IP}" ]]; then
  echo "could not determine Tailscale IPv4 address" >&2
  exit 1
fi

echo "Starting CodexBridge on ${TAILSCALE_IP}:${PORT}" >&2
echo "Clients on the same tailnet can connect to ${TAILSCALE_IP}:${PORT}" >&2

CMD=(swift run "${SWIFT_RUN_ARGS[@]}" CodexBridge --host "${TAILSCALE_IP}" --port "${PORT}")
if [[ -n "${CODEX_PATH}" ]]; then
  CMD+=(--codex "${CODEX_PATH}")
fi

exec "${CMD[@]}"
