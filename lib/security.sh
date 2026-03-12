#!/usr/bin/env bash

SECURITY_ISSUE_COUNT=0
SECURITY_WARN_COUNT=0
SECURITY_FIX_COUNT=0

sec_pass() {
  printf 'check=ok scope=%s\n' "$1"
}

sec_warn() {
  SECURITY_WARN_COUNT=$((SECURITY_WARN_COUNT + 1))
  printf 'check=warn scope=%s reason=%s\n' "$1" "$2"
}

sec_fail() {
  SECURITY_ISSUE_COUNT=$((SECURITY_ISSUE_COUNT + 1))
  printf 'check=FAIL scope=%s reason=%s\n' "$1" "$2"
}

sec_fixed() {
  SECURITY_FIX_COUNT=$((SECURITY_FIX_COUNT + 1))
  printf 'fix=applied scope=%s action=%s\n' "$1" "$2"
}

# ── File permission checks ──

audit_file_permissions() {
  local fix_mode="$1"

  local dir_targets=("$CONFIG_DIR" "$STATE_DIR" "$BACKUP_DIR" "$SNAPSHOT_DIR")
  for d in "${dir_targets[@]}"; do
    if [[ -d "$d" ]]; then
      local dmode
      dmode="$(get_file_mode "$d")"
      if [[ "$dmode" != "700" ]]; then
        sec_fail "dir_permission" "${d}=${dmode}_should_be_700"
        if [[ "$fix_mode" == "fix" ]]; then
          chmod 700 "$d" 2>/dev/null && sec_fixed "dir_permission" "chmod_700_${d##*/}"
        fi
      else
        sec_pass "dir_permission_${d##*/}"
      fi
    fi
  done

  local file_targets=("$ENV_FILE" "$SECRETS_FILE" "$POLICY_FILE")
  for f in "${file_targets[@]}"; do
    if [[ -f "$f" ]]; then
      local fmode
      fmode="$(get_file_mode "$f")"
      if [[ "$fmode" != "600" ]]; then
        sec_fail "file_permission" "${f##*/}=${fmode}_should_be_600"
        if [[ "$fix_mode" == "fix" ]]; then
          chmod 600 "$f" 2>/dev/null && sec_fixed "file_permission" "chmod_600_${f##*/}"
        fi
      else
        sec_pass "file_permission_${f##*/}"
      fi
    fi
  done

  local openclaw_env="${HOME}/.openclaw/.env"
  if [[ -f "$openclaw_env" ]]; then
    local oemode
    oemode="$(get_file_mode "$openclaw_env")"
    if [[ "$oemode" != "600" ]]; then
      sec_fail "file_permission" "openclaw_.env=${oemode}_should_be_600"
      if [[ "$fix_mode" == "fix" ]]; then
        chmod 600 "$openclaw_env" 2>/dev/null && sec_fixed "file_permission" "chmod_600_openclaw_.env"
      fi
    else
      sec_pass "file_permission_openclaw_.env"
    fi
  fi

  local openclaw_config="${HOME}/.openclaw/openclaw.json"
  if [[ -f "$openclaw_config" ]]; then
    local ocmode
    ocmode="$(get_file_mode "$openclaw_config")"
    local ocmode_num="${ocmode##*=}"
    case "$ocmode" in
      600|640|644)
        sec_pass "file_permission_openclaw.json"
        ;;
      *)
        if [[ "${ocmode: -1}" != "0" ]] && [[ "${ocmode:0:1}" != "6" ]]; then
          sec_warn "file_permission" "openclaw.json=${ocmode}"
        else
          sec_pass "file_permission_openclaw.json"
        fi
        ;;
    esac
  fi
}

get_file_mode() {
  local target="$1"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    stat -f '%Lp' "$target" 2>/dev/null || printf 'unknown'
  else
    stat -c '%a' "$target" 2>/dev/null || printf 'unknown'
  fi
}

# ── Secret leak scanning ──

