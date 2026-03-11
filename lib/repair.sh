#!/usr/bin/env bash

simple_openclaw_repair() {
  local action="${1:-}"
  local port
  port="$(env_get OPENCLAW_GATEWAY_PORT || printf '%s' "$DEFAULT_GATEWAY_PORT")"

  case "$action" in
    stale-process)
      if command_exists lsof; then
        lsof -nP -iTCP:"$port" -sTCP:LISTEN || true
      fi
      printf 'repair=inspect target=stale-process port=%s\n' "$port"
      ;;
    port)
      if command_exists lsof; then
        lsof -nP -iTCP:"$port" || true
      fi
      printf 'repair=inspect target=port port=%s\n' "$port"
      ;;
    service)
      cat "$SERVICE_STATE_FILE"
      printf '\nrepair=inspect target=service\n'
      ;;
    *)
      die "unknown repair action: $action"
      ;;
  esac
}
