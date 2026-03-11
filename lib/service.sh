#!/usr/bin/env bash

service_detect_runtime() {
  local port pid
  port="$(gateway_port)"
  pid="$(listener_pid_on_port "$port" || true)"
  if [[ -n "$pid" ]]; then
    printf 'running'
  elif pid_is_running "$(read_gateway_pid || true)"; then
    printf 'starting'
  else
    printf 'stopped'
  fi
}

simple_openclaw_service() {
  local action="${1:-status}"
  local runtime_state port pid manager gateway_cmd tracked_pid
  runtime_state="$(service_detect_runtime)"
  port="$(gateway_port)"
  pid="$(listener_pid_on_port "$port" || true)"
  manager="$(env_get OPENCLAW_SERVICE_MANAGER || true)"
  gateway_cmd="$(gateway_command || true)"
  tracked_pid="$(read_gateway_pid || true)"
  [[ -n "$manager" ]] || manager="$(detect_service_manager)"

  case "$action" in
    start)
      if [[ -n "$gateway_cmd" ]]; then
        if pid_is_running "$tracked_pid" || [[ -n "$pid" ]]; then
          warn "gateway already appears to be running"
        else
          nohup bash -lc "export PATH=/usr/local/bin:\$PATH; $gateway_cmd" >>"$LOG_DIR/openclaw-gateway.log" 2>&1 &
          record_gateway_pid "$!"
          info "started gateway command: $gateway_cmd"
        fi
      else
        warn "OPENCLAW_GATEWAY_CMD is not configured"
      fi
      write_service_state "running" "start" "$(service_detect_runtime)" "$(read_gateway_pid || true)"
      ;;
    stop)
      if pid_is_running "$tracked_pid"; then
        kill "$tracked_pid" >/dev/null 2>&1 || true
      fi
      clear_gateway_pid
      write_service_state "stopped" "stop" "$(service_detect_runtime)" ""
      info "stop requested"
      ;;
    restart)
      simple_openclaw_service stop
      sleep 1
      simple_openclaw_service start
      write_service_state "running" "restart" "$(service_detect_runtime)" "$(read_gateway_pid || true)"
      ;;
    status)
      printf 'desired=%s\n' "$(awk -F'"' '/"desired"/ {print $4}' "$SERVICE_STATE_FILE")"
      printf 'runtime=%s\n' "$runtime_state"
      printf 'port=%s\n' "$port"
      printf 'listener_pid=%s\n' "${pid:-none}"
      printf 'tracked_pid=%s\n' "${tracked_pid:-none}"
      printf 'manager=%s\n' "$manager"
      printf 'gateway_cmd=%s\n' "${gateway_cmd:-unset}"
      printf 'updated_at=%s\n' "$(awk -F'"' '/"updatedAt"/ {print $4}' "$SERVICE_STATE_FILE")"
      ;;
    *)
      die "unknown service action: $action"
      ;;
  esac
}
