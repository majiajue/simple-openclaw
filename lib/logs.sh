#!/usr/bin/env bash

simple_openclaw_logs() {
  local action="${1:-}"
  local app_log="$LOG_DIR/simple-openclaw.log"
  touch "$app_log"

  case "$action" in
    --follow)
      tail -f "$app_log"
      ;;
    --since)
      local window="${2:-1h}"
      printf 'logs_since=%s file=%s\n' "$window" "$app_log"
      tail -n 50 "$app_log"
      ;;
    "" )
      tail -n 50 "$app_log"
      ;;
    *)
      die "unknown logs option: $action"
      ;;
  esac
}
