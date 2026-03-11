#!/usr/bin/env bash

sync_openclaw_model_config() {
  local openclaw_config="${HOME}/.openclaw/openclaw.json"
  [[ -f "$openclaw_config" ]] || return 0
  require_jq

  local base_url model_name provider api_key
  base_url="$(env_get OPENCLAW_MODEL_BASE_URL || true)"
  model_name="$(env_get OPENCLAW_MODEL_NAME || true)"
  provider="$(env_get OPENCLAW_MODEL_PROVIDER || printf 'openai-compatible')"
  api_key="$(json_get "$SECRETS_FILE" '.["model.api_key"] // empty' 2>/dev/null || true)"

  [[ -n "$model_name" ]] || return 0

  local provider_prefix
  case "$provider" in
    anthropic) provider_prefix="anthropic" ;;
    openai)    provider_prefix="openai" ;;
    *)         provider_prefix="custom" ;;
  esac

  local model_ref="${provider_prefix}/${model_name}"
  local tmp="${openclaw_config}.tmp"

  local env_key
  case "$provider_prefix" in
    anthropic) env_key="ANTHROPIC_API_KEY" ;;
    openai)    env_key="OPENAI_API_KEY" ;;
    *)         env_key="OPENAI_API_KEY" ;;
  esac

  if [[ -n "$base_url" ]]; then
    if [[ -n "$api_key" ]]; then
      jq --arg model "$model_ref" --arg alias "$model_name" \
         --arg provider "$provider_prefix" --arg baseUrl "$base_url" \
         --arg envKey "$env_key" --arg apiKey "$api_key" \
         '.agents.defaults.model.primary = $model
         | .agents.defaults.models[$model] = { alias: $alias }
         | .models.providers[$provider] = { baseUrl: $baseUrl }
         | .env[$envKey] = $apiKey' \
         "$openclaw_config" >"$tmp"
    else
      jq --arg model "$model_ref" --arg alias "$model_name" \
         --arg provider "$provider_prefix" --arg baseUrl "$base_url" \
         '.agents.defaults.model.primary = $model
         | .agents.defaults.models[$model] = { alias: $alias }
         | .models.providers[$provider] = { baseUrl: $baseUrl }' \
         "$openclaw_config" >"$tmp"
    fi
  else
    if [[ -n "$api_key" ]]; then
      jq --arg model "$model_ref" --arg alias "$model_name" \
         --arg envKey "$env_key" --arg apiKey "$api_key" \
         '.agents.defaults.model.primary = $model
         | .agents.defaults.models[$model] = { alias: $alias }
         | .env[$envKey] = $apiKey' \
         "$openclaw_config" >"$tmp"
    else
      jq --arg model "$model_ref" --arg alias "$model_name" \
         '.agents.defaults.model.primary = $model
         | .agents.defaults.models[$model] = { alias: $alias }' \
         "$openclaw_config" >"$tmp"
    fi
  fi
  mv "$tmp" "$openclaw_config"
}

simple_openclaw_model() {
  local action="${1:-list}"
  shift || true

  case "$action" in
    set)
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --base-url)
            env_set "OPENCLAW_MODEL_BASE_URL" "$2"
            shift 2
            ;;
          --api-key)
            "$ROOT_DIR/bin/simple-openclaw" secret set model.api_key "$2" >/dev/null
            shift 2
            ;;
          --model)
            env_set "OPENCLAW_MODEL_NAME" "$2"
            shift 2
            ;;
          --provider)
            env_set "OPENCLAW_MODEL_PROVIDER" "$2"
            shift 2
            ;;
          *)
            die "unknown model option: $1"
            ;;
        esac
      done
      sync_openclaw_model_config
      info "model configuration updated"
      ;;
    list)
      printf 'provider=%s\n' "$(env_get OPENCLAW_MODEL_PROVIDER || printf 'openai-compatible')"
      printf 'base_url=%s\n' "$(env_get OPENCLAW_MODEL_BASE_URL || true)"
      printf 'model=%s\n' "$(env_get OPENCLAW_MODEL_NAME || true)"
      ;;
    test)
      local base_url model_name
      base_url="$(env_get OPENCLAW_MODEL_BASE_URL || true)"
      model_name="$(env_get OPENCLAW_MODEL_NAME || true)"
      [[ -n "$base_url" ]] || die "OPENCLAW_MODEL_BASE_URL is not configured"
      [[ -n "$model_name" ]] || die "OPENCLAW_MODEL_NAME is not configured"
      printf 'model_test=ok provider=%s url=%s model=%s\n' \
        "$(env_get OPENCLAW_MODEL_PROVIDER || printf 'openai-compatible')" "$base_url" "$model_name"
      ;;
    *)
      die "unknown model action: $action"
      ;;
  esac
}
