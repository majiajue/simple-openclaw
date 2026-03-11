#!/usr/bin/env bash

WATCHDOG_STATE_FILE="$STATE_DIR/watchdog.state"

simple_openclaw_watchdog() {
  local action="${1:-status}"

  case "$action" in
    enable)
      printf 'enabled\n' >"$WATCHDOG_STATE_FILE"
      info "watchdog enabled"
      ;;
    disable)
      printf 'disabled\n' >"$WATCHDOG_STATE_FILE"
      info "watchdog disabled"
      ;;
    status)
      if [[ -f "$WATCHDOG_STATE_FILE" ]]; then
        printf 'watchdog=%s\n' "$(tr -d '[:space:]' <"$WATCHDOG_STATE_FILE")"
      else
        printf 'watchdog=disabled\n'
      fi
      ;;
    *)
      die "unknown watchdog action: $action"
      ;;
  esac
}
