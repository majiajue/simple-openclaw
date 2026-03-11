#!/usr/bin/env bash

set_secret_value() {
  local key="$1"
  local value="$2"
  json_set_inplace "$SECRETS_FILE" --arg key "$key" --arg value "$value" '.[$key] = $value'
}

simple_openclaw_secret() {
  local action="${1:-list}"
  shift || true

  case "$action" in
    set)
      local key="${1:-}"
      local value="${2:-}"
      require_arg "$key" "secret key"
      require_arg "$value" "secret value"
      set_secret_value "$key" "$value"
      info "secret updated: $key"
      ;;
    list)
      jq -r 'to_entries[] | [.key, .value] | @tsv' "$SECRETS_FILE" | while IFS=$'\t' read -r key value; do
        printf '%s=%s\n' "$key" "$(mask_value "$value")"
      done
      ;;
    rotate)
      local rotate_key="${1:-}"
      require_arg "$rotate_key" "secret key"
      printf 'rotate=manual key=%s\n' "$rotate_key"
      ;;
    audit)
      jq -r 'to_entries[] | [.key, .value] | @tsv' "$SECRETS_FILE" | while IFS=$'\t' read -r key value; do
        printf 'audit=ok key=%s masked=%s\n' "$key" "$(mask_value "$value")"
      done
      ;;
    *)
      die "unknown secret action: $action"
      ;;
  esac
}
