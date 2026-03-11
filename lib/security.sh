#!/usr/bin/env bash

simple_openclaw_security() {
  local action="${1:-audit}"
  local report="$SECURITY_REPORT_DIR/security-$(timestamp).txt"

  case "$action" in
    audit|"")
      {
        printf 'policy_file=%s\n' "$POLICY_FILE"
        printf 'config_dir_mode=%s\n' "$(stat -f '%Lp' "$CONFIG_DIR" 2>/dev/null || printf 'unknown')"
        printf 'secrets_file_mode=%s\n' "$(stat -f '%Lp' "$SECRETS_FILE" 2>/dev/null || printf 'unknown')"
        if jq -e '.plugins.allow | type == "array"' "$POLICY_FILE" >/dev/null 2>&1; then
          printf 'plugins_allow=present\n'
          if jq -e '.plugins.allow | index("*") != null' "$POLICY_FILE" >/dev/null 2>&1; then
            printf 'check=warn scope=plugins.allow reason=wildcard\n'
          else
            printf 'check=ok scope=plugins.allow\n'
          fi
        else
          printf 'plugins_allow=missing\n'
        fi
        if [[ "$(jq -r '.plugins.pinVersions // false' "$POLICY_FILE")" == "true" ]]; then
          printf 'check=ok scope=pin_versions\n'
        else
          printf 'check=warn scope=pin_versions reason=disabled\n'
        fi
      } | tee "$report"
      ;;
    harden)
      chmod 700 "$CONFIG_DIR" "$STATE_DIR" >/dev/null 2>&1 || true
      chmod 600 "$ENV_FILE" "$SECRETS_FILE" "$POLICY_FILE" >/dev/null 2>&1 || true
      printf 'security=hardened\n' | tee "$report"
      ;;
    *)
      die "unknown security action: $action"
      ;;
  esac
}
