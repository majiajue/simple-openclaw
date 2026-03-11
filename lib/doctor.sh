#!/usr/bin/env bash

doctor_report_file() {
  printf '%s/doctor-%s.txt' "$DOCTOR_REPORT_DIR" "$(timestamp)"
}

doctor_check_channel() {
  local file="$1"
  local name missing plugin_name
  name="$(basename "$file" .json)"
  plugin_name="$(channel_plugin_name "$file" || true)"
  missing="$(channel_missing_keys "$file" | tr '\n' ',' | sed 's/,$//')"
  if [[ -n "$missing" ]]; then
    printf 'check=warn scope=channel name=%s missing=%s\n' "$name" "$missing"
  else
    printf 'check=ok scope=channel name=%s\n' "$name"
  fi
  if [[ -n "$plugin_name" ]]; then
    if policy_allows_plugin "$plugin_name"; then
      printf 'check=ok scope=channel-plugin name=%s plugin=%s\n' "$name" "$plugin_name"
    else
      printf 'check=warn scope=channel-plugin name=%s plugin=%s reason=not_in_allowlist\n' "$name" "$plugin_name"
    fi
  fi
}

run_doctor() {
  local fix_mode="$1"
  local report port listener_pid tracked_pid
  report="$(doctor_report_file)"
  port="$(gateway_port)"
  listener_pid="$(listener_pid_on_port "$port" || true)"
  tracked_pid="$(read_gateway_pid || true)"

  {
    printf 'simple-openclaw doctor report\n'
    printf 'timestamp=%s\n' "$(iso_now)"
    printf 'version=%s\n' "$(current_version)"
    if command_exists node; then
      printf 'node=%s\n' "$(node -v)"
      if [[ "$(node_major_version)" -lt 22 ]]; then
        printf 'check=fail scope=node reason=unsupported_version\n'
      else
        printf 'check=ok scope=node\n'
      fi
    else
      printf 'node=missing\n'
      printf 'check=fail scope=node reason=missing\n'
    fi
    if command_exists npm; then
      printf 'npm=%s\n' "$(npm -v)"
      printf 'check=ok scope=npm\n'
    else
      printf 'npm=missing\n'
      printf 'check=fail scope=npm reason=missing\n'
    fi
    if [[ -n "$(openclaw_bin)" ]]; then
      printf 'openclaw_bin=%s\n' "$(openclaw_bin)"
      printf 'check=ok scope=openclaw_bin\n'
    else
      printf 'openclaw_bin=missing\n'
      printf 'check=warn scope=openclaw_bin reason=missing\n'
    fi
    if jq empty "$SECRETS_FILE" >/dev/null 2>&1; then
      printf 'check=ok scope=secrets_json\n'
    else
      printf 'check=fail scope=secrets_json reason=invalid_json\n'
    fi
    if jq empty "$POLICY_FILE" >/dev/null 2>&1; then
      printf 'check=ok scope=policy_json\n'
    else
      printf 'check=fail scope=policy_json reason=invalid_json\n'
    fi
    printf 'env_file=%s\n' "$ENV_FILE"
    printf 'policy_file=%s\n' "$POLICY_FILE"
    printf 'channel_count=%s\n' "$(find "$CHANNEL_DIR" -maxdepth 1 -name '*.json' | wc -l | tr -d ' ')"
    printf 'plugin_records=%s\n' "$(grep -c '|' "$PLUGIN_DB_FILE" || true)"
    printf 'gateway_port=%s\n' "$port"
    printf 'listener_pid=%s\n' "${listener_pid:-none}"
    printf 'tracked_pid=%s\n' "${tracked_pid:-none}"
    if [[ -n "$listener_pid" ]]; then
      printf 'check=ok scope=probe-port\n'
    else
      printf 'check=warn scope=probe-port reason=no_listener\n'
    fi
    if [[ -n "$tracked_pid" && -z "$listener_pid" ]]; then
      if pid_is_running "$tracked_pid"; then
        printf 'check=warn scope=service reason=tracked_pid_without_listener\n'
      else
        printf 'check=warn scope=service reason=stale_pid\n'
      fi
    fi
    while IFS= read -r channel; do
      [[ -n "$channel" ]] || continue
      doctor_check_channel "$channel"
    done < <(find "$CHANNEL_DIR" -maxdepth 1 -name '*.json' | sort)
  } >"$report"

  if [[ "$fix_mode" == "fix" ]]; then
    ensure_runtime_dirs
    chmod 700 "$CONFIG_DIR" "$STATE_DIR" >/dev/null 2>&1 || true
    chmod 600 "$ENV_FILE" "$SECRETS_FILE" "$POLICY_FILE" >/dev/null 2>&1 || true
    if [[ -n "$tracked_pid" && -z "$listener_pid" ]] && ! pid_is_running "$tracked_pid"; then
      clear_gateway_pid
      printf 'fix=applied scope=service action=clear_stale_pid\n' >>"$report"
    fi
  fi

  cat "$report"
  info "doctor report written to $report"
}

simple_openclaw_doctor() {
  local action="${1:-doctor}"
  shift || true

  case "$action" in
    health)
      run_doctor "check"
      ;;
    doctor)
      if [[ "${1:-}" == "--fix" ]]; then
        run_doctor "fix"
      else
        run_doctor "check"
      fi
      ;;
    *)
      die "unknown doctor action: $action"
      ;;
  esac
}
