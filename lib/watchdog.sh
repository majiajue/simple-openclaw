#!/usr/bin/env bash

WATCHDOG_STATE_FILE="$STATE_DIR/watchdog.state"

watchdog_log() {
  local level="$1"
  shift
  printf '[%s] [%s] %s\n' "$(iso_now)" "$level" "$*" >>"$WATCHDOG_LOG"
}

write_watchdog_status() {
  local state="$1"
  local failures="$2"
  local restarts="$3"
  local last_check="$4"
  cat >"$WATCHDOG_STATUS_FILE" <<EOF
{
  "state": "$state",
  "consecutiveFailures": $failures,
  "restartCount": $restarts,
  "lastCheck": "$last_check",
  "updatedAt": "$(iso_now)"
}
EOF
}

watchdog_loop() {
  local interval failures=0 restarts=0 max_retries cooldown last_restart=0

  interval="$(env_get WATCHDOG_INTERVAL 2>/dev/null || printf '30')"
  max_retries="$(env_get WATCHDOG_MAX_RETRIES 2>/dev/null || printf '5')"
  cooldown="$(env_get WATCHDOG_COOLDOWN 2>/dev/null || printf '60')"

  watchdog_log "INFO" "watchdog started interval=${interval}s max_retries=${max_retries} cooldown=${cooldown}s"

  while true; do
    local now_epoch check_result
    now_epoch="$(date +%s)"

    # Source probe module and run health check
    # shellcheck source=/dev/null
    source "$ROOT_DIR/lib/probe.sh"
    check_result="$(simple_openclaw_probe 2>/dev/null)" || true

    local now_ts
    now_ts="$(iso_now)"

    if echo "$check_result" | grep -q 'probe=ok\|probe=degraded'; then
      if [[ "$failures" -gt 0 ]]; then
        watchdog_log "INFO" "service recovered after ${failures} failures"
      fi
      failures=0
      write_watchdog_status "healthy" "$failures" "$restarts" "$now_ts"
    else
      failures=$((failures + 1))
      watchdog_log "WARN" "probe failed (${failures}/${max_retries})"
      write_watchdog_status "unhealthy" "$failures" "$restarts" "$now_ts"

      if [[ "$failures" -ge "$max_retries" ]]; then
        watchdog_log "ERROR" "max retries reached, giving up"
        write_watchdog_status "gave_up" "$failures" "$restarts" "$now_ts"
        break
      fi

      # Attempt restart if cooldown has elapsed
      local elapsed=$((now_epoch - last_restart))
      if [[ "$elapsed" -ge "$cooldown" ]]; then
        watchdog_log "INFO" "attempting restart (attempt #$((restarts + 1)))"
        # shellcheck source=/dev/null
        source "$ROOT_DIR/lib/service.sh"
        simple_openclaw_service restart >/dev/null 2>&1 || true
        restarts=$((restarts + 1))
        last_restart="$(date +%s)"
        write_watchdog_status "restarting" "$failures" "$restarts" "$now_ts"
      fi
    fi

    sleep "$interval"
  done

  watchdog_log "INFO" "watchdog loop exited"
}

watchdog_start() {
  # Check not already running
  if [[ -f "$WATCHDOG_PID_FILE" ]]; then
    local existing_pid
    existing_pid="$(tr -d '[:space:]' <"$WATCHDOG_PID_FILE")"
    if pid_is_running "$existing_pid"; then
      die "watchdog already running (pid: $existing_pid)"
    fi
  fi

  # Launch in background
  watchdog_loop &
  local wpid=$!
  printf '%s\n' "$wpid" >"$WATCHDOG_PID_FILE"
  printf 'running\n' >"$WATCHDOG_STATE_FILE"
  write_watchdog_status "starting" 0 0 "$(iso_now)"
  watchdog_log "INFO" "watchdog started pid=$wpid"
  info "watchdog started (pid: $wpid)"
}

watchdog_stop() {
  if [[ ! -f "$WATCHDOG_PID_FILE" ]]; then
    info "watchdog is not running"
    return 0
  fi

  local wpid
  wpid="$(tr -d '[:space:]' <"$WATCHDOG_PID_FILE")"

  if pid_is_running "$wpid"; then
    kill "$wpid" >/dev/null 2>&1 || true
    watchdog_log "INFO" "watchdog stopped pid=$wpid"
  fi

  rm -f "$WATCHDOG_PID_FILE"
  printf 'stopped\n' >"$WATCHDOG_STATE_FILE"
  write_watchdog_status "stopped" 0 0 "$(iso_now)"
  info "watchdog stopped"
}

watchdog_status() {
  local state="stopped"
  if [[ -f "$WATCHDOG_STATE_FILE" ]]; then
    state="$(tr -d '[:space:]' <"$WATCHDOG_STATE_FILE")"
  fi

  local wpid="none"
  if [[ -f "$WATCHDOG_PID_FILE" ]]; then
    wpid="$(tr -d '[:space:]' <"$WATCHDOG_PID_FILE")"
    if ! pid_is_running "$wpid"; then
      wpid="${wpid} (dead)"
      state="stopped"
    fi
  fi

  printf 'watchdog=%s\n' "$state"
  printf 'pid=%s\n' "$wpid"

  if [[ -f "$WATCHDOG_STATUS_FILE" ]]; then
    printf 'consecutive_failures=%s\n' "$(jq -r '.consecutiveFailures // 0' "$WATCHDOG_STATUS_FILE")"
    printf 'restart_count=%s\n' "$(jq -r '.restartCount // 0' "$WATCHDOG_STATUS_FILE")"
    printf 'last_check=%s\n' "$(jq -r '.lastCheck // "never"' "$WATCHDOG_STATUS_FILE")"
  fi

  local interval cooldown max_retries
  interval="$(env_get WATCHDOG_INTERVAL 2>/dev/null || printf '30')"
  max_retries="$(env_get WATCHDOG_MAX_RETRIES 2>/dev/null || printf '5')"
  cooldown="$(env_get WATCHDOG_COOLDOWN 2>/dev/null || printf '60')"
  printf 'interval=%ss\n' "$interval"
  printf 'max_retries=%s\n' "$max_retries"
  printf 'cooldown=%ss\n' "$cooldown"
}

watchdog_show_log() {
  if [[ ! -f "$WATCHDOG_LOG" ]]; then
    info "no watchdog log yet"
    return 0
  fi
  tail -50 "$WATCHDOG_LOG"
}

simple_openclaw_watchdog() {
  local action="${1:-status}"

  case "$action" in
    start)
      watchdog_start
      ;;
    stop)
      watchdog_stop
      ;;
    status)
      watchdog_status
      ;;
    log)
      watchdog_show_log
      ;;
    # Backward compatibility
    enable)
      warn "deprecated: use 'watchdog start' instead"
      watchdog_start
      ;;
    disable)
      warn "deprecated: use 'watchdog stop' instead"
      watchdog_stop
      ;;
    *)
      die "unknown watchdog action: $action"
      ;;
  esac
}
