#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run_codex_bridge_tailscale.sh [--port PORT] [--codex PATH] [--swift-run-args ...]

Starts CodexBridge on 127.0.0.1 and publishes it to the current tailnet with
`tailscale serve`, so clients can use the machine's `.ts.net` URL.

Examples:
  Scripts/run_codex_bridge_tailscale.sh
  Scripts/run_codex_bridge_tailscale.sh --port 4000
  Scripts/run_codex_bridge_tailscale.sh --codex /opt/homebrew/bin/codex
EOF
}

PORT=31337
CODEX_PATH=""
SWIFT_RUN_ARGS=()

require_value() {
  local flag="$1"
  if [[ $# -lt 2 || -z ${2-} ]]; then
    echo "missing value for ${flag}" >&2
    usage >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      require_value "$1" "${2-}"
      if [[ ! "$2" =~ ^[0-9]+$ ]] || [[ "$2" == "0" ]]; then
        echo "invalid port: $2" >&2
        usage >&2
        exit 1
      fi
      PORT="$2"
      shift 2
      ;;
    --codex)
      require_value "$1" "${2-}"
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

TAILSCALE_DNS_NAME="$(
  tailscale status --json 2>/dev/null | ruby -rjson -e '
    status = JSON.parse($stdin.read)
    dns_name = status.dig("Self", "DNSName")
    abort if dns_name.nil? || dns_name.empty?
    puts dns_name.sub(/\.$/, "")
  '
)"
if [[ -z "${TAILSCALE_DNS_NAME}" || "${TAILSCALE_DNS_NAME}" == "null" ]]; then
  echo "could not determine Tailscale DNS name" >&2
  exit 1
fi

echo "Publishing CodexBridge on https://${TAILSCALE_DNS_NAME}/" >&2
echo "Local bridge will listen on http://127.0.0.1:${PORT}" >&2
tailscale serve -bg "${PORT}" >&2

CMD=(swift run "${SWIFT_RUN_ARGS[@]}" CodexBridge --host "127.0.0.1" --port "${PORT}")
if [[ -n "${CODEX_PATH}" ]]; then
  CMD+=(--codex "${CODEX_PATH}")
fi

exec "${CMD[@]}"
