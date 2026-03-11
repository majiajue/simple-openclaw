#!/usr/bin/env bash

channel_template() {
  local name="$1"
  local template="$ROOT_DIR/templates/channel.${name}.json"
  if [[ -f "$template" ]]; then
    printf '%s' "$template"
  else
    printf '%s' "$ROOT_DIR/templates/channel.generic.json"
  fi
}

channel_seed_file() {
  local name="$1"
  local target="$2"
  jq --arg name "$name" '.name = $name | .credentials = (.credentials // {})' "$(channel_template "$name")" >"$target"
}

simple_openclaw_channel() {
  local action="${1:-list}"
  local name
  shift || true

  case "$action" in
    list)
      find "$CHANNEL_DIR" -maxdepth 1 -name '*.json' -exec basename {} .json \; | sort
      ;;
    add)
      name="${1:-}"
      require_arg "$name" "channel name"
      channel_seed_file "$name" "$(channel_file "$name")"
      env_set "OPENCLAW_DEFAULT_CHANNEL" "$name"
      info "channel added: $name"
      ;;
    edit)
      name="${1:-}"
      require_arg "$name" "channel name"
      [[ -f "$(channel_file "$name")" ]] || die "channel not found: $name"
      if [[ "${2:-}" == "--set" ]]; then
        require_arg "${3:-}" "key=value"
        local key="${3%%=*}"
        local value="${3#*=}"
        json_set_inplace "$(channel_file "$name")" --arg key "$key" --arg value "$value" '.credentials[$key] = $value'
        info "channel credential updated: $name $key"
      else
        info "edit $(channel_file "$name") with your preferred editor"
        sed -n '1,160p' "$(channel_file "$name")"
      fi
      ;;
    remove)
      name="${1:-}"
      require_arg "$name" "channel name"
      rm -f "$(channel_file "$name")"
      info "channel removed: $name"
      ;;
    test)
      name="${1:-}"
      local file plugin_name missing allow_status
      require_arg "$name" "channel name"
      file="$(channel_file "$name")"
      [[ -f "$file" ]] || die "channel not found: $name"
      plugin_name="$(channel_plugin_name "$file" || true)"
      missing="$(channel_missing_keys "$file" | tr '\n' ',' | sed 's/,$//')"
      if [[ -n "$plugin_name" ]] && policy_allows_plugin "$plugin_name"; then
        allow_status="allowed"
      else
        allow_status="blocked"
      fi
      if [[ -n "$missing" ]]; then
        printf 'channel=%s status=warn plugin=%s allow=%s missing=%s\n' "$name" "${plugin_name:-none}" "$allow_status" "$missing"
      else
        printf 'channel=%s status=ok plugin=%s allow=%s\n' "$name" "${plugin_name:-none}" "$allow_status"
      fi
      ;;
    *)
      die "unknown channel action: $action"
      ;;
  esac
}
