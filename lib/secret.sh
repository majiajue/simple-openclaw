#!/usr/bin/env bash

set_secret_value() {
  local key="$1"
  local value="$2"
  json_set_inplace "$SECRETS_FILE" --arg key "$key" --arg value "$value" '.[$key] = $value'
}

sync_openclaw_env_secret() {
  local key="$1"
  local value="$2"
  local openclaw_env="${HOME}/.openclaw/.env"

  if [[ "$key" == "model.api_key" ]]; then
    local provider
    provider="$(env_get OPENCLAW_MODEL_PROVIDER || printf 'openai-compatible')"

    mkdir -p "${HOME}/.openclaw"

    local env_key
    case "$provider" in
      anthropic) env_key="ANTHROPIC_API_KEY" ;;
      openai)    env_key="OPENAI_API_KEY" ;;
      *)         env_key="OPENAI_API_KEY" ;;
    esac

    if [[ -f "$openclaw_env" ]] && grep -q "^${env_key}=" "$openclaw_env"; then
      sed -i.bak "s|^${env_key}=.*|${env_key}=${value}|" "$openclaw_env"
      rm -f "${openclaw_env}.bak"
    else
      printf '%s=%s\n' "$env_key" "$value" >>"$openclaw_env"
    fi
    chmod 600 "$openclaw_env"
  fi
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
      sync_openclaw_env_secret "$key" "$value"
      if [[ "$key" == "model.api_key" ]]; then
        # shellcheck source=/dev/null
        source "$ROOT_DIR/lib/model.sh"
        sync_openclaw_model_config
      fi
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