audit_secret_leaks() {
  local fix_mode="$1"

  local api_keys=()
  if [[ -f "$SECRETS_FILE" ]] && command_exists jq; then
    while IFS=$'\t' read -r key value; do
      [[ -n "$value" ]] || continue
      [[ ${#value} -ge 8 ]] || continue
      api_keys+=("$value")
    done < <(jq -r 'to_entries[] | [.key, .value] | @tsv' "$SECRETS_FILE" 2>/dev/null || true)
  fi

  if [[ ${#api_keys[@]} -eq 0 ]]; then
    sec_pass "secret_leak_scan"
    return
  fi

  local leak_found=0

  # Scan log files for leaked keys
  if [[ -d "$LOG_DIR" ]]; then
    for logfile in "$LOG_DIR"/*.log; do
      [[ -f "$logfile" ]] || continue
      for secret in "${api_keys[@]}"; do
        [[ ${#secret} -ge 8 ]] || continue
        if grep -qF "$secret" "$logfile" 2>/dev/null; then
          sec_fail "secret_in_logs" "${logfile##*/}"
          leak_found=1
          if [[ "$fix_mode" == "fix" ]]; then
            local masked
            masked="$(mask_value "$secret")"
            sed -i.bak "s|${secret}|${masked}|g" "$logfile" 2>/dev/null || true
            rm -f "${logfile}.bak"
            sec_fixed "secret_in_logs" "redacted_${logfile##*/}"
          fi
        fi
      done
    done
  fi

  # Scan OpenClaw config for plain-text keys that shouldn't be there
  local openclaw_config="${HOME}/.openclaw/openclaw.json"
  if [[ -f "$openclaw_config" ]]; then
    for secret in "${api_keys[@]}"; do
      [[ ${#secret} -ge 8 ]] || continue
      if grep -qF "$secret" "$openclaw_config" 2>/dev/null; then
        # apiKey in openclaw.json is expected; only warn if file is world-readable
        local cmode
        cmode="$(get_file_mode "$openclaw_config")"
        case "$cmode" in
          *[1-7][1-7])
            sec_warn "apikey_in_world_readable_config" "openclaw.json_mode=${cmode}"
            if [[ "$fix_mode" == "fix" ]]; then
              chmod 600 "$openclaw_config" 2>/dev/null && sec_fixed "config_permission" "chmod_600_openclaw.json"
            fi
            ;;
        esac
      fi
    done
  fi

  if [[ "$leak_found" -eq 0 ]]; then
    sec_pass "secret_leak_scan"
  fi
}

# ── API key validation ──

audit_api_keys() {
  if [[ ! -f "$SECRETS_FILE" ]] || ! command_exists jq; then
    sec_warn "api_key_check" "secrets_file_missing_or_no_jq"
    return
  fi

  local model_key
  model_key="$(jq -r '.["model.api_key"] // empty' "$SECRETS_FILE" 2>/dev/null || true)"

  if [[ -z "$model_key" ]]; then
    sec_warn "api_key" "model.api_key_not_set"
    return
  fi

  if [[ ${#model_key} -lt 10 ]]; then
    sec_fail "api_key_strength" "model.api_key_too_short(${#model_key}_chars)"
    return
  fi

  # Check for common placeholder values
  case "$model_key" in
    sk-test*|test-key*|your-*|YOUR_*|xxx*|placeholder*|changeme*|CHANGE_ME*)
      sec_warn "api_key" "model.api_key_looks_like_placeholder"
      return
      ;;
  esac

  sec_pass "api_key_validation"
}

# ── Network binding audit ──

audit_network_binding() {
  local port
  port="$(gateway_port)"

  local pid
  pid="$(listener_pid_on_port "$port" 2>/dev/null || true)"

  if [[ -z "$pid" ]]; then
    sec_pass "network_binding(service_not_running)"
    return
  fi

  if command_exists lsof; then
    local binding
    binding="$(lsof -iTCP:"$port" -sTCP:LISTEN -P -n 2>/dev/null | grep -v '^COMMAND' || true)"

    if printf '%s' "$binding" | grep -q '\*:'"$port" 2>/dev/null; then
      sec_warn "network_binding" "gateway_listening_on_all_interfaces(0.0.0.0:${port})"
    elif printf '%s' "$binding" | grep -q '0\.0\.0\.0:'"$port" 2>/dev/null; then
      sec_warn "network_binding" "gateway_listening_on_all_interfaces(0.0.0.0:${port})"
    else
      sec_pass "network_binding"
    fi
  elif command_exists ss; then
    local binding
    binding="$(ss -tlnp 2>/dev/null | grep ":${port}" || true)"
    if printf '%s' "$binding" | grep -qE '0\.0\.0\.0:|^\*:|\[::\]:' 2>/dev/null; then
      sec_warn "network_binding" "gateway_listening_on_all_interfaces(port_${port})"
    else
      sec_pass "network_binding"
    fi
  else
    sec_pass "network_binding(unable_to_check)"
  fi
}

# ── Plugin policy audit ──

audit_plugin_policy() {
  require_jq

  if ! jq -e '.plugins.allow | type == "array"' "$POLICY_FILE" >/dev/null 2>&1; then
    sec_fail "plugin_policy" "plugins.allow_missing_or_invalid"
    return
  fi

  if jq -e '.plugins.allow | index("*") != null' "$POLICY_FILE" >/dev/null 2>&1; then
    sec_fail "plugin_policy" "wildcard_in_allowlist"
  else
    sec_pass "plugin_allowlist"
  fi

  if [[ "$(jq -r '.plugins.pinVersions // false' "$POLICY_FILE")" != "true" ]]; then
    sec_warn "plugin_policy" "version_pinning_disabled"
  else
    sec_pass "plugin_version_pinning"
  fi

  # Check for unpinned plugins
  if [[ -s "$PLUGIN_DB_FILE" ]]; then
    local unpinned=0
    while IFS='|' read -r pkg enabled version pinned; do
      [[ -n "${pkg:-}" ]] || continue
      if [[ "$pinned" != "true" ]]; then
        sec_warn "plugin_unpinned" "$pkg"
        unpinned=$((unpinned + 1))
      fi
      if ! policy_allows_plugin "$pkg" 2>/dev/null; then
        sec_fail "plugin_not_in_allowlist" "$pkg"
      fi
    done <"$PLUGIN_DB_FILE"
    if [[ "$unpinned" -eq 0 ]]; then
      sec_pass "all_plugins_pinned"
    fi
  fi
}

# ── Config integrity ──

audit_plugin_security() {
  if [[ ! -s "$PLUGIN_DB_FILE" ]]; then
    sec_pass "plugin_scan(no_plugins)"
    return
  fi

  # shellcheck source=/dev/null
  source "$ROOT_DIR/lib/plugin.sh"

  local any_scanned=0
  while IFS='|' read -r pkg enabled version pinned; do
    [[ -n "${pkg:-}" ]] || continue
    local pkg_dir
    pkg_dir="$(resolve_plugin_dir "$pkg")"
    if [[ -z "$pkg_dir" ]]; then
      continue
    fi

    any_scanned=1
    PLUGIN_SCAN_RISK_COUNT=0
    PLUGIN_SCAN_WARN_COUNT=0

    scan_plugin_package_json "$pkg" "$pkg_dir"
    scan_plugin_source "$pkg" "$pkg_dir"
    scan_plugin_permissions "$pkg" "$pkg_dir"

    if [[ "$PLUGIN_SCAN_RISK_COUNT" -gt 0 ]]; then
      sec_fail "plugin_scan" "${pkg}=DANGEROUS(${PLUGIN_SCAN_RISK_COUNT}_risks)"
    elif [[ "$PLUGIN_SCAN_WARN_COUNT" -gt 0 ]]; then
      sec_warn "plugin_scan" "${pkg}=review(${PLUGIN_SCAN_WARN_COUNT}_warnings)"
    else
      sec_pass "plugin_scan_${pkg}"
    fi
  done <"$PLUGIN_DB_FILE"

  if [[ "$any_scanned" -eq 0 ]]; then
    sec_pass "plugin_scan(none_installed_locally)"
  fi
}

audit_config_integrity() {
  if [[ -f "$SECRETS_FILE" ]]; then
    if jq empty "$SECRETS_FILE" >/dev/null 2>&1; then
      sec_pass "secrets_json_valid"
    else
      sec_fail "config_integrity" "secrets.json_invalid_json"
    fi
  fi

  if [[ -f "$POLICY_FILE" ]]; then
    if jq empty "$POLICY_FILE" >/dev/null 2>&1; then
      sec_pass "policy_json_valid"
    else
      sec_fail "config_integrity" "policy.json_invalid_json"
    fi
  fi

  local openclaw_config="${HOME}/.openclaw/openclaw.json"
  if [[ -f "$openclaw_config" ]]; then
    if jq empty "$openclaw_config" >/dev/null 2>&1; then
      sec_pass "openclaw_json_valid"
    else
      sec_fail "config_integrity" "openclaw.json_invalid_json"
    fi
  fi

  # Check env file has no secrets embedded (key=value where value looks like an API key)
  if [[ -f "$ENV_FILE" ]]; then
    local suspicious=0
    while IFS='=' read -r key value; do
      [[ -n "$key" ]] || continue
      [[ "$key" != \#* ]] || continue
      case "$key" in
        *KEY*|*SECRET*|*TOKEN*|*PASSWORD*)
          if [[ -n "$value" && ${#value} -ge 10 ]]; then
            sec_warn "secret_in_env_file" "${key}"
            suspicious=$((suspicious + 1))
          fi
          ;;
      esac
    done <"$ENV_FILE"
    if [[ "$suspicious" -eq 0 ]]; then
      sec_pass "env_file_no_embedded_secrets"
    fi
  fi
}

# ── Gateway process ownership ──

audit_process_security() {
  local port
  port="$(gateway_port)"
  local pid
  pid="$(listener_pid_on_port "$port" 2>/dev/null || true)"

  if [[ -z "$pid" ]]; then
    return
  fi

  # Warn if gateway is running as root
  if command_exists ps; then
    local proc_user
    proc_user="$(ps -o user= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
    if [[ "$proc_user" == "root" ]]; then
      sec_warn "process_security" "gateway_running_as_root(pid=${pid})"
    else
      sec_pass "process_not_root"
    fi
  fi
}

# ── Main entry ──

simple_openclaw_security() {
  local action="${1:-audit}"
  shift || true

  local fix_mode="check"
  case "$action" in
    harden)
      fix_mode="fix"
      action="audit"
      ;;
  esac

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --fix) fix_mode="fix"; shift ;;
      *)     die "unknown security option: $1" ;;
    esac
  done

  local report="$SECURITY_REPORT_DIR/security-$(timestamp).txt"

  case "$action" in
    audit)
      {
        printf '=== simple-openclaw security audit ===\n'
        printf 'timestamp=%s\n' "$(iso_now)"
        printf 'version=%s\n' "$(current_version)"
        printf 'mode=%s\n\n' "$fix_mode"

        printf '%s\n' '--- File Permissions ---'
        audit_file_permissions "$fix_mode"
        printf '\n'

        printf '%s\n' '--- Secret Leak Scan ---'
        audit_secret_leaks "$fix_mode"
        printf '\n'

        printf '%s\n' '--- API Key Validation ---'
        audit_api_keys
        printf '\n'

        printf '%s\n' '--- Network Binding ---'
        audit_network_binding
        printf '\n'

        printf '%s\n' '--- Plugin Policy ---'
        audit_plugin_policy
        printf '\n'

        printf '%s\n' '--- Plugin Security Scan ---'
        audit_plugin_security
        printf '\n'

        printf '%s\n' '--- Config Integrity ---'
        audit_config_integrity
        printf '\n'

        printf '%s\n' '--- Process Security ---'
        audit_process_security
        printf '\n'

        printf '=== Summary ===\n'
        printf 'issues=%d warnings=%d' "$SECURITY_ISSUE_COUNT" "$SECURITY_WARN_COUNT"
        if [[ "$fix_mode" == "fix" ]]; then
          printf ' fixed=%d' "$SECURITY_FIX_COUNT"
        fi
        printf '\n'

        if [[ "$SECURITY_ISSUE_COUNT" -gt 0 ]]; then
          printf 'status=FAIL\n'
        elif [[ "$SECURITY_WARN_COUNT" -gt 0 ]]; then
          printf 'status=WARN\n'
        else
          printf 'status=PASS\n'
        fi

        if [[ "$fix_mode" != "fix" && "$SECURITY_ISSUE_COUNT" -gt 0 ]]; then
          printf '\nRun "simple-openclaw security harden" to auto-fix issues.\n'
        fi
      } | tee "$report"

      info "security report saved to $report"
      ;;
    *)
      die "unknown security action: $action"
      ;;
  esac
}
